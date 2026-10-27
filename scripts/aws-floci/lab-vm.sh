#!/usr/bin/env bash
# Solo laboratorio (Hyper-V del PC del laboratorio): crea/destruye la VM "aws-lab-1" (Ubuntu 24.04 + Docker + Floci por cloud-init).
# Uso: scripts/aws-floci/lab-vm.sh create|destroy|ip      (requiere acceso al PC del laboratorio: scripts/lab/winps.sh)
#   create : genera el seed cloud-init (render-seeds.sh floci), lo copia al PC, crea y arranca la VM (4 vCPU, 12 GB),
#            espera su IP y que Floci responda, y escribe "export FLOCI_IP=<ip>" como ultima linea.
#   destroy: apaga y borra la VM, su disco y el ISO del seed (la imagen base C:\lab\images\noble-base.vhdx no se toca).
#   ip     : imprime la IP de la VM (barrido SSH de la LAN buscando el nombre de host).
# Nunca toca otras VMs: el nombre esta fijado. Variables: LAB_KEY (clave privada), LAB_PUB (clave publica, defecto $LAB_KEY.pub),
# LAB_HOST (usuario@pc del laboratorio), WORK (carpeta del ISO; defecto ~/.cache/propuestas-floci/seeds).
# En otro hipervisor este script no sirve: vease el capitulo 3 del manual (ruta generica).
set -euo pipefail
cd "$(dirname "$0")/../.."
NAME=aws-lab-1
KEY=${LAB_KEY:-$HOME/.ssh/tesis-lab}
export LAB_PUB=${LAB_PUB:-$KEY.pub}
HOST=${LAB_HOST:-deltamontero@192.168.1.8}
WORK=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-floci/seeds}; export WORK; mkdir -p "$WORK"
export TMPDIR=${TMPDIR_LAB:-${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-floci/tmp}; mkdir -p "$TMPDIR"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ps() { scripts/lab/winps.sh "$1"; }
buscar_ip() {
  seq 2 254 | xargs -P 64 -I{} sh -c 'h=192.168.1.{}; timeout 4 ssh -i '"$KEY"' -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@$h hostname 2>/dev/null | grep -qx '"$NAME"' && echo $h' | head -1
}
case "${1:?create|destroy|ip}" in
  create)
    [ -r "$LAB_PUB" ] || { echo "ERROR: no existe la clave publica '$LAB_PUB' (exporte LAB_KEY o LAB_PUB)" >&2; exit 1; }
    cat > "$T/p.ps1" <<P
if (-not (Test-Path C:\\lab\\images\\noble-base.vhdx)) { "FALTA la imagen base C:\\lab\\images\\noble-base.vhdx"; exit 1 }
if (Get-VM -Name '$NAME' -EA SilentlyContinue) { "YA EXISTE la VM $NAME: ejecute primero 'lab-vm.sh destroy'"; exit 1 }
"ok"
P
    [ "$(ps "$T/p.ps1" | tr -d "\r" | tail -1)" = ok ] || { ps "$T/p.ps1" >&2; exit 1; }
    scripts/lab/render-seeds.sh floci "$NAME" >/dev/null 2>&1 || { echo "ERROR: render-seeds.sh fallo (se necesita podman o docker y la clave publica)" >&2; exit 1; }
    scp -q -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$WORK/seed-$NAME.iso" "$HOST:C:/lab/seeds/seed-$NAME.iso"
    { echo "\$Name='$NAME'; \$Cpu=4; \$MemGB=12"; grep -v '^param' scripts/lab/new-vm.ps1; } > "$T/c.ps1"
    ps "$T/c.ps1"
    echo "esperando la IP y a Floci (cloud-init tarda unos 10 minutos)..."
    ip=""
    for _ in $(seq 1 90); do
      [ -n "$ip" ] || ip=$(buscar_ip || true)
      if [ -n "$ip" ] && curl -fsS -m 5 "http://$ip:4566/_floci/health" >/dev/null 2>&1; then break; fi
      sleep 10
    done
    [ -n "$ip" ] || { echo "ERROR: la VM no aparecio en la LAN en 15 minutos" >&2; exit 1; }
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true   # la clave de host de una VM anterior con la misma IP ya no vale
    curl -fsS -m 5 "http://$ip:4566/_floci/health" >/dev/null || { echo "ERROR: Floci no responde en $ip:4566" >&2; exit 1; }
    echo "$NAME lista en $ip (Floci responde)"
    echo "export FLOCI_IP=$ip" ;;
  destroy)
    cat > "$T/d.ps1" <<P
\$n='$NAME'
if (Get-VM -Name \$n -EA SilentlyContinue) { Stop-VM -Name \$n -TurnOff -Force; Remove-VM -Name \$n -Force }
Remove-Item "C:\\lab\\vms\\\$n.vhdx" -Force -EA SilentlyContinue
Remove-Item "C:\\lab\\seeds\\seed-\$n.iso" -Force -EA SilentlyContinue
"removed \$n"
P
    ps "$T/d.ps1" ;;
  ip) buscar_ip ;;
esac
