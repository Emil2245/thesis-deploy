#!/usr/bin/env bash
# Modo local del entorno aws-floci: Floci corre en ESTE equipo (sin VM, sin SSH, sin sudo) y las tres imágenes
# (propuestas-api, propuestas-documentos, propuestas-web) se construyen aquí desde los repositorios hermanos, en lugar de
# copiarse de GHCR. Después delega en up.sh (tofu, kubeconfig, ECR, Argo CD, espera, smoke) con NODE_COUNT=1.
# Uso: scripts/aws-floci/local-up.sh [opciones de up.sh: --revision <rama> --repo <url> --skip-smoke]
#   BACKEND_DIR  (def. ../thesis-back-quarkus)  FRONTEND_DIR (def. ../thesis-front-react)
#   FLOCI_DATA_DIR (def. ~/.local/share/floci-propuestas; fuera del repo)
# Etiquetas = SHA corto de cada repo; con cambios sin commit se añade -dirty-<epoch> (ECR tiene etiquetas inmutables).
# Requiere libres los puertos 4566, 7001-7099, 8080-8089 y 8443-8449 (los publica clusters/aws-floci/compose.yaml).
set -euo pipefail
cd "$(dirname "$0")/../.."
export FLOCI_LOCAL=1 FLOCI_IP=127.0.0.1
export FLOCI_DATA_DIR="${FLOCI_DATA_DIR:-$HOME/.local/share/floci-propuestas}"
BACKEND_DIR=${BACKEND_DIR:-../thesis-back-quarkus}
FRONTEND_DIR=${FRONTEND_DIR:-../thesis-front-react}
source scripts/aws-floci/lib.sh
for c in docker git curl jq aws; do command -v "$c" >/dev/null || die "falta la herramienta: $c"; done
docker compose version >/dev/null 2>&1 || die "falta el plugin docker compose"
[ -f "$BACKEND_DIR/core/src/main/docker/Dockerfile" ] || die "BACKEND_DIR=$BACKEND_DIR no es thesis-back-quarkus"
[ -f "$FRONTEND_DIR/Dockerfile" ] || die "FRONTEND_DIR=$FRONTEND_DIR no tiene Dockerfile"

etiqueta() {   # SHA corto del repo; -dirty-<epoch> si hay cambios sin commit
  local t; t=$(git -C "$1" rev-parse --short=7 HEAD)
  [ -z "$(git -C "$1" status --porcelain)" ] || t="$t-dirty-$(date +%s)"
  echo "$t"
}

echo "== Floci local (datos en $FLOCI_DATA_DIR)"
mkdir -p "$FLOCI_DATA_DIR"
docker compose -f clusters/aws-floci/compose.yaml up -d
for _ in $(seq 1 60); do curl -fsS "$FLOCI/_floci/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$FLOCI/_floci/health" | jq -r '"Floci " + .version'

BT=$(etiqueta "$BACKEND_DIR"); FT=$(etiqueta "$FRONTEND_DIR")
echo "== construcción de imágenes (backend $BT, frontend $FT)"
docker build -q -f "$BACKEND_DIR/core/src/main/docker/Dockerfile" -t "propuestas-api:$BT" "$BACKEND_DIR" >/dev/null
docker build -q -f "$BACKEND_DIR/documentos/src/main/docker/Dockerfile" -t "propuestas-documentos:$BT" "$BACKEND_DIR" >/dev/null
docker build -q -t "propuestas-web:$FT" "$FRONTEND_DIR" >/dev/null
echo "propuestas-api:$BT propuestas-documentos:$BT propuestas-web:$FT"

# up.sh: tofu crea los repos ECR (fase 2) y copy-images.sh hace docker push de estas imágenes (fase 5) sin pasar por GHCR
export IMAGES_SOURCE=local API_TAG=$BT DOCUMENTOS_TAG=$BT WEB_TAG=$FT NODE_COUNT=1
exec scripts/aws-floci/up.sh "$@"
