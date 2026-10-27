#!/usr/bin/env bash
# Prueba HPA a traves del ALB: k6 (imagen fijada) + linea de tiempo de replicas. Requiere DEMO_PASSWORD (no se imprime), k6 o podman/docker.
# Imprime una linea de progreso por muestra (cada 10 s) y, al final: "peticiones fallidas: X % (n de N)", "replicas maximas listas: N" y "codigo de salida: C".
# Resultados en ./hpa-resultados/ (ignorado por git); otra carpeta con HPA_OUT=<dir> (p. ej. docs/evidencias/aws-floci/hpa para evidencia versionada).
# Criterio de aprobacion (exacto): codigo 0 si el maximo de replicas listas de la API supera minReplicas (2); 1 si no.
# Uso: DEMO_PASSWORD=... scripts/aws-floci/hpa-test.sh        (FLOCI_IP obligatoria; K6_BIN opcional)
set -u
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
usar_kubeconfig
: "${DEMO_PASSWORD:?exportar DEMO_PASSWORD}"
OUT=${HPA_OUT:-hpa-resultados}; mkdir -p "$OUT"
K6_IMAGE=docker.io/grafana/k6:2.3.0
tests/record-timeline.sh "$OUT/timeline.csv" "${TIMELINE_SECS:-780}" &
rec=$!
# reparto de las replicas de la API por nodo, cada 30 s (evidencia de que las 6 se programan en >= 2 nodos)
( end=$((SECONDS+${TIMELINE_SECS:-780})); : > "$OUT/pods-por-nodo.log"
  while [ $SECONDS -lt $end ]; do
    echo "$(date -u +%FT%TZ) $(kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')" >> "$OUT/pods-por-nodo.log"
    sleep 30
  done ) &
pn=$!
date -u +%FT%TZ > "$OUT/k6-start.txt"
K6=${K6_BIN:-$(command -v k6 || true)}
if [ -n "$K6" ]; then   # k6 local (version 2.3.0 o superior)
  BASE_URL="http://$FLOCI_IP:8080" DEMO_PASSWORD="$DEMO_PASSWORD" "$K6" run --summary-export "$OUT/k6-summary.json" tests/load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
else
  RT=$(command -v podman || command -v docker) || { echo "ERROR: falta k6 (scripts/install-tools.sh) o podman/docker" >&2; kill $rec $pn 2>/dev/null; exit 2; }
  $RT run --rm --network host -e BASE_URL="http://$FLOCI_IP:8080" -e DEMO_PASSWORD="$DEMO_PASSWORD" \
    -v "$PWD/tests/load:/load:ro,Z" -v "$PWD/$OUT:/out:Z" "$K6_IMAGE" run --summary-export /out/k6-summary.json /load/hpa-scaling.js > "$OUT/k6-output.txt" 2>&1
fi
date -u +%FT%TZ > "$OUT/k6-end.txt"
# el resumen de k6 incluye el token de setup(): se elimina antes de guardarlo
jq 'del(.setup_data)' "$OUT/k6-summary.json" > "$OUT/k6-summary.tmp" && mv "$OUT/k6-summary.tmp" "$OUT/k6-summary.json"
wait $rec $pn
kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api -o wide --no-headers | awk '{print $1,$7}' > "$OUT/api-pods-nodes.txt" || true
max=$(awk -F, 'NR>1 && $4+0>m{m=$4+0} END{print m+0}' "$OUT/timeline.csv")
fallidas=$(jq -r '(.metrics.http_req_failed.value // 0)*100*100|round/100' "$OUT/k6-summary.json" 2>/dev/null || echo "?")
total=$(jq -r '.metrics.http_reqs.count // 0' "$OUT/k6-summary.json" 2>/dev/null || echo "?")
nfall=$(jq -r '((.metrics.http_req_failed.value // 0)*(.metrics.http_reqs.count // 0))|round' "$OUT/k6-summary.json" 2>/dev/null || echo "?")
echo "peticiones fallidas: $fallidas % ($nfall de $total)"
echo "replicas maximas listas: $max (minReplicas = 2)"
[ "$max" -gt 2 ]; rc=$?
echo "codigo de salida: $rc"
exit $rc
