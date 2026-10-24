# thesis-deploy

Repositorio de despliegue cloud-native (GitOps) de la plataforma de propuestas
técnico-económicas. Fija las versiones exactas de la app como **submódulos git** y
describe el despliegue con **Kustomize**; **Argo CD** sincroniza el clúster desde este repo.

```
apps/backend, apps/frontend   submódulos (thesis-back-quarkus, thesis-front-react)
clusters/local/               configuración k3d
k8s/argocd/                   values de Argo CD y app-of-apps (root-local/prod)
k8s/platform/                 add-ons (CloudNativePG; plan 009 agrega más)
k8s/apps/                     Applications de la app por entorno
k8s/propuestas/{base,overlays/{local,prod}}   manifiestos Kustomize
scripts/                      install-tools, cluster-local-up/down, build-local-images, bootstrap, validate
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

## Releases
Los submódulos fijan la versión de la app: `git submodule update --remote` + commit = nueva release.
Validar manifiestos: `scripts/validate.sh`.

Decisiones y pilares: [docs/decisiones.md](docs/decisiones.md). Operación: [docs/runbook.md](docs/runbook.md).
