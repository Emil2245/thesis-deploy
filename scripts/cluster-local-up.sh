#!/usr/bin/env bash
# Crea el clúster k3d local (rootless podman). Mantiene Traefik y metrics-server de k3s.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
export DOCKER_SOCK="${XDG_RUNTIME_DIR}/podman/podman.sock"
k3d cluster create --config clusters/local/k3d-config.yaml ${K3D_EXTRA_ARGS:-}
kubectl config use-context k3d-propuestas
kubectl wait --for=condition=Ready nodes --all --timeout=180s
