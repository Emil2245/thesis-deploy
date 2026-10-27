#!/usr/bin/env bash
# Desmonta el entorno aws-floci (deja Floci y la VM en marcha): borra los nodos adicionales y destruye la infraestructura de tofu.
# Con --reset borra además todo el estado de Floci (equivale a una VM limpia); después se puede ejecutar up.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
export KUBECONFIG="$AWS_KUBECONFIG"   # down.sh borra este archivo: nunca el KUBECONFIG del entorno
$SSH 'for n in $(docker ps -aq --filter name=floci-aws-eks-propuestas-worker-); do docker rm -f $n >/dev/null; done; rm -rf $HOME/floci-workers'
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test tofu -chdir=infra/aws-floci destroy -auto-approve -input=false -var "floci_endpoint=$FLOCI"
rm -f "$AWS_KUBECONFIG"
if [ "${1:-}" = "--reset" ]; then
  $SSH 'cd /opt/floci && docker compose down -v && sudo rm -rf /opt/floci/data && sudo mkdir -p /opt/floci/data && docker compose up -d'
  rm -f infra/aws-floci/terraform.tfstate*
  rm -f "$CRED"
fi
echo "aws-floci desmontado"
