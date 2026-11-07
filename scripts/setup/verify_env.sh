#!/usr/bin/env bash
# =============================================================================
# verify_env.sh - Controlla che tutti i componenti della Fase 1 siano pronti.
#
# Uso:   bash scripts/setup/verify_env.sh
# (non serve sudo: dove necessario lo chiede lo script stesso)
#
# Percorsi dei venv: modificali qui se li hai creati altrove.
# =============================================================================
CONTAINERNET_VENV="${HOME}/containernet/venv"
RYU_VENV="${HOME}/venvs/ryu"

OK=0; FAIL=0
check() {   # check "descrizione" comando...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "  [\e[32m OK \e[0m] %s\n" "$desc"; OK=$((OK+1))
  else
    printf "  [\e[31mFAIL\e[0m] %s\n" "$desc"; FAIL=$((FAIL+1))
  fi
}

echo "== Sistema =="
check "Ubuntu supportata (22.04+)"    grep -Eq 'VERSION_ID="(22|24|26)\.(04|10)"' /etc/os-release
check "Architettura x86_64 o arm64"  grep -Eqx 'x86_64|aarch64' <<< "$(uname -m)"
echo "  (rilevato: $(. /etc/os-release; echo "$PRETTY_NAME") - $(uname -m), $(nproc) CPU, $(free -g | awk '/Mem:/{print $2}') GB RAM)"

echo "== Docker =="
check "docker installato"            command -v docker
check "demone docker attivo"         systemctl is-active --quiet docker
check "utente nel gruppo docker"     grep -qw docker <<< "$(id -nG "${USER:-$(whoami)}")"
check "docker run hello-world"       docker run --rm hello-world

echo "== Open vSwitch =="
check "ovs-vsctl installato"         command -v ovs-vsctl
check "servizio OVS attivo"          sudo ovs-vsctl show

echo "== Containernet / Mininet =="
check "venv Containernet presente"   test -f "${CONTAINERNET_VENV}/bin/activate"
check "modulo mininet importabile"   "${CONTAINERNET_VENV}/bin/python" -c "import mininet.net"
check "classe Docker di Containernet" "${CONTAINERNET_VENV}/bin/python" -c "from mininet.node import Docker"

echo "== Ryu =="
check "venv Ryu (Python 3.9)"        "${RYU_VENV}/bin/python" -c "import sys; assert sys.version_info[:2]==(3,9)"
check "ryu-manager --version"        "${RYU_VENV}/bin/ryu-manager" --version
check "import ryu.ofproto.ofproto_v1_3" "${RYU_VENV}/bin/python" -c "import ryu.ofproto.ofproto_v1_3"

echo
echo "Risultato: ${OK} OK, ${FAIL} FAIL"
[ "$FAIL" -eq 0 ] && echo "Ambiente pronto per lo Step 1.2." || echo "Correggi i punti in FAIL prima di proseguire."
