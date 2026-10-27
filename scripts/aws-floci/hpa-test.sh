#!/usr/bin/env bash
# Prueba HPA a través del ALB: k6 (imagen fijada) + línea de tiempo de réplicas.
# Requiere DEMO_PASSWORD en el entorno (no se imprime), podman o docker.
set -u
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
OUT=${OUT:-docs/evidencias/aws-floci/hpa}; mkdir -p "$OUT"
K6_IMAGE=docker.io/grafana/k6:2.3.0
tests/record-timeline.sh "$OUT/timeline.csv" "${TIMELINE_SECS:-780}" &
rec=$!
# reparto de las réplicas de la API por nodo, cada 30 s (evidencia de que las 6 se programan en >= 2 nodos)
( end=$((SECONDS+${TIMELINE_SECS:-780})); : > "$OUT/pods-por-nodo.log"
  while [ $SECONDS -lt $end ]; do
    echo "$(date -u +%FT%TZ) $(kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')" >> "$OUT/pods-por-nodo.log"
    sleep 30
  done ) &
pn=$!
date -u +%FT%TZ > "$OUT/k6-start.txt"
K6=${K6_BIN:-$(command -v k6 || true)}
if [ -n "$K6" ]; then   # k6 local (use la versión 2.3.0 o superior)
  BASE_URL="http://$FLOCI_IP:8080" DEMO_PASSWORD="$DEMO_PASSWORD" "$K6" run --summary-export "$OUT/k6-summary.json" tests/load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
else
  RT=$(command -v podman || command -v docker)
  $RT run --rm --network host -e BASE_URL="http://$FLOCI_IP:8080" -e DEMO_PASSWORD="$DEMO_PASSWORD" \
    -v "$PWD/tests/load:/load:ro,Z" -v "$PWD/$OUT:/out:Z" "$K6_IMAGE" run --summary-export /out/k6-summary.json /load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
fi
date -u +%FT%TZ > "$OUT/k6-end.txt"
# el resumen de k6 incluye el token de setup(): se elimina antes de guardarlo
jq 'del(.setup_data)' "$OUT/k6-summary.json" > "$OUT/k6-summary.tmp" && mv "$OUT/k6-summary.tmp" "$OUT/k6-summary.json"
wait $rec $pn
kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api -o wide --no-headers | awk '{print $1,$7}' > "$OUT/api-pods-nodes.txt" || true
