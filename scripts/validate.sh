#!/usr/bin/env bash
# kustomize build | kubeconform para cada overlay.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
for o in local lab prod aws vps; do
  echo "== overlay $o"
  kubectl kustomize "k8s/propuestas/overlays/$o" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
for e in local lab prod vps; do
  echo "== platform $e"
  kubectl kustomize "k8s/platform/$e" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
for d in issuers dashboards tunnel backup-store; do
  echo "== platform/$d/manifests"
  kubectl kustomize "k8s/platform/$d/manifests" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
echo "== aws-floci: plataforma y apps"
for d in k8s/platform/aws-floci/fluent-bit k8s/platform/aws-floci/pod-identity-relay k8s/platform/aws-floci/eso-config k8s/platform/aws-floci k8s/apps/propuestas-aws; do
  kubectl kustomize "$d" | kubeconform -strict -summary -ignore-missing-schemas \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
if command -v tofu >/dev/null; then
  echo "== infra/aws-floci (tofu fmt + validate)"
  # caches bajo $HOME (no /tmp: en algunos equipos es un tmpfs pequeno y el proveedor de AWS, ~300 MB, no cabe)
  C="${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-floci"; mkdir -p "$C/tmp" "$C/tfdata" "$C/tf-plugins"
  export TMPDIR="$C/tmp" TF_DATA_DIR="$C/tfdata" TF_PLUGIN_CACHE_DIR="$C/tf-plugins"
  tofu -chdir=infra/aws-floci fmt -check
  tofu -chdir=infra/aws-floci init -backend=false -input=false >/dev/null
  tofu -chdir=infra/aws-floci validate
fi
echo "== platform/issuers/lab"
kubectl kustomize k8s/platform/issuers/lab | kubeconform -strict -summary -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
echo "== dashboard JSON"
kubectl kustomize k8s/platform/dashboards/manifests \
  | python3 -c 'import sys,json,re
t=sys.stdin.read(); import subprocess
# extrae el bloque literal data.propuestas.json y lo valida
m=re.search(r"propuestas.json: \|\n((?:    .*\n)+)", t); json.loads("\n".join(l[4:] for l in m.group(1).splitlines())); print("dashboard JSON OK")'
