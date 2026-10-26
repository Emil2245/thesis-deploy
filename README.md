# thesis-deploy

Repositorio de despliegue cloud-native (GitOps) de la plataforma de propuestas
técnico-económicas. Fija las versiones exactas de la app como **submódulos git** y
describe el despliegue con **Kustomize**; **Argo CD** sincroniza el clúster desde este repo.

```
apps/backend, apps/frontend   submódulos (thesis-back-quarkus, thesis-front-react)
clusters/local/               configuración k3d
clusters/aws-floci/           VM aws-lab-1 (Docker + Floci, AWS emulado) y su cloud-init (plan 035)
k8s/argocd/                   values de Argo CD y app-of-apps (root-local/lab/prod)
k8s/platform/                 add-ons por directorio: CloudNativePG, cert-manager+issuers, kube-prometheus-stack, loki, tempo, alloy, dashboards, sealed-secrets
k8s/apps/                     Applications de la app por entorno
k8s/propuestas/{base,overlays/{local,lab,prod,aws}}   manifiestos Kustomize
infra/hetzner/                OpenTofu: Hetzner + k3s (plan 010)
infra/aws-floci/              OpenTofu: EKS + RDS + ECR + S3 + Secrets Manager + ALB sobre AWS emulado (plan 035)
scripts/                      install-tools, prod-up/down, cluster-local-up/down, build-local-images, bootstrap, validate, bump-submodules, seal-jwt, lab/ (tunnel-url), aws-floci/ (up, kubeconfig, copy-images, sync-secrets, hpa-test, restore-test, screenshots)
.github/workflows/            validate.yml (PR/push), release.yml (build+push GHCR+bump GitOps)
docs/                         decisiones.md, runbook.md
```

## Requisitos
podman rootless (con `podman.socket`), `gh`, y la delegación de cgroups `cpuset`
(ver [docs/decisiones.md](docs/decisiones.md)). Las CLIs se instalan con `scripts/install-tools.sh`.

## Levantar local en 3 comandos
```bash
scripts/cluster-local-up.sh
scripts/build-local-images.sh      # BACKEND_DIR / FRONTEND_DIR para apuntar a otros worktrees
scripts/bootstrap.sh local
```
App en http://propuestas.127.0.0.1.sslip.io:8080

## Producción (Hetzner + k3s con OpenTofu)
```bash
export HCLOUD_TOKEN=... TF_VAR_admin_cidrs='["<tu-ip>/32"]'
scripts/prod-up.sh      # crea red, firewall, 2 VMs, k3s y Argo CD
scripts/prod-down.sh    # destruye todo
```
Detalles, costos y state: [infra/hetzner/README.md](infra/hetzner/README.md).

## Nube emulada (AWS con Floci, plan 035)
Sustituto ejecutable de producción: OpenTofu crea EKS, RDS (PostgreSQL 18), ECR, S3, Secrets Manager, KMS, ALB, ACM y Route 53
en un emulador AWS (Floci) que corre en la VM `aws-lab-1` del laboratorio. App en `http://<IP de aws-lab-1>:8080` (ALB emulado).
`scripts/aws-floci/up.sh` · detalles: [clusters/aws-floci/README.md](clusters/aws-floci/README.md), runbook y
[docs/evidencias/aws-floci-2026-10.md](docs/evidencias/aws-floci-2026-10.md).

## Releases
Los submódulos fijan la versión de la app. **Cómo hacer un release:**
`scripts/bump-submodules.sh` (avanza `apps/*` a `main`, pide confirmación, commitea; `-y` no interactivo) y `git push`.
`release.yml` construye cada imagen desde el SHA del submódulo, la escanea (Trivy), la publica en GHCR como
`propuestas-{api,web}:<sha7>` y el bot commitea los tags en `k8s/propuestas/overlays/prod` (`[skip ci]`); Argo CD sincroniza.
Validar manifiestos: `scripts/validate.sh`.

Decisiones y pilares: [docs/decisiones.md](docs/decisiones.md). Operación: [docs/runbook.md](docs/runbook.md).
