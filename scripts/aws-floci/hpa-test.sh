#!/usr/bin/env bash
# Prueba HPA a través del ALB: k6 (imagen fijada) + línea de tiempo de réplicas.
# Requiere DEMO_PASSWORD en el entorno (no se imprime), podman o docker.
set -u
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
OUT=${OUT:-docs/evidencias/aws-floci/hpa}; mkdir -p "$OUT"
K6_IMAGE=docker.io/grafana/k6:2.3.0
RT=$(command -v podman || command -v docker)
tests/record-timeline.sh "$OUT/timeline.csv" "${TIMELINE_SECS:-780}" &
rec=$!
date -u +%FT%TZ > "$OUT/k6-start.txt"
$RT run --rm --network host -e BASE_URL="http://$FLOCI_IP:8080" -e DEMO_PASSWORD="$DEMO_PASSWORD" \
  -v "$PWD/tests/load:/load:ro,Z" "$K6_IMAGE" run --summary-export /dev/stdout /load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
date -u +%FT%TZ > "$OUT/k6-end.txt"
wait $rec
