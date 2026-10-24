#!/usr/bin/env bash
# Reejecuta Pasos 1-5. Requiere KUBECONFIG, DEMO_PASSWORD, k6/trivy en PATH, port-forwards (Paso 4 manual: ver docs/evidencias/README.md).
set -eu; cd "$(dirname "$0")/.."
tests/run-hpa.sh
tests/chaos/rolling-update.sh
tests/chaos/pod-kill.sh
tests/chaos/node-failure.sh "${NODE_VM:-k3s-lab-2}" node
tests/security-scans.sh
