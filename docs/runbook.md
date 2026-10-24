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
