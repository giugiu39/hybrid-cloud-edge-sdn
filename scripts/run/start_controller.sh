#!/usr/bin/env bash
# =============================================================================
# start_controller.sh - Avvia il Control Plane (Ryu) nel suo venv Python 3.9
#
# Uso:
#   bash scripts/run/start_controller.sh <app-ryu> [altre opzioni ryu-manager]
# Esempi:
#   bash scripts/run/start_controller.sh ryu.app.simple_switch_stp_13
#   bash scripts/run/start_controller.sh src/controller/mia_app.py --verbose
# =============================================================================
set -euo pipefail

RYU_VENV="${HOME}/venvs/ryu"
OF_PORT=6653                       # porta standard IANA di OpenFlow

if [ $# -lt 1 ]; then
  echo "Uso: $0 <app-ryu> [opzioni]" >&2
  exit 1
fi

# 1) Pulizia dei residui di Mininet (switch OVS, veth, container "mn.*").
#    Va fatta QUI, prima di avviare Ryu: "mn -c" termina anche i processi
#    ryu-manager, quindi lanciarla dopo ucciderebbe il controller.
CONTAINERNET_MN="${HOME}/containernet/venv/bin/mn"
echo "[*] Pulizia residui Mininet (password sudo se richiesta)..."
sudo env PATH="$(dirname "${CONTAINERNET_MN}"):${PATH}" "${CONTAINERNET_MN}" -c >/dev/null 2>&1 || true

# 2) Avvio di Ryu nel suo venv Python 3.9
# shellcheck disable=SC1091
source "${RYU_VENV}/bin/activate"
echo "[*] Ryu in ascolto su TCP ${OF_PORT} - app: $*"
exec ryu-manager --ofp-tcp-listen-port "${OF_PORT}" "$@"
