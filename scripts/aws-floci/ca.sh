#!/usr/bin/env bash
# Escribe la CA del ALB (output de tofu) en ./aws-floci-alb-ca.pem para importarla en el navegador/SO (G6).
set -euo pipefail
cd "$(dirname "$0")/../.."
FLOCI_IP=${FLOCI_IP:-0.0.0.0} source scripts/aws-floci/lib.sh   # solo para TF_DATA_DIR (el IP no se usa aqui)
tofu_out alb_ca_pem > "${1:-aws-floci-alb-ca.pem}"
openssl x509 -in "${1:-aws-floci-alb-ca.pem}" -noout -subject -fingerprint -sha256
