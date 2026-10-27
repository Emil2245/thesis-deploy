#!/usr/bin/env bash
# Uso: render-seeds.sh server|agent <nombre> [<server-ip>]   |   render-seeds.sh floci <nombre>   |   render-seeds.sh vps <nombre>
# vps: imagen limpia tipo VPS (solo usuario + clave SSH, sin k3s ni Docker; ver scripts/vps/).
# server|agent requieren el token en $WORK/k3s-token; floci no (Docker + Floci, ver clusters/aws-floci/). Genera $WORK/seed-<nombre>.iso (vía contenedor).
set -euo pipefail
role=$1; name=$2; sip=${3:-}
WORK=${WORK:-/tmp/claude-1000/lab}
D=$(cd "$(dirname "$0")/../../clusters/lab/cloud-init" && pwd)
V='v1.37.1+k3s1'
pub=$(cat "${LAB_PUB:-$HOME/.ssh/tesis-lab.pub}")
if [ "$role" = floci ] || [ "$role" = vps ]; then
  tok=""; cmd=""
elif [ "$role" = server ]; then
  tok=$(cat "$WORK/k3s-token")
  cmd="curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$V' K3S_TOKEN='$tok' sh -s - server --write-kubeconfig-mode 600 --tls-san ${sip:-k3s-lab-1}"
else
  tok=$(cat "$WORK/k3s-token")
  cmd="curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$V' K3S_URL=https://$sip:6443 K3S_TOKEN='$tok' sh -s - agent"
fi
out=$WORK/seed-$name; rm -rf "$out"; mkdir -p "$out"
sed -e "s|@@NAME@@|$name|g" -e "s|@@DATE@@|$(date +%Y%m%d%H%M)|g" "$D/meta-data.tmpl" > "$out/meta-data"
if [ "$role" = floci ]; then
  F=$(cd "$D/../../aws-floci" && pwd)
  sed -e "s#@@PUBKEY@@#$pub#" -e "/@@COMPOSE@@/{r /dev/stdin" -e "d}" "$F/cloud-init/user-data.tmpl" < <(sed 's/^/      /' "$F/compose.yaml") > "$out/user-data"
elif [ "$role" = vps ]; then
  printf '#cloud-config\nusers:\n  - name: ubuntu\n    sudo: ALL=(ALL) NOPASSWD:ALL\n    shell: /bin/bash\n    lock_passwd: true\n    ssh_authorized_keys:\n      - %s\n' "$pub" > "$out/user-data"
else
  sed -e "s#@@PUBKEY@@#$pub#" -e "s#@@K3S_CMD@@#$cmd#" "$D/user-data.tmpl" > "$out/user-data"
fi
cp "$D/network-config" "$out/network-config"
if grep -riE 'thesis|tesis' "$out"; then echo "ABORT: nombre prohibido en seed" >&2; exit 1; fi
podman run --rm -v "$out:/w:Z" docker.io/library/ubuntu:24.04 bash -c \
 "apt-get update -qq && apt-get install -y -qq xorriso >/dev/null && cd /w && xorriso -as genisoimage -output /w/seed.iso -volid cidata -joliet -rock user-data meta-data network-config"
mv "$out/seed.iso" "$WORK/seed-$name.iso"; echo "$WORK/seed-$name.iso"
