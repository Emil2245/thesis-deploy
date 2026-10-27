#!/usr/bin/env bash
# Uso: record-timeline.sh <out.csv> <segundos> ; registra HPA/replicas cada 10 s en el CSV y una linea de progreso en stdout
out=$1; dur=$2; start=$SECONDS; end=$((SECONDS+dur))
echo "timestamp,current_cpu,replicas_desired,replicas_ready" > "$out"
while [ $SECONDS -lt $end ]; do
  ts=$(date -u +%FT%TZ)
  if hpa=$(kubectl --request-timeout=8s -n propuestas get hpa propuestas-api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization},{.status.desiredReplicas}' 2>/dev/null); then
    ready=$(kubectl --request-timeout=8s -n propuestas get deploy propuestas-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    echo "${ts},${hpa},${ready:-0}" >> "$out"
    cpu=${hpa%%,*}; des=${hpa#*,}
    printf '%s t=%ss cpu=%s%% replicas deseadas=%s listas=%s\n' "$ts" "$((SECONDS-start))" "${cpu:-?}" "${des:-?}" "${ready:-0}"
  else
    echo "${ts},,," >> "$out"
    printf '%s t=%ss api no disponible\n' "$ts" "$((SECONDS-start))"
  fi
  sleep 10
done
