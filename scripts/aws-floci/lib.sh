# Variables comunes para los helpers de aws-floci (se hace `source`).
# FLOCI = endpoint del emulador (IP de la VM aws-lab-1). Credenciales ficticias (no son secretos).
: "${FLOCI_IP:=192.168.1.12}"
: "${FLOCI:=http://$FLOCI_IP:4566}"
export FLOCI FLOCI_IP
# Credenciales del operador (clave de acceso IAM creada por kubeconfig.sh; fuera de git). Floci rechaza test/test para EKS.
CRED="${AWS_FLOCI_CRED:-$HOME/.config/propuestas-aws/credentials}"
if [ -r "$CRED" ]; then set -a; . "$CRED"; set +a; else export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test; fi
export AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=
export KUBECONFIG="${KUBECONFIG_AWS:-$HOME/.kube/propuestas-aws.yaml}"
# aws CLI apuntando al emulador (v1 no lee AWS_ENDPOINT_URL).
awsf() { aws --endpoint-url "$FLOCI" "$@"; }
