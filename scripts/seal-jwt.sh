#!/usr/bin/env bash
# Genera un par RSA-2048 efimero y escribe el SealedSecret propuestas-jwt para un overlay.
# Uso: scripts/seal-jwt.sh <local|prod>   (requiere kubectl apuntando al cluster destino y kubeseal)
set -euo pipefail
ENV="${1:?uso: $0 <local|prod>}"
case "$ENV" in local|prod) ;; *) echo "env invalido: $ENV" >&2; exit 1;; esac
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
command -v kubeseal >/dev/null || { echo "falta kubeseal (scripts/install-tools.sh)" >&2; exit 1; }
OUT="k8s/propuestas/overlays/$ENV/sealed-jwt.yaml"
T="$(mktemp -d)"; chmod 700 "$T"
cleanup(){ find "$T" -type f -exec shred -u {} + 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/privateKey.pem" 2>/dev/null
openssl rsa -in "$T/privateKey.pem" -pubout -out "$T/publicKey.pem" 2>/dev/null
kubectl create secret generic propuestas-jwt --namespace propuestas \
  --from-file=privateKey.pem="$T/privateKey.pem" --from-file=publicKey.pem="$T/publicKey.pem" \
  --dry-run=client -o yaml \
| kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system \
  > "$OUT"
echo "Escrito $OUT (solo contiene datos cifrados). Descomentalo en el kustomization del overlay."
