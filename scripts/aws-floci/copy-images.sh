#!/usr/bin/env bash
# Copia (sin reconstruir) las imágenes de release de GHCR a ECR (Floci), preservando el digest del índice.
# Corre skopeo dentro de la VM aws-lab-1 (allí *.localhost:4566 resuelve a loopback, como pide la URI de ECR).
# IMAGES_SOURCE=local (scripts/aws-floci/local-up.sh): no usa GHCR; sube con skopeo (docker-daemon: -> ECR) las imágenes construidas
# en este equipo. No usa docker push: el certificado de Floci cubre *.localhost, no el host anidado de ECR, y docker exigiría
# declarar el registro inseguro en /etc/docker/daemon.json (sudo).
# (propuestas-<n>:<tag>). ECR tiene etiquetas inmutables: si la etiqueta ya existe, se asume la misma construcción y no se sube.
# Uso: copy-images.sh <tag-api> <tag-web> [<tag-documentos>]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
API=${1:?tag api}; WEB=${2:?tag web}; DOC=${3:-}
ECR=000000000000.dkr.ecr.us-east-1.localhost:4566
pairs=("api:$API" "web:$WEB"); [ -z "$DOC" ] || pairs+=("documentos:$DOC")
if [ "${IMAGES_SOURCE:-ghcr}" = local ]; then
  pw=$(awsf ecr get-login-password) || die "no se obtuvo el token de ECR ($ECR)"
  for pair in "${pairs[@]}"; do
    n=${pair%%:*}; t=${pair##*:}
    e=$(awsf ecr describe-images --repository-name propuestas-$n --image-ids imageTag=$t --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)
    if [ -n "$e" ] && [ "$e" != None ]; then echo "propuestas-$n:$t ya existe en ECR ($e): no se sube"; continue; fi
    docker image inspect "propuestas-$n:$t" >/dev/null 2>&1 || die "no existe la imagen local propuestas-$n:$t (la construye local-up.sh)"
    skopeo copy -q --dest-tls-verify=false --dest-creds "AWS:$pw" "docker-daemon:propuestas-$n:$t" "docker://$ECR/propuestas-$n:$t" \
      || die "fallo skopeo copy de propuestas-$n:$t a ECR"
    echo "propuestas-$n:$t -> ECR $(awsf ecr describe-images --repository-name propuestas-$n --image-ids imageTag=$t --query 'imageDetails[0].imageDigest' --output text)"
  done
  exit 0
fi
for pair in "${pairs[@]}"; do
  n=${pair%%:*}; t=${pair##*:}
  src="docker://ghcr.io/emil2245/propuestas-$n:$t"
  dst="docker://$ECR/propuestas-$n:$t"
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
