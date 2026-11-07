#!/usr/bin/env python3
# =============================================================================
# spine_leaf.py - Data Plane del Data Center SDN (Fase 1)
#
# Crea con Containernet una topologia Spine-Leaf a due livelli:
#
#   Livello spine:        spine1 (0x01)          spine2 (0x02)
#                              \   ogni leaf ha un link   /
#                               \  verso OGNI spine (6)  /
#   Livello leaf:     leaf1 (0x11)     leaf2 (0x12)     leaf3 (0x13)
#                       |    |           |    |         |     |     |
#   Host (Docker):     a1   b1          a2   b2       srv1  srv2  srv3
#
#   - 2 spine e 3 leaf: switch Open vSwitch (OpenFlow 1.3)
#   - host = container Docker (immagine sdn-host)
#   - Tenant A (a1, a2) e Tenant B (b1, b2) condividono gli stessi switch
#   - 3 backend (srv1-3) su leaf3, dietro il futuro VIP del load balancer
#   - il Control Plane è ESTERNO: un controller Ryu su 127.0.0.1:6653
#
# Uso (con il controller già avviato in un altro terminale):
#   bash scripts/run/start_topology.sh            # banda spine-leaf 10 Mbit/s
#   bash scripts/run/start_topology.sh --bw 20    # banda personalizzata
# =============================================================================
import argparse

from mininet.net import Containernet
from mininet.node import RemoteController, OVSSwitch
from mininet.link import TCLink, Link
from mininet.cli import CLI
from mininet.log import info, setLogLevel

# -----------------------------------------------------------------------------
# Parametri generali
# -----------------------------------------------------------------------------
CONTROLLER_IP = "127.0.0.1"
CONTROLLER_PORT = 6653
DOCKER_IMAGE = "sdn-host:latest"
DEFAULT_FABRIC_BW = 10      # Mbit/s dei link leaf<->spine: sono il collo di
                            # bottiglia voluto, lì misureremo e devieremo la
                            # congestione. I link host<->leaf NON hanno limiti.

# -----------------------------------------------------------------------------
# Switch: nome -> DPID (Datapath ID, l'identificativo OpenFlow dello switch).
# Li fissiamo a mano per riconoscerli subito nei log di Ryu:
#   spine = 0x01, 0x02     leaf = 0x11, 0x12, 0x13
# -----------------------------------------------------------------------------
SPINES = {
    "spine1": "0000000000000001",
    "spine2": "0000000000000002",
}
LEAVES = {
    "leaf1": "0000000000000011",
    "leaf2": "0000000000000012",
    "leaf3": "0000000000000013",
}

# -----------------------------------------------------------------------------
# Piano di indirizzamento (una sola rete L2 10.0.0.0/16, terzo ottetto = gruppo)
#   10.0.1.0/24   Tenant A
#   10.0.2.0/24   Tenant B
#   10.0.100.0/24 Backend (il VIP sarà 10.0.100.100)
# MAC "parlanti": 00:00:00:00:<gruppo in hex>:<host>  (0x64 = 100)
#
# Porte sulle leaf: 1 -> spine1, 2 -> spine2, 3+ -> host
# (numerazione fissa: il controller la userà per decidere i percorsi)
# -----------------------------------------------------------------------------
HOSTS = [
    # nome    leaf     porta  IP/prefisso        MAC                  ruolo
    ("a1",   "leaf1", 3, "10.0.1.1/16",   "00:00:00:00:01:01", "Tenant A"),
    ("b1",   "leaf1", 4, "10.0.2.1/16",   "00:00:00:00:02:01", "Tenant B"),
    ("a2",   "leaf2", 3, "10.0.1.2/16",   "00:00:00:00:01:02", "Tenant A"),
    ("b2",   "leaf2", 4, "10.0.2.2/16",   "00:00:00:00:02:02", "Tenant B"),
    ("srv1", "leaf3", 3, "10.0.100.1/16", "00:00:00:00:64:01", "Backend"),
    ("srv2", "leaf3", 4, "10.0.100.2/16", "00:00:00:00:64:02", "Backend"),
    ("srv3", "leaf3", 5, "10.0.100.3/16", "00:00:00:00:64:03", "Backend"),
]


