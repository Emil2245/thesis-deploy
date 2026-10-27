# Funciones comunes de scripts/vps (se hace `source`). Nada aqui imprime secretos.
# kubeconfig: VPS_KUBECONFIG; si no, KUBECONFIG; si no, ~/.kube/propuestas-vps.yaml (mismo orden en todos los scripts).
# up.sh y down.sh CREAN/BORRAN ese archivo, por lo que nunca toman KUBECONFIG (podria ser el de otro clúster): solo VPS_KUBECONFIG o el defecto.
VPS_KUBECONFIG_ENV="${VPS_KUBECONFIG:-}"   # lo que el operador exporto (vacio si nada)
VPS_KUBECONFIG_DEFECTO="$HOME/.kube/propuestas-vps.yaml"
VPS_KUBECONFIG="${VPS_KUBECONFIG:-$VPS_KUBECONFIG_DEFECTO}"
K3S_VERSION="${K3S_VERSION:-v1.37.1+k3s1}"   # igual que infra/hetzner, clusters/local y scripts/lab/render-seeds.sh
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
sshopts() {
  local o=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
  [ -n "$SSH_KEY" ] && o+=(-i "$SSH_KEY")
  printf '%s\n' "${o[@]}"
}
# rssh <ip> <comando...>: ejecuta en el VPS (el comando se pasa tal cual al shell remoto)
rssh() { local ip=$1; shift; mapfile -t o < <(sshopts); ssh "${o[@]}" "$SSH_USER@$ip" "$@"; }
fase() { printf '\n== [%ss] fase %s\n' $((SECONDS-${T0:-0})) "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
# usar_kubeconfig: para los scripts que solo LEEN el clúster (smoke, restore-drill, hpa-test). Falla con un mensaje claro.
usar_kubeconfig() {
  local kc
  if [ -n "${VPS_KUBECONFIG_ENV:-}" ]; then kc=$VPS_KUBECONFIG_ENV
  elif [ -n "${KUBECONFIG:-}" ]; then kc=$KUBECONFIG
  else kc=$VPS_KUBECONFIG_DEFECTO; fi
  local primero=${kc%%:*}
  [ -f "$primero" ] || die "no existe el kubeconfig '$primero' (se busca VPS_KUBECONFIG, luego KUBECONFIG, luego $VPS_KUBECONFIG_DEFECTO); obtengalo como indica el capitulo 5 o ejecute up.sh"
  export KUBECONFIG="$kc"; VPS_KUBECONFIG="$kc"
  kubectl get --raw /readyz --request-timeout=15s >/dev/null 2>&1 || die "la API de Kubernetes no responde con el kubeconfig '$kc' (servidor apagado, IP cambiada o archivo obsoleto); compruebe con: kubectl get nodes"
}
