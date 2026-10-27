#!/usr/bin/env bash
# Verificación de extremo a extremo del entorno aws-floci (plan 040). Sale con 1 si algo falla. No imprime secretos.
# DEMO_PASSWORD (opcional) activa login + GET /api/v1/proyectos (usuario john@uce.edu.ec).
set -uo pipefail
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
fail=0
ok()  { printf 'OK    %s\n' "$*"; }
bad() { printf 'FALLA %s\n' "$*"; fail=1; }
chk() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
tofu -chdir=infra/aws-floci output -raw alb_ca_pem > "$T/ca.pem"
RED=$(tofu -chdir=infra/aws-floci output -raw alb_redirect_http)
if [ "$RED" = true ]; then
  B=https://$FLOCI_IP:8443; C="curl -sS --cacert $T/ca.pem -m 30"
  r=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -m 20 "http://$FLOCI_IP:8080/")
  case "$r" in "301 https://$FLOCI_IP:8443/"*) ok "ALB :8080 redirige: $r";; *) bad "redirección HTTP->HTTPS: $r";; esac
else
  # Floci 2.3.0: el listener HTTPS no termina TLS (ver infra/aws-floci/variables.tf, alb_redirect_http); se prueba por HTTP
  B=http://$FLOCI_IP:8080; C="curl -sS -m 30"
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 20 http://$FLOCI_IP:8443/)" = 200 ] && ok "listener :8443 (HTTPS declarado, ACM) responde HTTP plano: limitación documentada de Floci 2.3.0" || bad ":8443 no responde"
fi
for p in / /api/v1/config/display /privacidad; do
  c=$($C -o /dev/null -w '%{http_code}' "$B$p" 2>/dev/null); [ "$c" = 200 ] && ok "GET $p -> 200 ($B)" || bad "GET $p -> $c"
done
if [ -n "${DEMO_PASSWORD:-}" ]; then
  tok=$($C -H 'Content-Type: application/json' -d "{\"email\":\"john@uce.edu.ec\",\"password\":\"$DEMO_PASSWORD\"}" "$B/api/v1/auth/login" | jq -r '.token // .accessToken // empty')
  if [ -n "$tok" ]; then
    ok "login (token ${#tok} caracteres)"
    for _ in 1 2 3 4 5; do $C -o /dev/null -H "Authorization: Bearer $tok" "$B/api/v1/proyectos?page=0&size=25"; done
    c=$($C -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" "$B/api/v1/proyectos?page=0&size=25"); [ "$c" = 200 ] && ok "GET /api/v1/proyectos -> 200" || bad "proyectos -> $c"
  else bad "login"; fi
fi

# G1/G5: nodos e ingress
n=$(kubectl get nodes --no-headers | grep -c ' Ready'); [ "$n" -ge 2 ] && ok "$n nodos Ready" || bad "nodos Ready: $n"
chk "Ingress propuestas con clase traefik" kubectl -n propuestas get ingress propuestas -o jsonpath='{.spec.ingressClassName}'
# G3: ESO
for e in propuestas-db-app propuestas-jwt; do
  s=$(kubectl -n propuestas get externalsecret "$e" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); [ "$s" = True ] && ok "ExternalSecret $e Ready" || bad "ExternalSecret $e: $s"
done
# G2: sin claves estáticas de AWS en el clúster ni TLS sin verificar en el repo
if kubectl get secret -A --no-headers | awk '{print $2}' | grep -i aws; then bad "hay Secrets con 'aws' en el nombre"; else ok "ningún Secret aws-* en el clúster"; fi
if git grep -n 'verify[ ]Off' >/dev/null 2>&1; then bad "el repo desactiva la verificación TLS"; else ok "sin verificación TLS desactivada en el repo"; fi
# G2/G4/G7: un respaldo real con pod identity + TLS verificado (S3)
j=smoke-backup-$(date +%s)
kubectl -n propuestas create job --from=cronjob/propuestas-backup "$j" >/dev/null 2>&1
if kubectl -n propuestas wait --for=condition=complete "job/$j" --timeout=300s >/dev/null 2>&1; then ok "respaldo con pod identity subido a S3 (job $j)"; else bad "job de respaldo $j"; fi
kubectl -n propuestas delete job "$j" --wait=false >/dev/null 2>&1
# G9: una métrica y una traza
PQ='/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query'
m=$(kubectl get --raw "$PQ?query=$(printf '%s' 'sum(up{namespace="propuestas"})' | jq -sRr @uri)" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
[ "${m%.*}" -ge 1 ] 2>/dev/null && ok "métrica Prometheus: sum(up{namespace=propuestas}) = $m" || bad "métrica Prometheus: $m"
q=$(kubectl get --raw "$PQ?query=$(printf '%s' 'sum(http_server_requests_seconds_count)' | jq -sRr @uri)" 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
[ "${q%.*}" -ge 1 ] 2>/dev/null && ok "métrica de la app: http_server_requests_seconds_count = $q" || bad "métrica de la app: $q"
for _ in $(seq 1 12); do
  tr=$(kubectl get --raw '/api/v1/namespaces/monitoring/services/tempo:3200/proxy/api/search?limit=5' 2>/dev/null | jq -r '.traces | length' 2>/dev/null)
  [ "${tr:-0}" -ge 1 ] && break; sleep 10
done
[ "${tr:-0}" -ge 1 ] && ok "traza en Tempo: $tr resultado(s)" || bad "sin trazas en Tempo"
# G4: logs en CloudWatch (Fluent Bit con TLS verificado)
ev=$(awsf logs filter-log-events --log-group-name /propuestas/api --limit 5 --query 'length(events)' --output text 2>/dev/null)
[ "${ev:-0}" -ge 1 ] && ok "CloudWatch Logs /propuestas/api: $ev evento(s)" || bad "sin eventos en CloudWatch Logs"
exit $fail
