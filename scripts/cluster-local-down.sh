#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
k3d cluster delete propuestas
