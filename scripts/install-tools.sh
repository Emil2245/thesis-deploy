#!/usr/bin/env bash
# Instala kubectl, helm, k3d y kubeconform en ~/.local/bin (sin sudo).
set -euo pipefail
KUBECTL_VERSION=v1.37.1
HELM_VERSION=v4.3.1
K3D_VERSION=v5.9.0
KUBECONFORM_VERSION=v0.8.0
BIN="${HOME}/.local/bin"; mkdir -p "$BIN"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"

# kubectl (checksum publicado)
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -o kubectl.sha256
echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
install -m 0755 kubectl "$BIN/kubectl"

# helm (checksum publicado)
curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" -o helm.sum
sha256sum -c helm.sum
tar xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"; install -m 0755 linux-amd64/helm "$BIN/helm"

# k3d (checksums.txt publicado)
curl -fsSL "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64" -o k3d-linux-amd64
curl -fsSL "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/checksums.txt" -o k3d.sums
grep ' _dist/k3d-linux-amd64$' k3d.sums | sed 's#_dist/##' | sha256sum -c -
install -m 0755 k3d-linux-amd64 "$BIN/k3d"

# kubeconform
curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/CHECKSUMS" -o kc.sums || true
if [ -s kc.sums ]; then grep ' kubeconform-linux-amd64.tar.gz$' kc.sums | sha256sum -c -; fi
tar xzf kubeconform-linux-amd64.tar.gz kubeconform; install -m 0755 kubeconform "$BIN/kubeconform"

echo "Instalado en $BIN:"; for t in kubectl helm k3d kubeconform; do "$BIN/$t" version 2>&1 | head -1 || true; done
