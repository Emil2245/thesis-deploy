#!/usr/bin/env bash
# Paso 1: carga + timeline HPA. Requiere KUBECONFIG, DEMO_PASSWORD, k6 en PATH.
set -u; cd "$(dirname "$0")/.."; out=docs/evidencias/hpa; mkdir -p $out
tests/record-timeline.sh $out/timeline.csv ${TIMELINE_SECS:-900} &
rec=$!
date -u +%FT%TZ > $out/k6-start.txt
k6 run --summary-export $out/k6-summary.json tests/load/hpa-scaling.js > $out/k6-output.txt 2>&1
date -u +%FT%TZ > $out/k6-end.txt
wait $rec
