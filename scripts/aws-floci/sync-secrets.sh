#!/usr/bin/env bash
# Secrets Manager (Floci) -> Secrets de Kubernetes del EKS emulado. No imprime valores.
#   propuestas/db  -> propuestas-db-app (username, password)
#   propuestas/jwt -> propuestas-jwt (privateKey.pem, publicKey.pem)
#   IAM user propuestas-workload -> aws-workload-credentials en propuestas y logging (clave de acceso; sustituye pod identity)
# En AWS real se usaría External Secrets Operator o el driver Secrets Store CSI; ambos exigen
# endpoints/CRDs que no se adaptan bien a Floci, de ahí este script (decisión en docs/decisiones.md).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
NS=propuestas
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# Pod Security "restricted" como en la base (idempotente)
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
if ! kubectl -n "$NS" get secret aws-workload-credentials >/dev/null 2>&1; then
  for k in $(awsf iam list-access-keys --user-name propuestas-workload --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    awsf iam delete-access-key --user-name propuestas-workload --access-key-id "$k"
  done
  read -r id sec < <(awsf iam create-access-key --user-name propuestas-workload --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  kubectl -n "$NS" create secret generic aws-workload-credentials --from-literal=AWS_ACCESS_KEY_ID="$id" --from-literal=AWS_SECRET_ACCESS_KEY="$sec" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi
# Fluent Bit (namespace logging) usa la misma clave
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" get secret aws-workload-credentials -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.annotations) | .metadata.namespace="logging"' \
  | kubectl apply -f - >/dev/null
echo "secrets sincronizados en $NS: $(kubectl -n $NS get secret -o name | tr '\n' ' ')"
