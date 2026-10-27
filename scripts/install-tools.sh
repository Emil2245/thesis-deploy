#!/usr/bin/env bash
# Instala kubectl, helm, k3d, kubeconform, tofu, tflint, kubeseal, jq y k6 en ~/.local/bin (sin sudo, Linux amd64).
# curl, openssl, git y ssh vienen del sistema operativo: el script solo los comprueba (no instala paquetes).
set -euo pipefail
KUBECTL_VERSION=v1.37.1
HELM_VERSION=v4.3.1
K3D_VERSION=v5.9.0
KUBECONFORM_VERSION=v0.8.0
TOFU_VERSION=1.13.2
TFLINT_VERSION=v0.65.0
KUBESEAL_VERSION=0.41.1
JQ_VERSION=1.8.2
K6_VERSION=v2.3.0
BIN="${HOME}/.local/bin"; mkdir -p "$BIN"
for c in curl openssl git ssh; do
  command -v "$c" >/dev/null || { echo "Falta '$c': instalelo con el gestor de paquetes del sistema (p. ej. sudo apt install curl openssl git openssh-client)" >&2; exit 1; }
done
# Descarga y extrae bajo $HOME (no en /tmp: en algunos equipos es un tmpfs pequeno y tar falla con "Wrote only ...")
W="${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-tools"; mkdir -p "$W"
T="$(mktemp -d -p "$W")"; trap 'rm -rf "$T"' EXIT
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

# OpenTofu (SHA256SUMS publicado)
curl -fsSLO "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" -o tofu.sums
grep " tofu_${TOFU_VERSION}_linux_amd64.tar.gz\$" tofu.sums | sha256sum -c -
tar xzf "tofu_${TOFU_VERSION}_linux_amd64.tar.gz" tofu; install -m 0755 tofu "$BIN/tofu"

# tflint (checksums.txt publicado)
curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip"
curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/checksums.txt" -o tflint.sums
grep ' tflint_linux_amd64.zip$' tflint.sums | sha256sum -c -
python3 -c 'import zipfile;zipfile.ZipFile("tflint_linux_amd64.zip").extract("tflint")'; install -m 0755 tflint "$BIN/tflint"

# kubeseal (checksum publicado)
curl -fsSLO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/sealed-secrets_${KUBESEAL_VERSION}_checksums.txt" -o ks.sums
grep " kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz\$" ks.sums | sha256sum -c -
tar xzf "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal; install -m 0755 kubeseal "$BIN/kubeseal"

# jq (sha256sum.txt publicado)
curl -fsSLO "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"
curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/sha256sum.txt" -o jq.sums
grep ' jq-linux-amd64$' jq.sums | sha256sum -c -
install -m 0755 jq-linux-amd64 "$BIN/jq"

# k6 (checksums publicados)
curl -fsSLO "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-amd64.tar.gz"
curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-checksums.txt" -o k6.sums
grep " k6-${K6_VERSION}-linux-amd64.tar.gz\$" k6.sums | sha256sum -c -
tar xzf "k6-${K6_VERSION}-linux-amd64.tar.gz"; install -m 0755 "k6-${K6_VERSION}-linux-amd64/k6" "$BIN/k6"

echo "Instalado en $BIN:"
# Falla en voz alta si alguna herramienta no quedo en la version esperada
check() { local n=$1 want=$2; shift 2; local got; got="$("$@" 2>&1 | head -3)"
  case "$got" in *"$want"*) echo "OK $n $want";; *) echo "ERROR: $n no esta en la version esperada ($want): $got" >&2; exit 1;; esac; }
check kubectl "$KUBECTL_VERSION" "$BIN/kubectl" version --client
check helm "$HELM_VERSION" "$BIN/helm" version
check k3d "$K3D_VERSION" "$BIN/k3d" version
check kubeconform "${KUBECONFORM_VERSION#v}" "$BIN/kubeconform" -v
check tofu "$TOFU_VERSION" "$BIN/tofu" version
check tflint "${TFLINT_VERSION#v}" "$BIN/tflint" --version
check kubeseal "$KUBESEAL_VERSION" "$BIN/kubeseal" --version
check jq "$JQ_VERSION" "$BIN/jq" --version
check k6 "${K6_VERSION#v}" "$BIN/k6" version
