#!/usr/bin/env bash
# Preparación del clúster EKS emulado (G4/G2, plan 040). Idempotente.
#  1. CoreDNS: el nombre "floci" (el único que cubre el certificado de Floci) resuelve a la IP del contenedor Floci.
#  2. CA de Floci (pública, no es un secreto) en un ConfigMap "floci-ca" por namespace que habla con Floci.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
usar_kubeconfig
FIP=$($SSH "docker inspect -f '{{.NetworkSettings.Networks.floci_default.IPAddress}}' floci")
[ -n "$FIP" ] || { echo "no se pudo obtener la IP de Floci" >&2; exit 1; }
cur=$(kubectl -n kube-system get cm coredns-custom -o jsonpath='{.data.floci\.server}' 2>/dev/null | grep -o '[0-9.]* floci' || true)
if [ "$cur" != "$FIP floci" ]; then
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  floci.server: |
    floci:53 {
        hosts {
            $FIP floci
        }
        errors
        cache 30
    }
YAML
  kubectl -n kube-system rollout restart deploy coredns >/dev/null
  kubectl -n kube-system rollout status deploy coredns --timeout=120s >/dev/null
fi
CA=$(mktemp); trap 'rm -f "$CA"' EXIT
curl -fsS "http://$FLOCI_IP:4566/_floci/ca.pem" -o "$CA"
openssl x509 -in "$CA" -noout -subject >/dev/null
for ns in propuestas logging external-secrets pod-identity monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" create configmap floci-ca --from-file=ca.pem="$CA" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
# Pod Security como en la base (idempotente)
kubectl label namespace propuestas pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
echo "cluster-prep: floci=$FIP, CA publicada en: propuestas logging external-secrets pod-identity monitoring"
