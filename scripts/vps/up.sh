#!/usr/bin/env bash
# Despliega la plataforma en UN VPS Linux generico (Ubuntu 24.04, IP publica, acceso SSH por clave): k3s + Argo CD + GitOps.
# Idempotente: se puede repetir. Se ejecuta desde el portatil del administrador (el repositorio thesis-deploy clonado).
#
# Uso: scripts/vps/up.sh <ip> --domain <dominio> --issuer <letsencrypt-prod|letsencrypt-staging|selfsigned-ca>
#        [--email <correo-acme>] [--agent <ip2>] [--ssh-user ubuntu] [--ssh-key <ruta>]
#        [--s3-endpoint <url> --s3-bucket <bucket>]   (S3 externo; claves en S3_ACCESS_KEY / S3_SECRET_KEY)
#        [--repo <url-git>] [--revision <rama>] [--skip-smoke]
#   La app queda en https://propuestas.<dominio> y Grafana en https://grafana.<dominio>
#   (<dominio> puede ser <ip>.sslip.io, o un dominio propio con DNS *.<dominio> -> <ip>).
#   DEMO_PASSWORD (opcional) activa el login en el smoke. Fases (cada una esta en el manual de despliegue):
#   1 preflight SSH · 2 k3s (+agente) · 3 kubeconfig · 4 Secrets · 5 Argo CD · 6 raiz GitOps parametrizada · 7 espera Synced/Healthy · 8 smoke
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.local/bin:$PATH"
source scripts/vps/lib.sh
T0=$SECONDS

IP=${1:-}; [ -n "$IP" ] && [[ "$IP" != --* ]] || die "uso: $0 <ip> --domain <dominio> --issuer <emisor> [opciones] (ver cabecera)"; shift
DOMAIN=""; ISSUER=""; EMAIL=""; AGENT=""; S3_ENDPOINT_EXT=""; S3_BUCKET_EXT=""; REPO="https://github.com/emil2245/thesis-deploy"; REVISION=main; SKIP_SMOKE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN=$2; shift 2;; --issuer) ISSUER=$2; shift 2;; --email) EMAIL=$2; shift 2;; --agent) AGENT=$2; shift 2;;
    --ssh-user) SSH_USER=$2; shift 2;; --ssh-key) SSH_KEY=$2; shift 2;; --repo) REPO=$2; shift 2;; --revision) REVISION=$2; shift 2;;
    --s3-endpoint) S3_ENDPOINT_EXT=$2; shift 2;; --s3-bucket) S3_BUCKET_EXT=$2; shift 2;; --skip-smoke) SKIP_SMOKE=1; shift;;
    *) die "opcion desconocida: $1";;
  esac
done
[ -n "$DOMAIN" ] || die "falta --domain"
case "$ISSUER" in letsencrypt-prod|letsencrypt-staging|selfsigned-ca) ;; *) die "--issuer debe ser letsencrypt-prod, letsencrypt-staging o selfsigned-ca";; esac
case "$ISSUER" in letsencrypt-*) [ -n "$EMAIL" ] || die "--email es obligatorio con $ISSUER (aviso de caducidad de Let's Encrypt)";; esac
[ -z "$S3_ENDPOINT_EXT" ] || { [ -n "$S3_BUCKET_EXT" ] && [ -n "${S3_ACCESS_KEY:-}" ] && [ -n "${S3_SECRET_KEY:-}" ] || die "S3 externo: --s3-bucket y las variables S3_ACCESS_KEY / S3_SECRET_KEY"; }
for c in ssh kubectl helm jq curl openssl; do command -v "$c" >/dev/null || die "falta la herramienta: $c (scripts/install-tools.sh)"; done
APP_HOST="propuestas.$DOMAIN"; GRAFANA_HOST="grafana.$DOMAIN"
K="kubectl --kubeconfig $VPS_KUBECONFIG"

fase "1 preflight SSH ($SSH_USER@$IP)"
rssh "$IP" true || die "no hay acceso SSH por clave a $SSH_USER@$IP"
rssh "$IP" 'sudo -n true' || die "el usuario $SSH_USER necesita sudo sin contrasena (o use --ssh-user root)"
rssh "$IP" '. /etc/os-release; [ "$ID" = ubuntu ] && [ "$VERSION_ID" = 24.04 ] || { echo "SO no soportado: $PRETTY_NAME (se requiere Ubuntu 24.04)"; exit 1; }
  cpu=$(nproc); mem=$(awk "/MemTotal/{print int(\$2/1024)}" /proc/meminfo)
  echo "SO: $PRETTY_NAME | vCPU: $cpu | RAM: ${mem} MB"
  [ "$cpu" -ge 4 ] || { echo "se requieren >= 4 vCPU"; exit 1; }
  [ "$mem" -ge 7000 ] || { echo "se requieren >= 8 GB de RAM"; exit 1; }
  for p in 80 443; do ss -ltn "sport = :$p" | grep -q LISTEN && ! pgrep -x traefik >/dev/null && { echo "el puerto $p ya esta en uso por otro servicio"; exit 1; }; done
  true' || die "preflight fallido"
