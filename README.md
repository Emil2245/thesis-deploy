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
scripts/                      vps/ (up, down, smoke, restore-drill, hpa-test, screenshots, lab-vm), install-tools, prod-up/down, cluster-local-up/down, build-local-images, bootstrap, validate, bump-submodules, seal-jwt, lab/ (tunnel-url), aws-floci/ (up, down, root, lab-vm, smoke, kubeconfig, add-workers, cluster-prep, copy-images, restore-drill, hpa-test, ca, sync-secrets, screenshots)
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

## Etapa 03: integración local Core + Documentos + frontend

Si `k3d` no está instalado, esta ruta usa Docker Compose sin modificar el clúster,
los submódulos fijados ni el Floci existente. Desde este repositorio, con Docker,
AWS CLI, OpenSSL y los repositorios hermanos en sus ramas de etapa 03:

```bash
scripts/stage03-local-up.sh
# Aplicación: http://127.0.0.1:8080/
LOCAL_STAGE03_GID="$(id -g)" docker compose -f compose.stage03-local.yaml ps
```

`BACKEND_DIR` y `FRONTEND_DIR` pueden apuntar a otros worktrees. El script genera
**dos** pares RSA locales en `.local-stage03/` (ignorados por Git), construye
imágenes desde los worktrees, inicia PostgreSQL aislado y una instancia Floci
2.4.0 aislada en `127.0.0.1:14569`, y crea su bucket de prueba con credenciales
ficticias y endpoint explícito. Además inicia Mailpit en `127.0.0.1:18025`
para verificar cuentas de prueba sin enviar correos reales; sus mensajes incluyen
enlaces de activación, por lo que no deben compartirse. No ejecuta comandos de borrado. Al terminar,
`LOCAL_STAGE03_GID="$(id -g)" docker compose -f compose.stage03-local.yaml stop`
detiene solo los contenedores de esta composición sin borrar sus datos.

Core (8082), Documentos (8081) y nginx (8080) escuchan solo en loopback con
red del host para que Core utilice su excepción HTTP *únicamente* en loopback;
nginx enruta `/api/` a Core sin registrar URL de tickets. Documentos no se
expone al navegador. **Esta alternativa es solo local:** no prueba Kubernetes,
TLS interno, permisos IAM diferenciados, AWS real, borrado físico a las 24 h ni
la suite completa de Core (GM_19 y GM_20 siguen diferidos). No sustituye los
manifiestos GitOps existentes ni configura el trabajador periódico de limpieza.

La [verificación local de cronograma de la etapa 04](docs/evidencias/stage04-cronograma-local-2026-11.md)
comprueba POST, render remoto, tres formatos, ticket de un uso, GET heredado y
la descarga de XLSX, PDF A3 y MSPDI XML en el navegador integrado de Orca.
La suite E2E de Playwright no se ejecutó: falta su ejecutable Chromium.

La [verificación local de la etapa 05](docs/evidencias/stage05-retiro-descargas-local-2026-11.md)
comprueba que los GET de bytes antiguos devuelven 404 y que POST + ticket
funciona para presupuesto, APUs y cronograma en sus siete formatos.

## Producción (Hetzner + k3s con OpenTofu)
```bash
export HCLOUD_TOKEN=... TF_VAR_admin_cidrs='["<tu-ip>/32"]'
scripts/prod-up.sh      # crea red, firewall, 2 VMs, k3s y Argo CD
scripts/prod-down.sh    # destruye todo
```
Detalles, costos y state: [infra/hetzner/README.md](infra/hetzner/README.md).

## Nube emulada (AWS con Floci, plan 035)
Sustituto ejecutable de producción: OpenTofu crea EKS, RDS (PostgreSQL 18), ECR, S3, Secrets Manager, KMS, ALB, ACM y Route 53
en un emulador AWS (Floci) que corre en la VM `aws-lab-1` del laboratorio. App en `http://<IP de aws-lab-1>:8080` (ALB emulado; HTTPS 8443 declarado, ver límites en la evidencia v2). Manual de despliegue verificado: `manual-despliegue-floci/` (repo de documentación).
`scripts/aws-floci/up.sh` · detalles: [clusters/aws-floci/README.md](clusters/aws-floci/README.md), runbook y
[docs/evidencias/aws-floci-2026-10.md](docs/evidencias/aws-floci-2026-10.md) (v1) y [aws-floci-2026-10-v2.md](docs/evidencias/aws-floci-2026-10-v2.md) (plan 040, sin brechas) y [verificacion-manuales-2026-10.md](docs/evidencias/verificacion-manuales-2026-10.md) (verificación en frío de los manuales, plan 042).

## Despliegue en un VPS genérico (plan 041)
Una máquina Ubuntu 24.04 con IP pública y SSH (4 vCPU / 8 GB): `scripts/vps/up.sh <ip> --domain <dominio> --issuer <letsencrypt-prod|letsencrypt-staging|selfsigned-ca> [--email <correo>] [--agent <ip2>]`
instala k3s, Argo CD y toda la plataforma (TLS, PostgreSQL con respaldos a S3, observabilidad, HPA). `scripts/vps/down.sh <ip> --yes` lo desmonta.
Manual verificado: `manual-despliegue-vps/` (repo de documentación). Detalles: [docs/evidencias/vps-2026-10.md](docs/evidencias/vps-2026-10.md), [verificación en frío del manual](docs/evidencias/verificacion-manuales-2026-10.md), runbook y decisiones.

## Releases
Los submódulos fijan la versión de la app. **Cómo hacer un release:**
`scripts/bump-submodules.sh` (avanza `apps/*` a `main`, pide confirmación, commitea; `-y` no interactivo) y `git push`.
`release.yml` construye cada imagen desde el SHA del submódulo, la escanea (Trivy), la publica en GHCR como
`propuestas-{api,web}:<sha7>` y el bot commitea los tags en `k8s/propuestas/overlays/prod` (`[skip ci]`); Argo CD sincroniza.
Validar manifiestos: `scripts/validate.sh`.

Decisiones y pilares: [docs/decisiones.md](docs/decisiones.md). Operación: [docs/runbook.md](docs/runbook.md).
