#!/usr/bin/env bash
# Paso 5: escaneos de seguridad y conformidad. Requiere trivy, kubectl.
set -u; cd "$(dirname "$0")/.."; out=docs/evidencias/seguridad; mkdir -p $out
api=$(kubectl -n propuestas get deploy propuestas-api -o jsonpath='{.spec.template.spec.containers[0].image}')
web=$(kubectl -n propuestas get deploy propuestas-web -o jsonpath='{.spec.template.spec.containers[0].image}')
trivy image --severity HIGH,CRITICAL "$api" > $out/trivy-image-api.txt 2>&1
trivy image --severity HIGH,CRITICAL "$web" > $out/trivy-image-web.txt 2>&1
trivy config --severity HIGH,CRITICAL k8s/ > $out/trivy-config.txt 2>&1
scripts/validate.sh > $out/kubeconform.txt 2>&1
kubectl label --dry-run=server --overwrite ns propuestas pod-security.kubernetes.io/enforce=restricted > $out/pss.txt 2>&1
{ echo "# pod  runAsNonRoot(pod)  runAsNonRoot(containers)"
  kubectl -n propuestas get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.securityContext.runAsNonRoot}{"  "}{.spec.containers[*].securityContext.runAsNonRoot}{"\n"}{end}'; } > $out/runasnonroot.txt
