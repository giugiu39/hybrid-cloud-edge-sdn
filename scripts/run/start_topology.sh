#!/usr/bin/env bash
# =============================================================================
# start_topology.sh - Avvia il Data Plane (Containernet) con i permessi di root
#
# Uso:
#   bash scripts/run/start_topology.sh [--bw MBIT]
#
# Avvia PRIMA il controller (start_controller.sh) in un altro terminale:
# è lui che pulisce anche i residui delle esecuzioni precedenti.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONTAINERNET_VENV="${HOME}/containernet/venv"

# Verifica che l'immagine Docker degli host esista
if ! docker image inspect sdn-host:latest >/dev/null 2>&1; then
  echo "[!] Immagine sdn-host:latest assente. Creala con:" >&2
  echo "    docker build -t sdn-host:latest ${REPO_DIR}/docker/tenant-host" >&2
  exit 1
fi

# Verifica che il controller sia già in ascolto (va avviato PRIMA)
if ! (exec 3<>/dev/tcp/127.0.0.1/6653) 2>/dev/null; then
  echo "[!] Nessun controller su 127.0.0.1:6653." >&2
  echo "    Avvia prima, in un altro terminale:" >&2
  echo "    bash scripts/run/start_controller.sh ryu.app.simple_switch_stp_13" >&2
  exit 1
fi

# Disattiva IPv6 sulla VM (fino al prossimo riavvio): le interfacce di Linux
# inviano in automatico pacchetti IPv6 (Router Solicitation, mDNS) che
# riempiono i log del controller di "packet in" inutili. Per il progetto
# usiamo solo IPv4.
sudo sysctl -q -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1

# shellcheck disable=SC1091
source "${CONTAINERNET_VENV}/bin/activate"

# NOTA: qui NON si esegue "mn -c": la pulizia di Mininet termina anche i
# controller (ryu-manager compreso). La fa start_controller.sh, prima di
# avviare Ryu.

# Mininet richiede root; -E e PATH mantengono il Python del venv
exec sudo -E env PATH="$PATH" python3 "${REPO_DIR}/src/topology/spine_leaf.py" "$@"
