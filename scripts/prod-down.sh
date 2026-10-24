#!/usr/bin/env bash
# Destruye TODA la infraestructura de produccion (con confirmacion).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
: "${HCLOUD_TOKEN:?exportar HCLOUD_TOKEN}"
: "${TF_VAR_admin_cidrs:?exportar TF_VAR_admin_cidrs (requerida por el modulo)}"
read -r -p "Esto destruye servidores, red y firewall de produccion. Escribe 'destruir': " ans
[ "$ans" = destruir ] || { echo "Cancelado."; exit 1; }
tofu -chdir=infra/hetzner destroy
