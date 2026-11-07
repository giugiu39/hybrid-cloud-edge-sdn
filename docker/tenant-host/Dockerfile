# =============================================================================
# sdn-host - immagine base per gli host del Data Center SDN
#
# Usata (per ora) da TUTTI i nodi finali della topologia:
#   - client dei Tenant A e B
#   - server backend (che avviano un piccolo web server Python)
#
# Build (dalla radice del repository):
#   docker build -t sdn-host:latest docker/tenant-host
# =============================================================================
FROM ubuntu:22.04

# Evita le domande interattive di apt durante la build
ENV DEBIAN_FRONTEND=noninteractive

# Strumenti necessari:
#   iproute2, net-tools -> Containernet configura IP e banda con "ip", "ifconfig", "tc"
#   iputils-ping        -> test di raggiungibilità (ping)
#   iperf3              -> generazione di traffico e misura della banda (congestione)
#   curl                -> richieste HTTP verso il load balancer
#   tcpdump             -> cattura pacchetti dentro il container
#   python3             -> web server dei backend (python3 -m http.server)
#   traceroute          -> verifica del percorso seguito dai pacchetti
RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 net-tools iputils-ping iperf3 curl tcpdump python3 traceroute \
    && rm -rf /var/lib/apt/lists/*

# Containernet avvia il container con una shell e poi vi esegue i comandi:
# la shell deve restare viva, quindi il comando di default è bash.
CMD ["/bin/bash"]
