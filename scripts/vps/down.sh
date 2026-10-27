#!/usr/bin/env bash
# Desmonta el entorno: desinstala k3s del VPS (borra el cluster y sus datos, incluidos los volumenes) y el kubeconfig local.
# Uso: scripts/vps/down.sh <ip> [--agent <ip2>] [--ssh-user u] [--ssh-key k] --yes      (no toca la VM/maquina en si)
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/vps/lib.sh
IP=${1:?uso: $0 <ip> [--agent <ip2>] --yes}; shift
AGENT=""; YES=0
while [ $# -gt 0 ]; do case "$1" in --agent) AGENT=$2; shift 2;; --ssh-user) SSH_USER=$2; shift 2;; --ssh-key) SSH_KEY=$2; shift 2;; --yes) YES=1; shift;; *) die "opcion desconocida: $1";; esac; done
[ "$YES" = 1 ] || die "esto destruye el cluster y sus datos (bases, respaldos internos). Repita con --yes"
[ -z "$AGENT" ] || rssh "$AGENT" 'if [ -x /usr/local/bin/k3s-agent-uninstall.sh ]; then sudo /usr/local/bin/k3s-agent-uninstall.sh; fi' || true
rssh "$IP" 'if [ -x /usr/local/bin/k3s-uninstall.sh ]; then sudo /usr/local/bin/k3s-uninstall.sh; else echo "k3s no estaba instalado"; fi'
rm -f "$VPS_KUBECONFIG"
echo "k3s desinstalado de $IP"
