#!/usr/bin/env bash
# Construye las imágenes desde los submódulos (o BACKEND_DIR/FRONTEND_DIR) e importa a k3d.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
BACKEND_DIR="${BACKEND_DIR:-$PWD/apps/backend}"
FRONTEND_DIR="${FRONTEND_DIR:-$PWD/apps/frontend}"
CLUSTER="${CLUSTER:-propuestas}"
API=ghcr.io/emil2245/propuestas-api:local
WEB=ghcr.io/emil2245/propuestas-web:local

[ -f "$BACKEND_DIR/src/main/docker/Dockerfile" ] || { echo "Falta Dockerfile backend en $BACKEND_DIR (plan 006)"; exit 1; }
[ -f "$FRONTEND_DIR/Dockerfile" ] || { echo "Falta Dockerfile frontend en $FRONTEND_DIR (plan 007)"; exit 1; }

podman build -f "$BACKEND_DIR/src/main/docker/Dockerfile" -t "$API" "$BACKEND_DIR"
podman build -f "$FRONTEND_DIR/Dockerfile" -t "$WEB" "$FRONTEND_DIR"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for pair in "api:$API" "web:$WEB"; do
  n="${pair%%:*}"; img="${pair#*:}"
  podman save "$img" -o "$T/$n.tar"
  k3d image import "$T/$n.tar" -c "$CLUSTER"
done
