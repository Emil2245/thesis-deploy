#!/usr/bin/env bash
# G8 (plan 040): de una VM aws-lab-1 limpia (Docker + Floci en marcha, ver clusters/aws-floci/README.md) a la app funcionando.
# Idempotente: cada fase se puede repetir. Fases (cada una documentada en el manual de despliegue):
#   1 salud de Floci · 2 tofu apply · 3 kubeconfig · 4 nodos de trabajo · 5 imágenes a ECR · 6 CoreDNS+CA · 7 Argo CD + GitOps · 8 espera · 9 smoke
# Uso: FLOCI_IP=<ip-de-la-VM> scripts/aws-floci/up.sh [--skip-smoke]     (DEMO_PASSWORD opcional: activa el login en el smoke)
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
S=scripts/aws-floci
t0=$SECONDS
fase() { printf '\n== [%ss] fase %s\n' $((SECONDS-t0)) "$*"; }

for c in aws tofu kubectl helm jq skopeo ssh curl openssl; do command -v "$c" >/dev/null || { echo "falta la herramienta: $c" >&2; exit 1; }; done
OVERLAY=k8s/propuestas/overlays/aws/kustomization.yaml
if ! grep -q "CORS_ORIGINS=https://$FLOCI_IP:8443" "$OVERLAY"; then
  echo "El overlay aws fija CORS_ORIGINS a otra IP. Edite $OVERLAY (CORS_ORIGINS=https://$FLOCI_IP:8443), haga commit y push, y repita." >&2
  exit 1
fi
API_TAG=$(awk '/propuestas-api/{f=1} f&&/newTag/{print $2; exit}' "$OVERLAY")
WEB_TAG=$(awk '/propuestas-web/{f=1} f&&/newTag/{print $2; exit}' "$OVERLAY")

fase "1 salud de Floci"
for _ in $(seq 1 60); do curl -fsS "$FLOCI/_floci/health" >/dev/null 2>&1 && break; sleep 5; done
curl -fsS "$FLOCI/_floci/health" | jq -r '"Floci " + .version'

fase "2 OpenTofu (VPC, IAM, KMS, ECR, EKS, RDS, Secrets Manager, S3, ALB, ACM, CloudWatch)"
tofu -chdir=infra/aws-floci init -input=false >/dev/null
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test tofu -chdir=infra/aws-floci apply -auto-approve -input=false -var "floci_endpoint=$FLOCI"

fase "3 kubeconfig"
$S/kubeconfig.sh
kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null

fase "4 nodos de trabajo"

$S/add-workers.sh "${NODE_COUNT:-2}"

fase "5 imágenes GHCR -> ECR ($API_TAG / $WEB_TAG)"
$S/copy-images.sh "$API_TAG" "$WEB_TAG"

fase "6 CoreDNS (nombre floci) y CA de Floci"
$S/cluster-prep.sh

fase "7 Argo CD y GitOps (app-of-apps)"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 10.11.1 -f k8s/argocd/values-aws.yaml --wait --timeout 10m
kubectl apply -f k8s/argocd/root-aws.yaml

fase "8 espera a que todas las Applications estén Synced y Healthy"
for _ in $(seq 1 120); do
  bad=$(kubectl -n argocd get applications -o json | jq -r '[.items[] | select(.status.sync.status!="Synced" or .status.health.status!="Healthy") | .metadata.name] | join(" ")')
  n=$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l)
  [ -z "$bad" ] && [ "$n" -ge 9 ] && break
  sleep 10
done
kubectl -n argocd get applications
[ -z "$bad" ] || { echo "Applications pendientes: $bad" >&2; exit 1; }
kubectl -n propuestas rollout status deploy/propuestas-api --timeout=600s
kubectl -n propuestas rollout status deploy/propuestas-web --timeout=300s

if [ "${1:-}" != "--skip-smoke" ]; then fase "9 smoke"; $S/smoke.sh; fi
printf '\nListo en %ss: https://%s:%s (ALB emulado; importe la CA: scripts/aws-floci/ca.sh)\n' $((SECONDS-t0)) "$FLOCI_IP" 8443
