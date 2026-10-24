#!/usr/bin/env bash
# Paso 3b: apaga una VM del lab (Hyper-V) bajo carga, observa reprogramacion y la vuelve a encender.
# Uso: node-failure.sh <vm> <tag>   (p. ej. k3s-lab-2 node)
set -u; cd "$(dirname "$0")/../.."; vm=$1; tag=$2; out=docs/evidencias/chaos; mkdir -p $out
psf=$(mktemp --suffix=.ps1); trap 'rm -f $psf' EXIT
VUS=10 DURATION=${DURATION:-6m} k6 run --summary-export $out/$tag-k6-summary.json tests/load/constant.js > $out/$tag-k6-output.txt 2>&1 &
k=$!
( kubectl get nodes -w --no-headers | while read l; do echo "$(date -u +%FT%TZ) $l"; done > $out/$tag-nodes-watch.txt ) & nw=$!
( kubectl -n propuestas get pods -o wide -w --no-headers | while read l; do echo "$(date -u +%FT%TZ) $l"; done > $out/$tag-pods-watch.txt ) & pw=$!
( kubectl -n propuestas get cluster propuestas-db -w --no-headers | while read l; do echo "$(date -u +%FT%TZ) $l"; done > $out/$tag-cnpg-watch.txt ) & cw=$!
sleep 45
echo "Stop-VM -Name $vm -TurnOff -Force" > $psf
date -u +%FT%TZ > $out/$tag-vm-stop.txt; scripts/lab/winps.sh $psf
sleep ${OUTAGE:-150}
echo "Start-VM -Name $vm" > $psf
date -u +%FT%TZ > $out/$tag-vm-start.txt; scripts/lab/winps.sh $psf
wait $k; sleep 60
pkill -P $$ -f kubectl 2>/dev/null; kill $nw $pw $cw 2>/dev/null; pkill -f "kubectl.*get .* -w" 2>/dev/null
kubectl -n propuestas get pods -o wide > $out/$tag-pods-final.txt
