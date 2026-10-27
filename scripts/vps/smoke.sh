#!/usr/bin/env bash
# Verificacion de extremo a extremo del entorno vps (checklist del capitulo 12 del manual). Sale con 1 si algo falla. No imprime secretos.
# Variables: VPS_IP, VPS_DOMAIN, VPS_ISSUER (las fija up.sh); DEMO_PASSWORD (opcional) activa login + GET /proyectos (john@uce.edu.ec).
set -uo pipefail
cd "$(dirname "$0")/../.."
source scripts/vps/lib.sh
: "${VPS_IP:?}" "${VPS_DOMAIN:?}" "${VPS_ISSUER:?}"
export KUBECONFIG="$VPS_KUBECONFIG"
H=propuestas.$VPS_DOMAIN; G=grafana.$VPS_DOMAIN
fail=0
ok()  { printf 'OK    %s\n' "$*"; }
bad() { printf 'FALLA %s\n' "$*"; fail=1; }
chk() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CA=()
if [ "$VPS_ISSUER" = selfsigned-ca ]; then
  kubectl -n cert-manager get secret selfsigned-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > "$T/ca.pem"; CA=(--cacert "$T/ca.pem")
fi
# --resolve evita depender del DNS; el certificado SE VERIFICA (CA propia o la raiz publica de Let's Encrypt)
C=(curl -sS -m 30 "${CA[@]}" --resolve "$H:443:$VPS_IP" --resolve "$G:443:$VPS_IP")

# 1. Cluster y GitOps
n=$(kubectl get nodes --no-headers | grep -c ' Ready'); [ "$n" -ge 1 ] && ok "$n nodo(s) Ready" || bad "nodos Ready: $n"
bad_apps=$(kubectl -n argocd get applications -o json | jq -r '[.items[]|select(.status.sync.status!="Synced" or .status.health.status!="Healthy")|.metadata.name]|join(" ")')
na=$(kubectl -n argocd get applications --no-headers | wc -l)
[ -z "$bad_apps" ] && ok "$na Applications Synced/Healthy" || bad "Applications pendientes: $bad_apps"
# 2. TLS
for c in propuestas-tls; do s=$(kubectl -n propuestas get certificate "$c" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); [ "$s" = True ] && ok "Certificate $c Ready (emisor $VPS_ISSUER)" || bad "Certificate $c: $s"; done
r=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -m 20 --resolve "$H:80:$VPS_IP" "http://$H/")
case "$r" in "308 https://$H/"*|"301 https://$H/"*) ok "HTTP redirige a HTTPS (Traefik: 301 con GET, 308 con HEAD): $r";; *) bad "redireccion HTTP->HTTPS: $r";; esac
# 3. Aplicacion por HTTPS (certificado verificado)
for p in / /api/v1/config/display /privacidad; do
  c=$("${C[@]}" -o /dev/null -w '%{http_code}' "https://$H$p" 2>/dev/null); [ "$c" = 200 ] && ok "GET https://$H$p -> 200" || bad "GET $p -> $c"
