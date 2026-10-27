#!/usr/bin/env bash
# Secrets Manager (Floci) -> Secrets de Kubernetes del EKS emulado. No imprime valores.
#   propuestas/db  -> propuestas-db-app (username, password)
#   propuestas/jwt -> propuestas-jwt (privateKey.pem, publicKey.pem)
# BREAK-GLASS (plan 040): el flujo normal es External Secrets Operator (k8s/platform/aws-floci/eso-config). Este script solo sirve
# para recuperar los Secrets si ESO no estuviera disponible; no crea ninguna clave de acceso.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
NS=propuestas
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null

db=$(awsf secretsmanager get-secret-value --secret-id propuestas/db --query SecretString --output text)
jwt=$(awsf secretsmanager get-secret-value --secret-id propuestas/jwt --query SecretString --output text)
u=$(jq -r .username <<<"$db"); p=$(jq -r .password <<<"$db")
kubectl -n "$NS" create secret generic propuestas-db-app --from-literal=username="$u" --from-literal=password="$p" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
T=$(mktemp -d); chmod 700 "$T"; trap 'rm -rf "$T"' EXIT
jq -r .privateKey <<<"$jwt" > "$T/privateKey.pem"; jq -r .publicKey <<<"$jwt" > "$T/publicKey.pem"
kubectl -n "$NS" create secret generic propuestas-jwt --from-file=privateKey.pem="$T/privateKey.pem" --from-file=publicKey.pem="$T/publicKey.pem" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "secrets sincronizados en $NS: $(kubectl -n $NS get secret -o name | tr '\n' ' ')"
