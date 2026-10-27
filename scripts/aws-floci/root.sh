#!/usr/bin/env bash
# Aplica la Application raiz de Argo CD (k8s/argocd/root-aws.yaml) con parches kustomize en linea: el CORS_ORIGINS del ALB usa FLOCI_IP
# y, si se pide, repo y rama. El repositorio no se edita nunca (mismo mecanismo que scripts/vps/up.sh). Idempotente.
# Uso: FLOCI_IP=<ip> scripts/aws-floci/root.sh [--revision <rama>] [--repo <url-git>]     (Argo CD ya instalado, fase 7 de up.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
usar_kubeconfig
REPO=https://github.com/emil2245/thesis-deploy; REVISION=main
while [ $# -gt 0 ]; do
  case "$1" in
    --revision) REVISION=${2:?--revision <rama>}; shift 2;; --repo) REPO=${2:?--repo <url>}; shift 2;;
    *) die "opcion desconocida: $1 (uso: root.sh [--revision <rama>] [--repo <url>])";;
  esac
done
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

