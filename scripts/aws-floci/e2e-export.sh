#!/usr/bin/env bash
# E2E: cuenta desechable -> proyecto con APU con precio, ET y cronograma programado ->
# POST exportación (Core -> Documentos -> S3) -> ticket 200 -> reuso 404 -> objeto en bucket.
# No imprime contraseñas, JWT, tickets ni downloadUrl.
# Uso (modo local, tras local-up.sh): scripts/aws-floci/e2e-export.sh   · requiere docker (psql efímero), aws, jq, curl, kubectl, python3 >= 3.14 (uuid7)
set -euo pipefail
B=${B:-http://127.0.0.1:8080/api/v1}
ALB=${ALB:-http://127.0.0.1:8080}
OUT=${OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-floci/e2e-out}; mkdir -p "$OUT"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/propuestas-aws.yaml}
F=http://127.0.0.1:4566
EMAIL="e2e-$(date +%s)@example.test"; PASS="E2e$(openssl rand -hex 8)x9"
uuid7() { python3 -I -c "import uuid;print(uuid.uuid7())"; }
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "== registro (cuenta desechable)"
curl -sS -o /dev/null -w 'registro %{http_code}\n' -H 'Content-Type: application/json' "$B/auth/registro" \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASS" '{nombre:"E2E Floci",email:$e,password:$p,passwordConfirmacion:$p,aceptaPolitica:true}')"

echo "== verificación de la cuenta desechable en RDS emulado (el token no se registra en prod)"
S=$(aws --endpoint-url $F secretsmanager get-secret-value --secret-id propuestas/db --query SecretString --output text)
docker run --rm --network host -e PGPASSWORD="$(jq -r .password <<<"$S")" postgres:18-alpine \
  psql -h 127.0.0.1 -p 7001 -U "$(jq -r .username <<<"$S")" -d "$(jq -r .dbname <<<"$S")" -tAc \
  "UPDATE usuario SET email_verificado = true WHERE email = '$EMAIL' RETURNING 'verificada'"
unset S

TOKEN=$(curl -sS -H 'Content-Type: application/json' "$B/auth/login" \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASS" '{email:$e,password:$p,recordarSesion:false}')" | jq -r '.accessToken // .token // empty')
[ -n "$TOKEN" ] && echo "login 200 (token recibido)" || { echo "login FALLA"; exit 1; }
A=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')

# call METHOD PATH BODY -> imprime "<code>" en stderr-label y deja el cuerpo en $RB
call() { local R; R=$(curl -sS -w '\n%{http_code}' "${A[@]}" -X "$1" "$B$2" ${3:+-d "$3"}); RC=$(tail -1 <<<"$R"); RB=$(sed '$d' <<<"$R"); }

echo "== datos (solo API pública)"
call POST /proyectos '{"nombreProyecto":"E2E Floci microservicios","anio":2026,"fechaInicio":"2026-01-05","plazoEjecucion":3,"plazoUnidad":"MES","direccionInstitucional":"UCE"}'
P=$(jq -r .id <<<"$RB"); echo "proyecto $RC"
call GET "/proyectos/$P/presupuestos"; PR=$(jq -r 'map(select(.esVigente))[0].presupuestoId' <<<"$RB"); echo "presupuesto vigente $RC"
call POST "/proyectos/$P/insumos" '{"codigo":"INS-E2E-01","tipo":"MATERIAL","descripcion":"Material E2E con precio","unidad":"u","precioUnitario":5.00}'
INS=$(jq -r .id <<<"$RB"); echo "insumo PROYECTO $RC"
call POST "/presupuestos/$PR/apus" '{"codigo":"APU-E2E-01","descripcion":"APU E2E","unidad":"u"}'
APU=$(jq -r '.id // .apuId' <<<"$RB"); echo "apu $RC"
call POST "/apus/$APU/detalles" "{\"seccionTipo\":\"MATERIAL\",\"insumoId\":\"$INS\",\"cantidad\":1.0}"; echo "detalle apu $RC"
call PUT "/apus/$APU/especificacion-tecnica" '{"texto":"Especificación técnica E2E: suministro e instalación según planos."}'; echo "especificación técnica $RC"
call POST "/presupuestos/$PR/capitulos" '{"descripcion":"OBRAS PRELIMINARES E2E"}'; CAP=$(jq -r '.capitulos[0].id' <<<"$RB"); echo "capítulo $RC"
call POST "/presupuestos/$PR/capitulos/$CAP/rubros" "{\"apuId\":\"$APU\",\"cantidad\":\"5.000000\"}"; echo "rubro $RC"
call POST "/presupuestos/$PR/cronograma" '{"unidadTiempo":"SEMANA","numeroPeriodos":4}'; CR=$(jq -r .id <<<"$RB"); echo "cronograma $RC"
call GET "/presupuestos/$PR/cronograma"; ACT=$(jq -r '.actividades[0].id' <<<"$RB"); echo "actividades $RC n=$(jq '.actividades|length' <<<"$RB")"
call PATCH "/cronogramas/$CR/actividades/$ACT" '{"operacion":"REEMPLAZAR_AVANCES","avancePorPeriodo":{"1":"100.0000"}}'; echo "programar actividad $RC"
call GET "/presupuestos/$PR/validacion"; echo "validación $RC exportable=$(jq -r .exportable <<<"$RB")"

export_post() { # doc-path body key -> RC/RB
  local R; R=$(curl -sS -w '\n%{http_code}' "${A[@]}" -H "Idempotency-Key: $3" "$B/documentos/$1/$PR/exportaciones" -d "$2")
  RC=$(tail -1 <<<"$R"); RB=$(sed '$d' <<<"$R"); }

printf '\n%-34s %-5s %-5s %-9s %-6s %s\n' DOC POST GET BYTES REUSO TYPE | tee "$OUT/results.txt"
SPECS=${SPECS:-'presupuesto|{"formato":"xlsx"}|xlsx
presupuesto|{"formato":"pdf","orientacion":"vertical"}|pdf
apus|{"formato":"xlsx","layout":"pestanas"}|xlsx
apus|{"formato":"pdf"}|pdf
especificaciones-tecnicas|{"formato":"docx","titulo1":"ESPECIFICACIONES TECNICAS","titulo2":"E2E Floci"}|docx
cronograma|{"formato":"xlsx"}|xlsx
cronograma|{"formato":"pdf","papel":"a4"}|pdf
cronograma|{"formato":"mspdi"}|xml'}
while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  IFS='|' read -r doc body ext <<<"$spec"; fmt=$(jq -r .formato <<<"$body")
  name="$doc-$fmt"; export_post "$doc" "$body" "$(uuid7)"
  if [ "$RC" != 200 ]; then
    printf '%-34s %-5s FAIL  %s\n' "$name" "$RC" "$(jq -c '[.bloqueos[]?.codigo] + [.detail // .mensaje // .title // empty]' <<<"$RB" 2>/dev/null)" | tee -a "$OUT/results.txt"; continue
  fi
  U=$(jq -r .downloadUrl <<<"$RB"); MT=$(jq -r '.mediaType // .mimeType // empty' <<<"$RB"); SZ=$(jq -r '.sizeBytes // empty' <<<"$RB")
  c1=$(curl -sS -o "$OUT/$name.$ext" -D "$OUT/h.$name" -w '%{http_code}' "$ALB$U")
  c2=$(curl -sS -o /dev/null -w '%{http_code}' "$ALB$U"); unset U
  bytes=$(stat -c %s "$OUT/$name.$ext")
  printf '%-34s %-5s %-5s %-9s %-6s %s\n' "$name" "$RC" "$c1" "$bytes" "$c2" "$(file -b "$OUT/$name.$ext" | cut -c1-50)" | tee -a "$OUT/results.txt"
  echo "    $(grep -i -E '^content-(type|disposition)' "$OUT/h.$name" | tr -d '\r' | paste -sd' ' -) | resp.mediaType=$MT resp.sizeBytes=$SZ | cabeceras s3/amz: $(grep -i -c 's3\|amz' "$OUT/h.$name" || true)" | tee -a "$OUT/results.txt"
done <<<"$SPECS"

echo "== idempotencia (misma clave + mismo cuerpo dos veces; luego misma clave + cuerpo distinto)"
K=$(uuid7)
export_post presupuesto '{"formato":"xlsx"}' "$K"; c1=$RC; o1=$(jq -r '.operationId // .id' <<<"$RB"); h1=$(jq -r .sha256 <<<"$RB")
export_post presupuesto '{"formato":"xlsx"}' "$K"; c2=$RC; o2=$(jq -r '.operationId // .id' <<<"$RB"); h2=$(jq -r .sha256 <<<"$RB")
export_post presupuesto '{"formato":"pdf"}' "$K"; c3=$RC
echo "1º=$c1 2º=$c2 mismaOperacion=$([ "$o1" = "$o2" ] && echo sí || echo no) mismoSha256=$([ "$h1" = "$h2" ] && echo sí || echo no) | misma clave+otro cuerpo=$c3 $(jq -c '.title // .detail // .mensaje // empty' <<<"$RB" 2>/dev/null)" | tee -a "$OUT/results.txt"
unset TOKEN A

echo "== objetos en propuestas-documentos"
aws --endpoint-url $F s3api list-objects-v2 --bucket propuestas-documentos --query "Contents[?LastModified>='$START'].[Size,LastModified]" --output text
echo "total en bucket: $(aws --endpoint-url $F s3api list-objects-v2 --bucket propuestas-documentos --query 'length(Contents || `[]`)' --output text); de esta corrida: $(aws --endpoint-url $F s3api list-objects-v2 --bucket propuestas-documentos --query "length(Contents[?LastModified>='$START'] || \`[]\`)" --output text)"
echo "propuestas-backups: total $(aws --endpoint-url $F s3api list-objects-v2 --bucket propuestas-backups --query 'length(Contents || `[]`)' --output text), de esta corrida $(aws --endpoint-url $F s3api list-objects-v2 --bucket propuestas-backups --query "length(Contents[?LastModified>='$START'] || \`[]\`)" --output text)"
curl -s -o /dev/null -w 'GET anónimo directo al bucket: %{http_code}\n' "$F/propuestas-documentos/"

echo "== pods (Core y Documentos separados)"
kubectl -n propuestas get pods -o wide
echo "== logs propuestas-documentos (solo conteos)"
L=$(kubectl -n propuestas logs deploy/propuestas-documentos --since=15m 2>&1 || true)
for pat in 'export' 'upload|subid|PutObject' 'render' 'POST' 'internal'; do echo "  /$pat/i: $(grep -ciE "$pat" <<<"$L" || true)"; done
L=$(kubectl -n propuestas logs deploy/propuestas-api --since=15m 2>&1 || true)
echo "  core /documentos|export/i: $(grep -ciE 'documentos|export' <<<"$L" || true)"
echo "archivos en $OUT"
