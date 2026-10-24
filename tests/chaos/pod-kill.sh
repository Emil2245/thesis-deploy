#!/usr/bin/env bash
# Paso 3a: carga constante 3 min; cada 30 s borra un pod api aleatorio; al final un pod web.
set -u; cd "$(dirname "$0")/../.."; out=docs/evidencias/chaos; mkdir -p $out
VUS=10 DURATION=3m k6 run --summary-export $out/pod-kill-k6-summary.json tests/load/constant.js > $out/pod-kill-k6-output.txt 2>&1 &
k=$!
: > $out/pod-kill-log.txt
for i in 1 2 3 4 5; do
  sleep 30
  if [ $i -eq 5 ]; then sel=propuestas-web; else sel=propuestas-api; fi
  pod=$(kubectl -n propuestas get pods -l app.kubernetes.io/name=$sel --field-selector=status.phase=Running -o name | shuf -n1)
  echo "$(date -u +%FT%TZ) delete $pod" | tee -a $out/pod-kill-log.txt
  kubectl -n propuestas delete $pod --wait=false >> $out/pod-kill-log.txt
done
wait $k
kubectl -n propuestas get events --sort-by=.lastTimestamp > $out/pod-kill-events.txt
