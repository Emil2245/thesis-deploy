#!/usr/bin/env bash
# Uso: record-timeline.sh <out.csv> <segundos> ; registra HPA/replicas cada 10 s en el CSV y una linea de progreso en stdout
out=$1; dur=$2; start=$SECONDS; end=$((SECONDS+dur))
echo "timestamp,current_cpu,replicas_desired,replicas_ready" > "$out"
while [ $SECONDS -lt $end ]; do
  hpa=$(kubectl -n propuestas get hpa propuestas-api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization},{.status.desiredReplicas}')
  ready=$(kubectl -n propuestas get deploy propuestas-api -o jsonpath='{.status.readyReplicas}')
  ts=$(date -u +%FT%TZ)
  echo "${ts},${hpa},${ready:-0}" >> "$out"
  cpu=${hpa%%,*}; des=${hpa#*,}
  printf '%s t=%ss cpu=%s%% replicas deseadas=%s listas=%s\n' "$ts" "$((SECONDS-start))" "${cpu:-?}" "${des:-?}" "${ready:-0}"
  sleep 10
done