done
pod=$(kubectl -n propuestas get pods -l app.kubernetes.io/name=propuestas-api -o jsonpath='{.items[0].metadata.name}')
h=$(kubectl get --raw "/api/v1/namespaces/propuestas/pods/$pod:9000/proxy/q/health" 2>/dev/null | jq -r .status)
[ "$h" = UP ] && ok "/q/health (puerto de gestion) = UP" || bad "/q/health = $h"
v=$(kubectl -n propuestas exec propuestas-db-1 -c postgres -- psql -U postgres -d propuestas -tAc "select max(version::int) from flyway_schema_history where success" 2>/dev/null | tr -d '[:space:]')
[ "${v:-0}" -ge 22 ] 2>/dev/null && ok "Flyway: esquema migrado hasta V$v" || bad "Flyway: version $v (se esperaba >= 22)"
if [ -n "${DEMO_PASSWORD:-}" ]; then
  tok=$("${C[@]}" -H 'Content-Type: application/json' -d "{\"email\":\"john@uce.edu.ec\",\"password\":\"$DEMO_PASSWORD\"}" "https://$H/api/v1/auth/login" | jq -r '.accessToken // .token // empty')
  if [ -n "$tok" ]; then
    ok "login por HTTPS (token ${#tok} caracteres)"
    c=$("${C[@]}" -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" "https://$H/api/v1/proyectos?page=0&size=25"); [ "$c" = 200 ] && ok "GET /api/v1/proyectos -> 200" || bad "proyectos -> $c"
  else bad "login"; fi
fi
# 4. Base de datos, secretos y respaldo
chk "Cluster CNPG propuestas-db en estado sano" bash -c "kubectl -n propuestas get cluster propuestas-db -o jsonpath='{.status.phase}' | grep -q 'Cluster in healthy state'"
chk "Secret propuestas-jwt presente" kubectl -n propuestas get secret propuestas-jwt
if git grep -nE 'BEGIN (RSA )?PRIVATE KEY' -- k8s >/dev/null 2>&1; then bad "hay una llave privada en k8s/"; else ok "ninguna llave privada en el repositorio"; fi
j=smoke-backup-$(date +%s)
kubectl -n propuestas create job --from=cronjob/propuestas-backup "$j" >/dev/null 2>&1
if kubectl -n propuestas wait --for=condition=complete "job/$j" --timeout=300s >/dev/null 2>&1; then ok "respaldo pg_dump subido a S3 (job $j)"; else bad "job de respaldo $j"; fi
kubectl -n propuestas delete job "$j" --wait=false >/dev/null 2>&1
# 5. Observabilidad: una metrica, una linea de log, una traza
PQ='/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query'
m=$(kubectl get --raw "$PQ?query=$(printf '%s' 'sum(up{namespace="propuestas"})' | jq -sRr @uri)" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
[ "${m%.*}" -ge 1 ] 2>/dev/null && ok "metrica Prometheus: sum(up{namespace=propuestas}) = $m" || bad "metrica Prometheus: $m"
q=$(kubectl get --raw "$PQ?query=$(printf '%s' 'sum(http_server_requests_seconds_count)' | jq -sRr @uri)" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
[ "${q%.*}" -ge 1 ] 2>/dev/null && ok "metrica de la app: http_server_requests_seconds_count = $q" || bad "metrica de la app: $q"
lq=$(printf '%s' '{namespace="propuestas",app="propuestas-api"}' | jq -sRr @uri)
for _ in $(seq 1 12); do
  nl=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/loki:3100/proxy/loki/api/v1/query_range?query=$lq&limit=5&since=1h" 2>/dev/null | jq -r '[.data.result[].values|length]|add // 0')
  [ "${nl:-0}" -ge 1 ] && break; sleep 10
done
[ "${nl:-0}" -ge 1 ] && ok "Loki: $nl linea(s) de log de propuestas-api" || bad "sin logs en Loki"
for _ in $(seq 1 12); do
  tr=$(kubectl get --raw '/api/v1/namespaces/monitoring/services/tempo:3200/proxy/api/search?limit=5' 2>/dev/null | jq -r '.traces|length' 2>/dev/null)
  [ "${tr:-0}" -ge 1 ] && break; sleep 10
done
[ "${tr:-0}" -ge 1 ] && ok "traza en Tempo: $tr resultado(s)" || bad "sin trazas en Tempo"
c=$("${C[@]}" -o /dev/null -w '%{http_code}' "https://$G/login" 2>/dev/null); [ "$c" = 200 ] && ok "Grafana https://$G/login -> 200" || bad "Grafana -> $c"
# 6. Escalamiento
chk "HPA propuestas-api presente (min 2 / max 6)" kubectl -n propuestas get hpa propuestas-api
exit $fail
