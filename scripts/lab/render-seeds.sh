#!/usr/bin/env bash
# Uso: render-seeds.sh server|agent <nombre> [<server-ip>]
# Requiere K3S_TOKEN en $WORK/k3s-token. Genera $WORK/seed-<nombre>.iso (vía contenedor).
set -euo pipefail
role=$1; name=$2; sip=${3:-}
WORK=${WORK:-/tmp/claude-1000/lab}
D=$(cd "$(dirname "$0")/../../clusters/lab/cloud-init" && pwd)
V='v1.37.1+k3s1'
tok=$(cat "$WORK/k3s-token")
pub=$(cat "${LAB_PUB:-$HOME/.ssh/tesis-lab.pub}")
if [ "$role" = server ]; then
  cmd="curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$V' K3S_TOKEN='$tok' sh -s - server --write-kubeconfig-mode 600 --tls-san ${sip:-k3s-lab-1}"
else
  cmd="curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$V' K3S_URL=https://$sip:6443 K3S_TOKEN='$tok' sh -s - agent"
fi
out=$WORK/seed-$name; rm -rf "$out"; mkdir -p "$out"
sed -e "s|@@NAME@@|$name|g" -e "s|@@DATE@@|$(date +%Y%m%d%H%M)|g" "$D/meta-data.tmpl" > "$out/meta-data"
sed -e "s#@@PUBKEY@@#$pub#" -e "s#@@K3S_CMD@@#$cmd#" "$D/user-data.tmpl" > "$out/user-data"
cp "$D/network-config" "$out/network-config"
if grep -riE 'thesis|tesis' "$out"; then echo "ABORT: nombre prohibido en seed" >&2; exit 1; fi
podman run --rm -v "$out:/w:Z" docker.io/library/ubuntu:24.04 bash -c \
 "apt-get update -qq && apt-get install -y -qq xorriso >/dev/null && cd /w && xorriso -as genisoimage -output /w/seed.iso -volid cidata -joliet -rock user-data meta-data network-config"
mv "$out/seed.iso" "$WORK/seed-$name.iso"; echo "$WORK/seed-$name.iso"
