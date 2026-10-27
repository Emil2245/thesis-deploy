# Funciones comunes de scripts/vps (se hace `source`). Nada aqui imprime secretos.
VPS_KUBECONFIG="${VPS_KUBECONFIG:-$HOME/.kube/propuestas-vps.yaml}"
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
