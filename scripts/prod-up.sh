#!/usr/bin/env bash
# Crea la infraestructura de produccion (Hetzner + k3s) y hace bootstrap de Argo CD.
# Requiere: HCLOUD_TOKEN y TF_VAR_admin_cidrs (p.ej. '["1.2.3.4/32"]') en el entorno.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
: "${HCLOUD_TOKEN:?exportar HCLOUD_TOKEN (nunca guardarlo en archivos)}"
: "${TF_VAR_admin_cidrs:?exportar TF_VAR_admin_cidrs, p.ej. '[\"1.2.3.4/32\"]'}"
TF=(tofu -chdir=infra/hetzner)
KUBE="$HOME/.kube/propuestas-prod.yaml"

"${TF[@]}" init
"${TF[@]}" apply
IP="$("${TF[@]}" output -raw server_ipv4)"
echo "Server: $IP"

echo "Esperando SSH..."
until ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "root@$IP" true 2>/dev/null; do sleep 5; done
echo "Esperando k3s (cloud-init)..."
until ssh "root@$IP" test -s /etc/rancher/k3s/k3s.yaml 2>/dev/null; do sleep 10; done

mkdir -p "$(dirname "$KUBE")"
ssh "root@$IP" cat /etc/rancher/k3s/k3s.yaml | sed "s#127.0.0.1#$IP#" > "$KUBE"
chmod 600 "$KUBE"

if grep -rq PROD_IP k8s/propuestas/overlays/prod k8s/platform/prod; then
  read -r -p "Reemplazar PROD_IP por $IP, commit y push? [s/N] " ans
  if [ "$ans" = s ]; then
    grep -rl PROD_IP k8s/propuestas/overlays/prod k8s/platform/prod | xargs sed -i "s/PROD_IP/$IP/g"
    git add k8s && git commit -m "chore(prod): host sslip.io $IP" && git push
  fi
fi

KUBECONFIG="$KUBE" scripts/bootstrap.sh prod

if [ -x scripts/seal-jwt.sh ]; then
  KUBECONFIG="$KUBE" scripts/seal-jwt.sh prod
  echo "Habilitar sealed-jwt.yaml en k8s/propuestas/overlays/prod/kustomization.yaml, commit y push."
fi
echo "Listo: $("${TF[@]}" output -raw app_url)  (kubeconfig: $KUBE)"
