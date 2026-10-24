#!/usr/bin/env bash
# kustomize build | kubeconform para cada overlay.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
for o in local prod; do
  echo "== overlay $o"
  kubectl kustomize "k8s/propuestas/overlays/$o" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
for e in local prod; do
  echo "== platform $e"
  kubectl kustomize "k8s/platform/$e" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
