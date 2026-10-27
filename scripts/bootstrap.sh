#!/usr/bin/env bash
# Uso: scripts/bootstrap.sh <local|lab|prod|vps>
set -euo pipefail
ENV="${1:?uso: bootstrap.sh <local|lab|prod|vps>}"
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
ARGOCD_CHART_VERSION=10.11.6

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" -f "k8s/argocd/values-${ENV}.yaml" --wait --timeout 10m

if [ "$ENV" = local ] || [ "$ENV" = lab ] || [ "$ENV" = vps ]; then
  kubectl create namespace propuestas --dry-run=client -o yaml | kubectl apply -f -
  if ! kubectl -n propuestas get secret propuestas-jwt >/dev/null 2>&1; then
    T="$(mktemp -d)"; trap 'shred -u "$T"/*.pem 2>/dev/null; rm -rf "$T"' EXIT
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/privateKey.pem"
    openssl rsa -pubout -in "$T/privateKey.pem" -out "$T/publicKey.pem"
    kubectl -n propuestas create secret generic propuestas-jwt \
      --from-file=privateKey.pem="$T/privateKey.pem" --from-file=publicKey.pem="$T/publicKey.pem"
  fi
fi
# SKIP_ROOT=1: el llamador (scripts/vps/up.sh) aplica su propia raiz renderizada con parches
[ -n "${SKIP_ROOT:-}" ] || kubectl apply -f "k8s/argocd/root-${ENV}.yaml"
