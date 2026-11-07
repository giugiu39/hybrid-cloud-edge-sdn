# 01 – Topologia Spine-Leaf e piano di indirizzamento

## Topologia

```
Livello spine:        spine1 (dpid 0x01)        spine2 (dpid 0x02)
                         \    ogni leaf ha un link    /
                          \   verso OGNI spine (6)   /
Livello leaf:     leaf1 (0x11)     leaf2 (0x12)     leaf3 (0x13)
                    |    |           |    |         |     |     |
Host (Docker):     a1   b1          a2   b2       srv1  srv2  srv3
```

- **Spine-Leaf**: ogni leaf è collegata a ogni spine. Tra due leaf esistono
  sempre 2 percorsi a parità di costo (via spine1 o via spine2): è la
  ridondanza su cui si basa il traffic steering.
- **Data Plane**: Open vSwitch con OpenFlow 1.3; host = container Docker.
- **Control Plane**: controller Ryu esterno (`127.0.0.1:6653`).

## Piano di indirizzamento

Un'unica rete L2 `10.0.0.0/16`; il terzo ottetto identifica il gruppo.
L'isolamento tra tenant **non** è ottenuto con subnet o VLAN, ma con regole
OpenFlow installate dal controller (network slicing, Step successivi).

| Host | Ruolo    | IP           | MAC               | Leaf  | Porta |
|------|----------|--------------|-------------------|-------|-------|
| a1   | Tenant A | 10.0.1.1     | 00:00:00:00:01:01 | leaf1 | 3     |
| b1   | Tenant B | 10.0.2.1     | 00:00:00:00:02:01 | leaf1 | 4     |
| a2   | Tenant A | 10.0.1.2     | 00:00:00:00:01:02 | leaf2 | 3     |
| b2   | Tenant B | 10.0.2.2     | 00:00:00:00:02:02 | leaf2 | 4     |
| srv1 | Backend  | 10.0.100.1   | 00:00:00:00:64:01 | leaf3 | 3     |
| srv2 | Backend  | 10.0.100.2   | 00:00:00:00:64:02 | leaf3 | 4     |
| srv3 | Backend  | 10.0.100.3   | 00:00:00:00:64:03 | leaf3 | 5     |
| VIP  | Load balancer (virtuale) | 10.0.100.100 | – | – | – |

## Mappa delle porte degli switch

| Switch | Porta 1 | Porta 2 | Porta 3 | Porta 4 | Porta 5 |
|--------|---------|---------|---------|---------|---------|
| leaf1  | spine1  | spine2  | a1      | b1      | –       |
| leaf2  | spine1  | spine2  | a2      | b2      | –       |
| leaf3  | spine1  | spine2  | srv1    | srv2    | srv3    |
| spine1 | leaf1   | leaf2   | leaf3   | –       | –       |
| spine2 | leaf1   | leaf2   | leaf3   | –       | –       |

## Banda dei link

- leaf ↔ spine: **10 Mbit/s** (modificabile con `--bw`): collo di bottiglia
  voluto, per poter generare e misurare la congestione con `iperf3`.
- host ↔ leaf: nessun limite.

## Nota: loop e broadcast storm

La topologia contiene anelli (leaf1 → spine1 → leaf2 → spine2 → leaf1).
Un controller che inonda i broadcast (es. `simple_switch_13`) li farebbe
circolare all'infinito (**broadcast storm**). Per il primo test si usa
`simple_switch_stp_13`, che calcola uno Spanning Tree e blocca i link
ridondanti. Il controller del progetto sostituirà lo STP con la scoperta
della topologia e il calcolo dei percorsi, usando **tutti** i link.
