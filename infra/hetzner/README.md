# infra/hetzner

OpenTofu (>= 1.8; probado con 1.13.2) + provider `hetznercloud/hcloud ~> 1.70` (lock: 1.70.x) + `hashicorp/random`.
Crea red privada 10.0.0.0/16, firewall, llave SSH, 1 nodo k3s server y `agent_count` agents
(Ubuntu 24.04, k3s `v1.37.1+k3s1`, igual que el local `rancher/k3s:v1.37.1-k3s1`). Cloud-init instala k3s;
luego `scripts/bootstrap.sh prod` instala Argo CD (GitOps).

## Uso
```bash
export HCLOUD_TOKEN=...                       # solo entorno
export TF_VAR_admin_cidrs='["<tu-ip>/32"]'    # SSH y API 6443
scripts/prod-up.sh                            # init + apply + kubeconfig + bootstrap
scripts/prod-down.sh                          # destroy (confirmacion)
```
Validar sin token: `tofu -chdir=infra/hetzner init && tofu -chdir=infra/hetzner validate && tflint --chdir=infra/hetzner`.

## Defaults y costo
| Variable | Default | Specs |
|---|---|---|
| `location` | `ash` (Ashburn, US-East) | CX* no existe en US; CPX* si |
| `server_type_server` | `cpx32` | 4 vCPU AMD / 8 GB |
| `server_type_agent` | `cpx22` | 2 vCPU AMD / 4 GB |

Alternativa UE (mas barata): `location=nbg1`, `cx33` (4 vCPU/8 GB) y `cx23` (2 vCPU/4 GB).
Costo mensual (sin IVA, **estimado**: la pagina oficial no expone precios sin sesion y las fuentes terceras discrepan):
UE ~ cx33 EUR 6.49 + cx23 EUR 3.99 + 2 IPv4 x EUR 0.50 = ~EUR 11.5; US (ash) con CPX: precios ~20% sobre UE y solo 1 TB de trafico;
fuentes dan CPX22 EUR 7.99-19.99 y CPX32 hasta EUR 35.99 (UE), es decir ~EUR 15-60/mes en ash.
**Verificar con la consola/`hcloud server-type list` antes de `apply`.**
Fuentes: hetzner.com/cloud, docs.hetzner.com/cloud/servers/overview, vpsbenchmarks.com (cx23/cpx22/cpx32), bitdoze.com (ajuste abril 2026).

## Estado y secretos
El state es local (`terraform.tfstate`, ignorado por git) y **contiene secretos** (token k3s). No commitear
state, `terraform.tfvars`, tokens ni kubeconfig. Remoto (Hetzner Object Storage S3) diferido.
Los datos de CNPG viven en el disco local de cada nodo (local-path): sin backups automaticos (limitacion).
Region `ash` implica transferencia internacional de datos personales (LOPDP): declararla.
