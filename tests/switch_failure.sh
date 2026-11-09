#!/usr/bin/env bash
# =============================================================================
# switch_failure.sh - Simula il guasto e il ripristino di uno switch OVS
#
# Uso (da un terminale separato, con la topologia avviata):
#   sudo bash tests/switch_failure.sh fail    spine1
#   sudo bash tests/switch_failure.sh restore spine1
#
# Come funziona
#   fail    -> elimina il bridge OVS ("ovs-vsctl del-br"): spariscono Data Plane
#              e connessione OpenFlow. Le interfacce veth restano accese, quindi
#              i vicini NON ricevono un "link down": devono accorgersi del
#              guasto da soli (come quando si blocca il software di uno switch).
#   restore -> ricrea il bridge con lo stesso DPID e gli stessi numeri di porta
#              e lo ricollega al controller.
#
# Perché non usare "switch spine1 stop/start" della CLI di Mininet?
#   In questa versione "stop" termina anche la shell interna del nodo e il
#   successivo "start" va in errore, smontando l'intera rete.
# =============================================================================
set -euo pipefail

ACTION="${1:-}"
SW="${2:-spine1}"
CONTROLLER="tcp:127.0.0.1:6653"

# DPID fissi della topologia (devono coincidere con src/topology/spine_leaf.py)
declare -A DPID=(
  [spine1]=0000000000000001 [spine2]=0000000000000002
  [leaf1]=0000000000000011  [leaf2]=0000000000000012  [leaf3]=0000000000000013
)

if [ "$(id -u)" -ne 0 ]; then
  echo "Esegui con sudo: sudo bash $0 $*" >&2; exit 1
fi
if [ -z "${DPID[$SW]:-}" ]; then
  echo "Switch sconosciuto: $SW (validi: ${!DPID[*]})" >&2; exit 1
fi

ts() { date +%H:%M:%S.%3N; }   # orario con millisecondi, per misurare i tempi

case "$ACTION" in
  fail)
    ovs-vsctl --if-exists del-br "$SW"
    echo "[$(ts)] GUASTO: bridge $SW eliminato (veth ancora accese)"
    ;;

  restore)
    if ovs-vsctl br-exists "$SW"; then
      echo "Il bridge $SW esiste già: niente da ripristinare." >&2; exit 1
    fi
    # Interfacce dello switch rimaste nel sistema (es. spine1-eth1@leaf1-eth1)
    mapfile -t PORTS < <(ip -o link show | awk -F': ' '{print $2}' \
                          | cut -d@ -f1 | grep "^${SW}-eth" | sort -V)
    if [ "${#PORTS[@]}" -eq 0 ]; then
      echo "Nessuna interfaccia ${SW}-ethN trovata: la topologia è attiva?" >&2; exit 1
    fi

    # Ricrea il bridge con la stessa configurazione usata da Mininet
    ARGS=(-- add-br "$SW"
          -- set bridge "$SW" other_config:datapath-id="${DPID[$SW]}"
             fail_mode=secure protocols=OpenFlow13
             other-config:disable-in-band=true)
    for p in "${PORTS[@]}"; do
      n="${p##*eth}"                      # spine1-eth2 -> porta OpenFlow 2
      ARGS+=(-- add-port "$SW" "$p" -- set Interface "$p" ofport_request="$n")
    done
    ovs-vsctl "${ARGS[@]}"
    ovs-vsctl set-controller "$SW" "$CONTROLLER"
    echo "[$(ts)] RIPRISTINO: bridge $SW ricreato (porte: ${PORTS[*]}) e ricollegato a $CONTROLLER"
    ;;

  *)
    echo "Uso: sudo bash $0 {fail|restore} <switch>" >&2; exit 1
    ;;
esac
