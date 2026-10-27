#!/usr/bin/env bash
# G8 (plan 040): de una VM aws-lab-1 limpia (Docker + Floci en marcha, ver clusters/aws-floci/README.md) a la app funcionando.
# Idempotente: cada fase se puede repetir. Fases (cada una documentada en el manual de despliegue):
#   1 salud de Floci · 2 tofu apply · 3 kubeconfig · 4 nodos de trabajo · 5 imágenes a ECR · 6 CoreDNS+CA · 7 Argo CD + GitOps · 8 espera · 9 smoke
# Uso: FLOCI_IP=<ip-de-la-VM> scripts/aws-floci/up.sh [--revision <rama>] [--repo <url-git>] [--skip-smoke]
#   DEMO_PASSWORD (opcional) activa el login en el smoke. La Application raiz se aplica con parches kustomize en linea (CORS del ALB,
#   repo y rama), por lo que el repositorio no se edita nunca: sirve para cualquier IP de VM y cualquier fork o rama.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"
source scripts/aws-floci/lib.sh
export KUBECONFIG="$AWS_KUBECONFIG"   # up.sh CREA este archivo: nunca toma el KUBECONFIG del entorno
S=scripts/aws-floci
t0=$SECONDS
fase() { printf '\n== [%ss] fase %s\n' $((SECONDS-t0)) "$*"; }
REPO=https://github.com/emil2245/thesis-deploy; REVISION=main; SKIP_SMOKE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --revision) REVISION=${2:?--revision <rama>}; shift 2;; --repo) REPO=${2:?--repo <url>}; shift 2;; --skip-smoke) SKIP_SMOKE=1; shift;;
    *) die "opcion desconocida: $1 (uso: up.sh [--revision <rama>] [--repo <url>] [--skip-smoke])";;
  esac
done

for c in aws tofu kubectl helm jq skopeo ssh curl openssl; do command -v "$c" >/dev/null || die "falta la herramienta: $c"; done
OVERLAY=k8s/propuestas/overlays/aws/kustomization.yaml
API_TAG=$(awk '/propuestas-api/{f=1} f&&/newTag/{print $2; exit}' "$OVERLAY")
WEB_TAG=$(awk '/propuestas-web/{f=1} f&&/newTag/{print $2; exit}' "$OVERLAY")

fase "1 salud de Floci"
for _ in $(seq 1 60); do curl -fsS "$FLOCI/_floci/health" >/dev/null 2>&1 && break; sleep 5; done
curl -fsS "$FLOCI/_floci/health" | jq -r '"Floci " + .version'

fase "2 OpenTofu (VPC, IAM, KMS, ECR, EKS, RDS, Secrets Manager, S3, ALB, ACM, CloudWatch)"
tofu_init
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test tofu -chdir=infra/aws-floci apply -auto-approve -input=false -var "floci_endpoint=$FLOCI" -var "node_count=${NODE_COUNT:-2}"

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
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 10.11.6 -f k8s/argocd/values-aws.yaml --wait --timeout 10m
# raiz parametrizada: parches kustomize en linea sobre las Applications (mismo mecanismo que scripts/vps/up.sh)
APPS=$(kubectl kustomize k8s/apps/propuestas-aws | kubectl create --dry-run=client -f - -o json | jq -s '{items: [.[] | if .items then .items[] else . end]}')
ROOT=$(kubectl apply --dry-run=client -f k8s/argocd/root-aws.yaml -o json)
DEFREPO=https://github.com/emil2245/thesis-deploy
PATCHES=$(jq -n --argjson apps "$APPS" --arg cors "http://$FLOCI_IP:8080,https://$FLOCI_IP:8443" --arg repo "$REPO" --arg rev "$REVISION" --arg defrepo "$DEFREPO" '
  def isrepo(a): (a.spec.source // null) != null and (a.spec.source.repoURL == $defrepo);
  def repo_ops(a):
    ( if isrepo(a) then [{op:"replace",path:"/spec/source/repoURL",value:$repo},{op:"replace",path:"/spec/source/targetRevision",value:$rev}] else [] end )
    + ( (a.spec.sources // []) | to_entries | map(select(.value.repoURL == $defrepo)) | map(.key as $i | [{op:"replace",path:"/spec/sources/\($i)/repoURL",value:$repo},{op:"replace",path:"/spec/sources/\($i)/targetRevision",value:$rev}]) | flatten );
  def extra(name):
    if name == "propuestas" then [{op:"add",path:"/spec/source/kustomize",value:{patches:[
      {target:{kind:"ConfigMap",name:"propuestas-api-config"},patch:([{op:"replace",path:"/data/CORS_ORIGINS",value:$cors}]|tojson)}]}}]
    else [] end;
  [ $apps.items[] | select(.kind=="Application") | . as $a | {name:.metadata.name, ops:((if ($repo != $defrepo or $rev != "main") then repo_ops($a) else [] end) + extra(.metadata.name))}
    | select(.ops|length>0) | {target:{kind:"Application",name:.name},patch:(.ops|tojson)} ]')
jq --argjson p "$PATCHES" --arg repo "$REPO" --arg rev "$REVISION" \
  '.spec.source.repoURL=$repo | .spec.source.targetRevision=$rev | .spec.source.kustomize={patches:$p}' <<<"$ROOT" | kubectl apply -f - >/dev/null
echo "Application root aplicada (CORS=http://$FLOCI_IP:8080,https://$FLOCI_IP:8443; repo $REPO, rama $REVISION; $(jq length <<<"$PATCHES") parches en linea)"

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

if [ "$SKIP_SMOKE" = 0 ]; then fase "9 smoke"; $S/smoke.sh; fi
printf '\nListo en %ss: http://%s:8080 (ALB emulado; HTTPS 8443 declarado, ver variables.tf)\n' $((SECONDS-t0)) "$FLOCI_IP"
