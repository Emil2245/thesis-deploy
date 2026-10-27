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
wait $rec
kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api -o wide --no-headers | awk '{print $1,$7}' > "$OUT/api-pods-nodes.txt" || true