def build_network(fabric_bw):
    """Costruisce (senza avviarla) la rete Spine-Leaf e la restituisce."""
    net = Containernet(controller=RemoteController, switch=OVSSwitch,
                       link=TCLink, autoSetMacs=False)

    info("*** Controller remoto (Ryu) su %s:%d\n" % (CONTROLLER_IP, CONTROLLER_PORT))
    net.addController("c0", controller=RemoteController,
                      ip=CONTROLLER_IP, port=CONTROLLER_PORT)

    info("*** Switch spine e leaf (Open vSwitch, OpenFlow 1.3)\n")
    switches = {}
    for name, dpid in {**SPINES, **LEAVES}.items():
        switches[name] = net.addSwitch(name, dpid=dpid, protocols="OpenFlow13")

    info("*** Link leaf <-> spine (full mesh, %d Mbit/s)\n" % fabric_bw)
    # Porta della leaf  = indice della spine (spine1 -> 1, spine2 -> 2)
    # Porta della spine = indice della leaf  (leaf1 -> 1, leaf2 -> 2, leaf3 -> 3)
    for leaf_idx, leaf in enumerate(LEAVES, start=1):
        for spine_idx, spine in enumerate(SPINES, start=1):
            net.addLink(switches[leaf], switches[spine],
                        port1=spine_idx, port2=leaf_idx,
                        cls=TCLink, bw=fabric_bw)

    info("*** Container Docker (host dei tenant e backend)\n")
    hosts = {}
    for name, leaf, port, ip, mac, _role in HOSTS:
        hosts[name] = net.addDocker(name, ip=ip, mac=mac, dimage=DOCKER_IMAGE)
        # Link semplice (senza limite di banda): evita gli avvisi di "tc htb"
        # e lascia come unico collo di bottiglia il fabric leaf<->spine.
        net.addLink(hosts[name], switches[leaf], port2=port, cls=Link)

    return net, hosts


def start_backends(hosts):
    """Avvia su ogni backend un web server che risponde con il proprio nome."""
    for name, _leaf, _port, _ip, _mac, role in HOSTS:
        if role != "Backend":
            continue
        h = hosts[name]
        h.cmd("mkdir -p /srv/www")
        h.cmd("echo 'Risposta dal backend %s' > /srv/www/index.html" % name)
        h.cmd("python3 -m http.server 80 --directory /srv/www > /tmp/http.log 2>&1 &")
        info("    %s: web server attivo sulla porta 80\n" % name)


def print_summary(fabric_bw):
    info("\n*** Piano di indirizzamento\n")
    info("    %-5s %-6s %-6s %-15s %-18s %s\n"
         % ("HOST", "LEAF", "PORTA", "IP", "MAC", "RUOLO"))
    for name, leaf, port, ip, mac, role in HOSTS:
        info("    %-5s %-6s %-6d %-15s %-18s %s\n" % (name, leaf, port, ip, mac, role))
    info("\n    Link leaf<->spine: %d Mbit/s | host<->leaf: senza limite\n" % fabric_bw)
    info("    Attendi la convergenza dello STP (circa 30-60 s) prima dei test.\n\n")


def main():
    parser = argparse.ArgumentParser(description="Topologia Spine-Leaf (Fase 1)")
    parser.add_argument("--bw", type=int, default=DEFAULT_FABRIC_BW,
                        help="banda dei link leaf<->spine in Mbit/s (default 10)")
    args = parser.parse_args()

    setLogLevel("info")
    net, hosts = build_network(args.bw)
    try:
        net.start()
        start_backends(hosts)
        print_summary(args.bw)
        CLI(net)
    finally:
        # Anche in caso di errore o Ctrl+D: rimuove switch, link e container
        net.stop()


if __name__ == "__main__":
    main()
