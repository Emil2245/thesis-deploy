#!/usr/bin/env bash
# Copia (sin reconstruir) las imágenes de release de GHCR a ECR (Floci), preservando el digest del índice.
# Corre skopeo dentro de la VM aws-lab-1 (allí *.localhost:4566 resuelve a loopback, como pide la URI de ECR).
# Uso: copy-images.sh <tag-api> <tag-web>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
API=${1:?tag api}; WEB=${2:?tag web}
for pair in "api:$API" "web:$WEB"; do
  n=${pair%%:*}; t=${pair##*:}
  src="docker://ghcr.io/emil2245/propuestas-$n:$t"
  dst="docker://000000000000.dkr.ecr.us-east-1.localhost:4566/propuestas-$n:$t"
  g=$(skopeo inspect --format '{{.Digest}}' "$src")   # digest del indice (lo que publica GHCR)
  e=$(awsf ecr describe-images --repository-name propuestas-$n --image-ids imageTag=$t --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)
  echo "propuestas-$n:$t"
  if [ "$e" = "$g" ]; then
    echo "  (la etiqueta ya existe en ECR con el mismo digest: no se copia)"
  else
    # ECR tiene etiquetas inmutables: si existe con otro digest no se puede sobrescribir
    [ -z "$e" ] || [ "$e" = None ] || die "propuestas-$n:$t ya existe en ECR con otro digest ($e); la etiqueta es inmutable (use otra etiqueta o ejecute down.sh --reset)"
    $SSH "docker run -q --rm --network host quay.io/skopeo/stable:latest copy --all --dest-tls-verify=false $src $dst" >/dev/null 2>&1 \
      || die "fallo skopeo copy de $src a ECR"
    e=$(awsf ecr describe-images --repository-name propuestas-$n --image-ids imageTag=$t --query 'imageDetails[0].imageDigest' --output text)
  fi
  echo "  ghcr: $g"
  echo "  ecr : $e"
  [ "$e" = "$g" ] || die "los digests no coinciden"
done
