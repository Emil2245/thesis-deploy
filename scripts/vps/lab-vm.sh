#!/usr/bin/env bash
# Solo laboratorio: crea/destruye la VM limpia "vps-lab-1" (Ubuntu 24.04 sin nada, como la imagen de un VPS).
# Uso: scripts/vps/lab-vm.sh create|destroy|ip      (requiere acceso al PC del laboratorio: scripts/lab/winps.sh)
# Nunca toca otras VMs: el nombre esta fijado.
set -euo pipefail
cd "$(dirname "$0")/../.."
NAME=vps-lab-1
WORK=${WORK:-/tmp/claude-1000/lab}; export WORK
KEY=${LAB_KEY:-$HOME/.ssh/tesis-lab}
HOST=${LAB_HOST:-deltamontero@192.168.1.8}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ps() { scripts/lab/winps.sh "$1"; }
case "${1:?create|destroy|ip}" in
  create)
    scripts/lab/render-seeds.sh vps "$NAME" >/dev/null 2>&1
    scp -q -i "$KEY" -o BatchMode=yes "$WORK/seed-$NAME.iso" "$HOST:C:/lab/seeds/seed-$NAME.iso"
    { echo "\$Name='$NAME'; \$Cpu=4; \$MemGB=8"; grep -v '^param' scripts/lab/new-vm.ps1; } > "$T/c.ps1"
    ps "$T/c.ps1" ;;
  destroy)
    cat > "$T/d.ps1" <<P
\$n='$NAME'
if (Get-VM -Name \$n -EA SilentlyContinue) { Stop-VM -Name \$n -TurnOff -Force; Remove-VM -Name \$n -Force }
Remove-Item "C:\\lab\\vms\\\$n.vhdx" -Force -EA SilentlyContinue
"removed \$n"
P
    ps "$T/d.ps1" ;;
  ip)
    seq 2 254 | xargs -P 64 -I{} sh -c 'h=192.168.1.{}; timeout 4 ssh -i '"$KEY"' -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@$h hostname 2>/dev/null | grep -qx '"$NAME"' && echo $h' | head -1 ;;
esac
