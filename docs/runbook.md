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

## Observabilidad, TLS y secretos (plan 009)

- **Grafana**: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` (o https://grafana.127.0.0.1.sslip.io:8443, cert de `local-ca`: usar `-k`). Usuario `admin`; contraseña (solo en terminal, no guardar):
  `kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo`
- **Prometheus**: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090` y `up{namespace="propuestas"}`.
- **Loki**: `kubectl -n monitoring port-forward svc/loki 3100`; `curl -G -s localhost:3100/loki/api/v1/query_range --data-urlencode 'query={namespace="propuestas",container="api"}'`. Buscar por traza: `{namespace="propuestas"} |= "<traceId>"` (traceId no es label).
- **Tempo**: `kubectl -n monitoring port-forward svc/tempo 3200`; `curl -s 'localhost:3200/api/search?tags=service.name%3Dpropuestas-api&limit=5'`. En Grafana, Explore > Tempo, o salto desde un log (campo derivado `traceId`).
- **Certificados**: `kubectl get certificate -A`; `kubectl describe certificate -n propuestas propuestas-tls`. Si Let's Encrypt limita, cambiar el issuer del Ingress prod a `letsencrypt-staging`. El email ACME es placeholder (`ACME_EMAIL_CHANGE_ME@example.invalid`): reemplazar en `k8s/platform/issuers/manifests/issuers.yaml` antes del deploy prod.
- **Rotar la llave JWT**: `scripts/install-tools.sh` (kubeseal), contexto kubectl del cluster destino, `scripts/seal-jwt.sh prod`, commit del `sealed-jwt.yaml` generado (solo cifrado), descomentarlo en `k8s/propuestas/overlays/prod/kustomization.yaml`, push y `kubectl -n propuestas rollout restart deploy/propuestas-api`.

## Entorno `lab` (k3s en Hyper-V)

Ver `clusters/lab/README.md`. Bootstrap: `KUBECONFIG=~/.kube/propuestas-lab.yaml scripts/bootstrap.sh lab`.
Actualizar tags: `scripts/lab/sync-tags.sh`. Prueba de fallo de nodo: `Stop-VM k3s-lab-3 -TurnOff` vía `scripts/lab/winps.sh`.
Nota: un arranque en frío del PC bloquea VT-x; reiniciar en caliente desde macOS (Boot Camp).
