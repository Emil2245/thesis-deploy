#!/usr/bin/env bash
# Paso 2: rolling update bajo carga constante (10 VUs, 3 min); restart a los 30 s.
set -u; cd "$(dirname "$0")/../.."; out=docs/evidencias/rolling; mkdir -p $out
VUS=10 DURATION=3m k6 run --summary-export $out/k6-summary.json tests/load/constant.js > $out/k6-output.txt 2>&1 &
k=$!
sleep 30
date -u +%FT%TZ > $out/restart-start.txt
kubectl -n propuestas rollout restart deploy/propuestas-api
kubectl -n propuestas rollout status deploy/propuestas-api --timeout=300s | tee $out/rollout-status.txt
date -u +%FT%TZ > $out/restart-end.txt
wait $k
