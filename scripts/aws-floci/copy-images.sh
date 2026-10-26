#!/usr/bin/env bash
# Copia (sin reconstruir) las imágenes de release de GHCR a ECR (Floci), preservando el digest del índice.
# Corre skopeo dentro de la VM aws-lab-1 (allí *.localhost:4566 resuelve a loopback, como pide la URI de ECR).
# Uso: copy-images.sh <tag-api> <tag-web>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
API=${1:?tag api}; WEB=${2:?tag web}
SSH="ssh -i ${LAB_KEY:-$HOME/.ssh/tesis-lab} -o BatchMode=yes ubuntu@$FLOCI_IP"
for pair in "api:$API" "web:$WEB"; do
  n=${pair%%:*}; t=${pair##*:}
  src="docker://ghcr.io/emil2245/propuestas-$n:$t"
  dst="docker://000000000000.dkr.ecr.us-east-1.localhost:4566/propuestas-$n:$t"
  $SSH "docker run --rm --network host quay.io/skopeo/stable:latest copy --all --dest-tls-verify=false $src $dst" >/dev/null
  echo "propuestas-$n:$t"
  echo "  ghcr: $(skopeo inspect --format '{{.Digest}}' "$src")"
  echo "  ecr : $(awsf ecr describe-images --repository-name propuestas-$n --image-ids imageTag=$t --query 'imageDetails[0].imageDigest' --output text)"
done
