#!/usr/bin/env bash
# Prueba de escalamiento: k6 (tests/load/hpa-scaling.js) contra https://propuestas.<dominio> + linea de tiempo de replicas.
# Imprime una linea de progreso por muestra (cada 10 s) y, al final, "replicas maximas listas: N" y "codigo de salida: C" (ultima linea).
# Uso: DEMO_PASSWORD=... scripts/vps/hpa-test.sh <dominio> [VU_MULT]   (el certificado de la CA propia no se verifica en k6)
set -u
cd "$(dirname "$0")/../.."
source scripts/vps/lib.sh
export KUBECONFIG="$VPS_KUBECONFIG"
D=${1:?uso: $0 <dominio> [VU_MULT]}
: "${DEMO_PASSWORD:?exportar DEMO_PASSWORD}"
OUT=${OUT:-docs/evidencias/vps/hpa}; mkdir -p "$OUT"
tests/record-timeline.sh "$OUT/timeline.csv" "${TIMELINE_SECS:-780}" &
rec=$!
date -u +%FT%TZ > "$OUT/k6-start.txt"
BASE_URL="https://propuestas.$D" VU_MULT=${2:-1} DEMO_PASSWORD="$DEMO_PASSWORD" k6 run --summary-export "$OUT/k6-summary.json" tests/load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
date -u +%FT%TZ > "$OUT/k6-end.txt"
jq 'del(.setup_data)' "$OUT/k6-summary.json" > "$OUT/k6-summary.tmp" && mv "$OUT/k6-summary.tmp" "$OUT/k6-summary.json"
wait $rec
max=$(awk -F, 'NR>1 && $4+0>m{m=$4+0} END{print m+0}' "$OUT/timeline.csv")
echo "replicas maximas listas: $max (minReplicas = 2)"
[ "$max" -gt 2 ]; rc=$?
echo "codigo de salida: $rc"
exit $rc
