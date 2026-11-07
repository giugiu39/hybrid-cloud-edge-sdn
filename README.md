# Hybrid Cloud-Edge Infrastructure
### Software-Defined Data Center with Dynamic Load Balancing & Edge VNF Gateway

Progetto per il corso *Smart and Programmable Networks* (A.A. 2026/2027).

## Architettura
- **Fase 1 – Core Data Center SDN**: topologia Spine-Leaf emulata con
  Containernet (Mininet + Open vSwitch + Docker), controller **Ryu** con
  forwarding L2/L3, network slicing multi-tenant, load balancer L4 su VIP
  e traffic steering dinamico basato sulle statistiche delle porte.
- **Fase 2 – Edge VNF Gateway**: sede remota Cisco (VLAN, Router-on-a-Stick,
  ACL, OSPF) collegata al Data Center tramite una catena di VNF Docker
  (`vFirewall` → `vNAT`).

## Struttura del repository
| Cartella   | Contenuto                                         |
|------------|---------------------------------------------------|
| `src/`     | Codice: app Ryu (`controller/`) e topologie (`topology/`) |
| `docker/`  | Dockerfile di backend, host dei tenant e VNF      |
| `cisco/`   | File Packet Tracer / GNS3 della sede remota       |
| `scripts/` | Setup dell'ambiente e avvio degli scenari         |
| `tests/`   | Test di connettività, isolamento e prestazioni    |
| `docs/`    | Documentazione e diagrammi                        |
| `results/` | Log e grafici delle prove sperimentali            |

## Requisiti
Ubuntu 22.04 LTS (x86_64 o arm64), Docker Engine, Containernet, Ryu 4.34 (Python 3.9).
Vedi `docs/00-setup.md`.

## Stato
- [ ] Fase 1 – Setup ambiente
- [ ] Fase 1 – Topologia Spine-Leaf
- [ ] Fase 1 – Forwarding e slicing
- [ ] Fase 1 – Load balancer L4
- [ ] Fase 1 – Monitoring e steering dinamico
- [ ] Fase 2 – Sede Cisco
- [ ] Fase 2 – Catena VNF
- [ ] Integrazione end-to-end
