# Runbook (día 2)

```bash
export PATH=$HOME/.local/bin:$PATH
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock   # solo local
```

- **Estado**: `kubectl -n argocd get applications`; `kubectl -n propuestas get pods,hpa -o wide`
- **Argo CD UI**: `kubectl -n argocd port-forward svc/argocd-server 8081:80` y abrir http://localhost:8081 (usuario `admin`).
  Contraseña inicial (solo mostrar en terminal, no guardar en archivos):
  `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`
- **Logs**: `kubectl -n propuestas logs deploy/propuestas-api --tail=100 -f`
- **Rollback**: `git revert <commit>` en este repo y push; Argo CD sincroniza solo.
- **Nueva versión de la app**: `git submodule update --remote apps/backend apps/frontend`, commit y push.
- **BD**: `kubectl -n propuestas exec -it propuestas-db-1 -- psql -U postgres propuestas` (o plugin `kubectl cnpg psql propuestas-db`).
- **Reconstruir imágenes locales**: `scripts/build-local-images.sh` y `kubectl -n propuestas rollout restart deploy`.
- **Destruir local**: `scripts/cluster-local-down.sh`.

## CI/CD (plan 011)

**Qué hace fallar el build**
- `validate.yml` / `manifests`: manifiestos que no pasan kubeconform (`scripts/validate.sh`).
- `validate.yml` / `k8s-security`: Trivy config con hallazgos HIGH/CRITICAL en `k8s/` (local: `podman run --rm -v $PWD:/w:Z docker.io/aquasec/trivy:latest config --severity HIGH,CRITICAL /w/k8s`).
- `validate.yml` / `iac`: `tofu validate`, `fmt -check` o tflint en `infra/hetzner` .
- `release.yml`: Trivy image con CRITICAL que tenga fix disponible (`ignore-unfixed`) en `propuestas-api`/`propuestas-web`.

**Release:** `scripts/bump-submodules.sh` + push a `main`. El job `bump` commitea `chore(release): api <sha> web <sha> [skip ci]`.

**Paquetes GHCR públicos (una vez, tras la primera release):**
`gh api -X PATCH /user/packages/container/propuestas-api -f visibility=public` (y `propuestas-web`).
Si la API lo rechaza: GitHub → Packages → paquete → Package settings → Change visibility → Public.

## Producción (OpenTofu, plan 010)
- **Crear**: `export HCLOUD_TOKEN=... TF_VAR_admin_cidrs='["<ip>/32"]'; scripts/prod-up.sh` (kubeconfig en `~/.kube/propuestas-prod.yaml`, fuera del repo).
- **Destruir**: `scripts/prod-down.sh` (pide confirmación).
- **State**: local en `infra/hetzner/terraform.tfstate` (git-ignorado, contiene el token k3s). Perderlo = recursos huérfanos en Hetzner.
- **Escalar**: subir `agent_count` y `tofu apply`; los agents se unen solos.
- **Costo**: ver [infra/hetzner/README.md](../infra/hetzner/README.md) (estimado, verificar en consola).
- **LOPDP**: la región `ash` (EE.UU.) es transferencia internacional de datos; declararla o usar `nbg1`.
