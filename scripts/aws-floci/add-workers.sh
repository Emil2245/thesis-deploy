#!/usr/bin/env bash
# G1 (plan 040): nodos de trabajo adicionales para el EKS emulado.
# Floci materializa UN solo contenedor k3s por clúster (todos los node groups comparten ese nodo; docs/services/eks.md,
# "Single shared node mapping"), así que el aws_eks_node_group (desired N) queda como metadato. Para tener N nodos
# reales se unen N-1 agentes k3s (misma versión/imagen que el servidor) a la red docker del clúster.
# En AWS real esto lo haría el propio node group. Uso: add-workers.sh [total-de-nodos (def. 2)]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TOTAL=${1:-2}
SSH="ssh -i ${LAB_KEY:-$HOME/.ssh/tesis-lab} -o BatchMode=yes ubuntu@$FLOCI_IP"
CL=${CLUSTER:-propuestas}
# el token del clúster viaja solo dentro de la VM (nunca a pantalla ni a disco local)
$SSH "bash -s" "$CL" "$TOTAL" <<'REMOTE'
set -euo pipefail
CL=$1; TOTAL=$2; SRV=floci-aws-eks-$CL
ver=$(docker exec "$SRV" k3s --version | awk 'NR==1{print $3}' | tr + -)   # v1.37.0-k3s1
net=floci_default
mkdir -p "$HOME/floci-workers"
docker cp "$SRV:/etc/rancher/k3s/registries.yaml" $HOME/floci-workers/registries.yaml
token=$(docker exec "$SRV" cat /var/lib/rancher/k3s/server/node-token)
srvip=$(docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' "$SRV")   # IP de nodo del servidor (red bridge)
for i in $(seq 1 $((TOTAL-1))); do
  n=$SRV-worker-$i
  if docker inspect "$n" >/dev/null 2>&1; then echo "$n ya existe"; continue; fi
  # el agente se une por la red bridge (donde el servidor anuncia su IP) y además a floci_default (DNS "floci" para el espejo de ECR)
  docker create --name "$n" --hostname "worker-$i.ec2.internal" --privileged --restart unless-stopped \
    -e K3S_URL="https://$srvip:6443" -e K3S_TOKEN="$token" \
    -v "$HOME/floci-workers/registries.yaml:/etc/rancher/k3s/registries.yaml:ro" \
    --tmpfs /run --tmpfs /var/run \
    "rancher/k3s:$ver" agent --node-name "worker-$i.ec2.internal" \
      --node-label topology.kubernetes.io/zone=us-east-1a --node-label eks.amazonaws.com/nodegroup=workers >/dev/null
  docker network connect --ip "172.18.0.$((200+i))" "$net" "$n"   # IP fija: el ALB la usa como target (infra/aws-floci/alb.tf)
  docker start "$n" >/dev/null
  echo "$n creado ($ver, 172.18.0.$((200+i)))"
done
REMOTE
for _ in $(seq 1 60); do
  r=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  [ "$r" -ge "$TOTAL" ] && break; sleep 5
done
kubectl get nodes
[ "$r" -ge "$TOTAL" ]
