#!/usr/bin/env bash
# Escribe la CA del ALB (output de tofu) en ./aws-floci-alb-ca.pem para importarla en el navegador/SO (G6).
set -euo pipefail
cd "$(dirname "$0")/../.."
tofu -chdir=infra/aws-floci output -raw alb_ca_pem > "${1:-aws-floci-alb-ca.pem}"
openssl x509 -in "${1:-aws-floci-alb-ca.pem}" -noout -subject -fingerprint -sha256
