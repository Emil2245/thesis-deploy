# Variables y funciones comunes de los helpers de aws-floci (se hace `source`). Nada aqui imprime secretos.
# FLOCI_IP = IP de la VM de Floci (obligatoria). FLOCI = endpoint del emulador. Las credenciales de Floci son ficticias.
die() { echo "ERROR: $*" >&2; exit 1; }
: "${FLOCI_IP:?exporte FLOCI_IP=<ip de la VM de Floci> (ver el manual, capitulo 2)}"
: "${FLOCI:=http://$FLOCI_IP:4566}"
export FLOCI FLOCI_IP
# Caches y temporales bajo $HOME (no en /tmp: en algunos equipos es un tmpfs pequeno y tofu/tar fallan con "disk quota exceeded").
FLOCI_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/propuestas-floci"
export TF_DATA_DIR="${TF_DATA_DIR:-$FLOCI_CACHE/tfdata}" TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$FLOCI_CACHE/tf-plugins}"
export TMPDIR="${FLOCI_TMPDIR:-$FLOCI_CACHE/tmp}"
mkdir -p "$TF_DATA_DIR" "$TF_PLUGIN_CACHE_DIR" "$TMPDIR"
# Credenciales del operador (clave de acceso IAM creada por kubeconfig.sh; fuera de git). Floci rechaza test/test para EKS.
CRED="${AWS_FLOCI_CRED:-$HOME/.config/propuestas-aws/credentials}"
if [ -r "$CRED" ]; then set -a; . "$CRED"; set +a; else export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test; fi
export AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=
# kubeconfig: AWS_KUBECONFIG; si no, KUBECONFIG; si no, ~/.kube/propuestas-aws.yaml (mismo orden en todos los scripts).
# up.sh, down.sh y kubeconfig.sh CREAN/BORRAN ese archivo, por lo que nunca toman KUBECONFIG (podria ser el de otro cluster).
AWS_KUBECONFIG_ENV="${AWS_KUBECONFIG:-}"
AWS_KUBECONFIG_DEFECTO="$HOME/.kube/propuestas-aws.yaml"
AWS_KUBECONFIG="${AWS_KUBECONFIG:-$AWS_KUBECONFIG_DEFECTO}"
usar_kubeconfig() {   # para los scripts que solo LEEN el cluster
  local kc primero
  if [ -n "$AWS_KUBECONFIG_ENV" ]; then kc=$AWS_KUBECONFIG_ENV
  elif [ -n "${KUBECONFIG:-}" ]; then kc=$KUBECONFIG
  else kc=$AWS_KUBECONFIG_DEFECTO; fi
  primero=${kc%%:*}
  [ -f "$primero" ] || die "no existe el kubeconfig '$primero' (se busca AWS_KUBECONFIG, luego KUBECONFIG, luego $AWS_KUBECONFIG_DEFECTO); obtengalo con scripts/aws-floci/kubeconfig.sh o ejecute up.sh"
  export KUBECONFIG="$kc"
  kubectl get --raw /readyz --request-timeout=15s >/dev/null 2>&1 || die "la API de Kubernetes no responde con el kubeconfig '$kc' (VM apagada, IP cambiada o archivo obsoleto); compruebe con: kubectl get nodes"
}
# aws CLI apuntando al emulador (v1 no lee AWS_ENDPOINT_URL).
awsf() { aws --endpoint-url "$FLOCI" "$@"; }
# SSH a la VM de Floci (clave LAB_KEY; la huella de un host nuevo se acepta, la de uno conocido que cambia se rechaza)
LAB_KEY="${LAB_KEY:-$HOME/.ssh/tesis-lab}"
SSHOPTS=(-i "$LAB_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
SSH="ssh ${SSHOPTS[*]} ubuntu@$FLOCI_IP"
# tofu_out <nombre> [raw]: lee un output del estado local (infra/aws-floci/terraform.tfstate) con jq, sin tofu: no exige
# proveedores instalados (evita descargar ~300 MB solo para leer un valor).
tofu_out() {
  local f=infra/aws-floci/terraform.tfstate
  [ -r "$f" ] || die "no existe $f (ejecute antes el capitulo 4: tofu apply, o up.sh)"
  jq -er --arg n "$1" '.outputs[$n].value | tostring' "$f" || die "el estado no tiene el output '$1'"
}
# tofu_init: init con caches en $HOME; si un intento anterior dejo un proveedor a medias, lo limpia y repite una vez.
tofu_init() {
  local d=infra/aws-floci
  tofu -chdir=$d init -input=false >/dev/null 2>&1 && return 0
  echo "tofu init fallo; se limpia la cache parcial de proveedores y se repite" >&2
  rm -rf "$TF_DATA_DIR/providers" "$d/.terraform/providers" "$TF_PLUGIN_CACHE_DIR"; mkdir -p "$TF_PLUGIN_CACHE_DIR"
  tofu -chdir=$d init -input=false >/dev/null || die "tofu init fallo (compruebe espacio en disco y red)"
}
