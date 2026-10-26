#!/usr/bin/env bash
# Levanta el entorno aws-floci sobre una VM aws-lab-1 ya creada (ver clusters/aws-floci/README.md).
# Orden: tofu apply -> kubeconfig -> copia de imágenes -> Argo CD -> secretos.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/aws-floci/lib.sh
API_TAG=$(awk '/propuestas-api/{f=1} f&&/newTag/{print $2; exit}' k8s/propuestas/overlays/aws/kustomization.yaml)
WEB_TAG=$(awk '/propuestas-web/{f=1} f&&/newTag/{print $2; exit}' k8s/propuestas/overlays/aws/kustomization.yaml)
tofu -chdir=infra/aws-floci init -input=false >/dev/null
tofu -chdir=infra/aws-floci apply -auto-approve -var "floci_endpoint=$FLOCI"
scripts/aws-floci/kubeconfig.sh
scripts/aws-floci/copy-images.sh "$API_TAG" "$WEB_TAG"
scripts/aws-floci/sync-secrets.sh
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 10.11.1 -f k8s/argocd/values-aws.yaml --wait --timeout 10m
kubectl apply -f k8s/argocd/root-aws.yaml
echo "Listo: http://$FLOCI_IP:8080 (ALB emulado)"
