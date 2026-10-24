#!/usr/bin/env bash
# Copia los tags de imágenes de overlays/prod a overlays/lab.
set -euo pipefail
cd "$(dirname "$0")/../.."
P=k8s/propuestas/overlays
for s in api web; do
  tag=$(grep -A2 "propuestas-$s\$" $P/prod/kustomization.yaml | sed -n 's/.*newTag: //p' | head -1)
  sed -i -E "s#(propuestas-$s, newTag: )[^}]+#\1$tag#" $P/lab/kustomization.yaml
done
grep newTag $P/lab/kustomization.yaml
