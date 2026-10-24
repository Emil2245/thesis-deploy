#!/usr/bin/env bash
# kustomize build | kubeconform para cada overlay.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
for o in local lab prod; do
  echo "== overlay $o"
  kubectl kustomize "k8s/propuestas/overlays/$o" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
for e in local lab prod; do
  echo "== platform $e"
  kubectl kustomize "k8s/platform/$e" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
for d in issuers dashboards tunnel; do
  echo "== platform/$d/manifests"
  kubectl kustomize "k8s/platform/$d/manifests" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
echo "== dashboard JSON"
kubectl kustomize k8s/platform/dashboards/manifests \
  | python3 -c 'import sys,json,re
t=sys.stdin.read(); import subprocess
# extrae el bloque literal data.propuestas.json y lo valida
m=re.search(r"propuestas.json: \|\n((?:    .*\n)+)", t); json.loads("\n".join(l[4:] for l in m.group(1).splitlines())); print("dashboard JSON OK")'