echo "preflight OK (los puertos 80/443 deben estar abiertos en el firewall del proveedor; el smoke lo comprueba desde fuera)"

fase "2 k3s $K3S_VERSION"
if rssh "$IP" "k3s --version 2>/dev/null | grep -qF '$K3S_VERSION'"; then
  echo "k3s ya instalado en la version pedida"
else
  rssh "$IP" "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION='$K3S_VERSION' sh -s - server --tls-san '$IP' --write-kubeconfig-mode 600"
fi
for _ in $(seq 1 60); do rssh "$IP" 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready"' && break; sleep 5; done
rssh "$IP" 'sudo k3s kubectl get nodes --no-headers' | grep -q ' Ready' || die "el nodo servidor no llega a Ready"
if [ -n "$AGENT" ]; then
  if rssh "$AGENT" 'systemctl is-active --quiet k3s-agent'; then echo "agente $AGENT ya unido"; else
    TOKEN=$(rssh "$IP" 'sudo cat /var/lib/rancher/k3s/server/node-token')
    rssh "$AGENT" "curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION='$K3S_VERSION' K3S_URL='https://$IP:6443' K3S_TOKEN='$TOKEN' sh -s - agent" >/dev/null
    unset TOKEN
  fi
  for _ in $(seq 1 60); do [ "$($K get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 2 ] && break; sleep 5; done
fi

fase "3 kubeconfig -> $VPS_KUBECONFIG"
mkdir -p "$(dirname "$VPS_KUBECONFIG")"
rssh "$IP" 'sudo cat /etc/rancher/k3s/k3s.yaml' | sed "s#127.0.0.1#$IP#; s#: default#: propuestas-vps#" > "$VPS_KUBECONFIG"
chmod 600 "$VPS_KUBECONFIG"
export KUBECONFIG="$VPS_KUBECONFIG"
$K wait --for=condition=Ready node --all --timeout=300s >/dev/null
$K get nodes

fase "4 Secrets en el cluster (JWT, respaldos S3); nunca en git ni en disco"
for ns in propuestas backup-store; do $K create namespace "$ns" --dry-run=client -o yaml | $K apply -f - >/dev/null; done
if ! $K -n propuestas get secret propuestas-backup-s3 >/dev/null 2>&1; then
  if [ -n "$S3_ENDPOINT_EXT" ]; then EP=$S3_ENDPOINT_EXT; BK=$S3_BUCKET_EXT; AK=$S3_ACCESS_KEY; SK=$S3_SECRET_KEY
  else EP=http://backup-store.backup-store.svc:8333; BK=propuestas-backups; AK=$(openssl rand -hex 10); SK=$(openssl rand -hex 24); fi
  $K -n propuestas create secret generic propuestas-backup-s3 --from-literal=endpoint="$EP" --from-literal=bucket="$BK" \
    --from-literal=access-key="$AK" --from-literal=secret-key="$SK" >/dev/null
  if [ -z "$S3_ENDPOINT_EXT" ] && ! $K -n backup-store get secret backup-store-s3-config >/dev/null 2>&1; then
    jq -n --arg a "$AK" --arg s "$SK" '{identities:[{name:"backup",credentials:[{accessKey:$a,secretKey:$s}],actions:["Admin","Read","Write","List","Tagging"]}]}' \
      | $K -n backup-store create secret generic backup-store-s3-config --from-file=s3.json=/dev/stdin >/dev/null
  fi
  unset AK SK
  echo "Secret propuestas-backup-s3 creado"
else echo "Secret propuestas-backup-s3 ya existe"; fi
# propuestas-jwt lo crea bootstrap.sh (par RSA-2048 efimero, solo si no existe)

fase "5 Argo CD (scripts/bootstrap.sh vps)"
SKIP_ROOT=1 scripts/bootstrap.sh vps

fase "6 raiz GitOps parametrizada (dominio $DOMAIN, emisor $ISSUER, rama $REVISION)"
INSTANCES=1; [ -z "$AGENT" ] || INSTANCES=2
APPS=$(kubectl kustomize k8s/platform/vps | $K create --dry-run=client -f - -o json)
ROOT=$($K apply --dry-run=client -f k8s/argocd/root-vps.yaml -o json)
DEFREPO=https://github.com/emil2245/thesis-deploy
PATCHES=$(jq -n --argjson apps "$APPS" --arg host "$APP_HOST" --arg ghost "$GRAFANA_HOST" --arg issuer "$ISSUER" --arg email "$EMAIL" \
  --argjson inst "$INSTANCES" --arg repo "$REPO" --arg rev "$REVISION" --arg defrepo "$DEFREPO" '
  def isrepo(a): (a.spec.source // null) != null and (a.spec.source.repoURL == $defrepo);
  def repo_ops(a):
    ( if isrepo(a) then [{op:"replace",path:"/spec/source/repoURL",value:$repo},{op:"replace",path:"/spec/source/targetRevision",value:$rev}] else [] end )
    + ( (a.spec.sources // []) | to_entries | map(select(.value.repoURL == $defrepo)) | map(.key as $i | [{op:"replace",path:"/spec/sources/\($i)/repoURL",value:$repo},{op:"replace",path:"/spec/sources/\($i)/targetRevision",value:$rev}]) | flatten );
  def extra(name):
    if name == "propuestas" then [{op:"add",path:"/spec/source/kustomize",value:{patches:[
      {target:{kind:"Ingress",name:"propuestas"},patch:([{op:"replace",path:"/spec/rules/0/host",value:$host},{op:"replace",path:"/metadata/annotations/cert-manager.io~1cluster-issuer",value:$issuer},{op:"replace",path:"/spec/tls/0/hosts/0",value:$host}]|tojson)},
      {target:{kind:"ConfigMap",name:"propuestas-api-config"},patch:([{op:"replace",path:"/data/CORS_ORIGINS",value:("https://"+$host)}]|tojson)},
      {target:{kind:"Cluster",name:"propuestas-db"},patch:([{op:"replace",path:"/spec/instances",value:$inst}]|tojson)}]}}]
    elif name == "kube-prometheus-stack" then [{op:"add",path:"/spec/sources/0/helm/valuesObject",value:{grafana:{ingress:{annotations:{"cert-manager.io/cluster-issuer":$issuer},hosts:[$ghost],tls:[{secretName:"grafana-tls",hosts:[$ghost]}]}}}}]
    elif name == "issuers" and $issuer == "selfsigned-ca" then [{op:"replace",path:"/spec/source/path",value:"k8s/platform/issuers/lab"}]
    elif name == "issuers" then [{op:"add",path:"/spec/source/kustomize",value:{patches:[{target:{kind:"ClusterIssuer",name:"letsencrypt-.*"},patch:([{op:"replace",path:"/spec/acme/email",value:$email}]|tojson)}]}}]
    else [] end;
  [ $apps.items[] | select(.kind=="Application") | . as $a | {name:.metadata.name, ops:((if ($repo != $defrepo or $rev != "main") then repo_ops($a) else [] end) + extra(.metadata.name))}
    | select(.ops|length>0) | {target:{kind:"Application",name:.name},patch:(.ops|tojson)} ]')
ROOT_R=$(jq --argjson p "$PATCHES" --arg repo "$REPO" --arg rev "$REVISION" \
  '.spec.source.repoURL=$repo | .spec.source.targetRevision=$rev | .spec.source.kustomize={patches:$p}' <<<"$ROOT")
$K apply -f - <<<"$ROOT_R" >/dev/null
echo "Application root aplicada ($(jq length <<<"$PATCHES") parches en linea)"

fase "7 espera a que todas las Applications esten Synced y Healthy"
bad=x
for _ in $(seq 1 180); do
  bad=$($K -n argocd get applications -o json | jq -r '[.items[] | select(.status.sync.status!="Synced" or .status.health.status!="Healthy") | .metadata.name] | join(" ")')
  n=$($K -n argocd get applications --no-headers 2>/dev/null | wc -l)
  [ -z "$bad" ] && [ "$n" -ge 12 ] && break
  sleep 10
done
$K -n argocd get applications
[ -z "$bad" ] || die "Applications pendientes: $bad"
$K -n propuestas rollout status deploy/propuestas-api --timeout=600s
$K -n propuestas rollout status deploy/propuestas-web --timeout=300s

if [ "$SKIP_SMOKE" = 0 ]; then fase "8 smoke"; VPS_IP=$IP VPS_DOMAIN=$DOMAIN VPS_ISSUER=$ISSUER scripts/vps/smoke.sh; fi
printf '\nListo en %ss: https://%s  (Grafana https://%s, kubeconfig %s)\n' $((SECONDS-T0)) "$APP_HOST" "$GRAFANA_HOST" "$VPS_KUBECONFIG"
