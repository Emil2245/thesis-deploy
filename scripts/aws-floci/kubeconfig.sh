#!/usr/bin/env bash
# Escribe ~/.kube/propuestas-aws.yaml (fuera de git) para el EKS emulado "propuestas".
# El endpoint que anuncia Floci es https://localhost:<puerto>; se reemplaza por la IP de la VM.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
CL=${1:-propuestas}
# Floci rechaza test/test en la autenticación EKS (otorgaría cluster-admin): crear un usuario IAM operador con clave propia.
if [ ! -r "$CRED" ] || ! grep -q AKIA "$CRED"; then
  mkdir -p "$(dirname "$CRED")"; chmod 700 "$(dirname "$CRED")"
  AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$FLOCI" iam create-user --user-name propuestas-operator >/dev/null 2>&1 || true
  k=$(AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --endpoint-url "$FLOCI" iam create-access-key --user-name propuestas-operator --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  umask 077; printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' $k > "$CRED"
  source "$(dirname "$0")/lib.sh"
fi
ep=$(awsf eks describe-cluster --name "$CL" --query cluster.endpoint --output text)
rm -f "$KUBECONFIG"
awsf eks update-kubeconfig --name "$CL" --kubeconfig "$KUBECONFIG" >/dev/null
sed -i -e "s#https://localhost:#https://$FLOCI_IP:#" -e "s#https://floci-aws-eks-[a-z0-9-]*:#https://$FLOCI_IP:#" "$KUBECONFIG"
# el plugin exec de aws necesita credenciales del operador en su entorno (kubeconfig 0600, fuera de git)
python3 - "$KUBECONFIG" <<'PY'
import sys,re,os
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"(      command: .*\n)", r"\1      env:\n      - {name: AWS_ACCESS_KEY_ID, value: " + os.environ["AWS_ACCESS_KEY_ID"] + "}\n      - {name: AWS_SECRET_ACCESS_KEY, value: " + os.environ["AWS_SECRET_ACCESS_KEY"] + "}\n      - {name: AWS_DEFAULT_REGION, value: us-east-1}\n", s, count=1)
open(p,'w').write(s)
PY
# el certificado del API server cubre 127.0.0.1 pero no la IP de la VM: se valida contra ese nombre (CA verificada)
kubectl config set-cluster "$(kubectl config view -o jsonpath='{.clusters[0].name}')" --tls-server-name=127.0.0.1 >/dev/null
chmod 600 "$KUBECONFIG"
echo "kubeconfig: $KUBECONFIG (endpoint anunciado: $ep -> https://$FLOCI_IP:...)"
