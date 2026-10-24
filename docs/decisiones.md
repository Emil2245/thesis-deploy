# Decisiones cloud-native

| Pilar cloud-native | Herramienta | Dónde |
|---|---|---|
| Contenedores | OCI images (multi-stage), registro GHCR | `apps/*/Dockerfile`, CI plan 011 |
| Orquestación | Kubernetes **k3s** (CNCF-certified); local **k3d** | `clusters/`, `infra/` |
| Escalamiento horizontal | Deployment ≥2 réplicas + **HPA** autoscaling/v2 (CPU) + metrics-server (k3s) + PDB | `k8s/propuestas/base/*-hpa.yaml` |
| Entrega continua / GitOps | **Argo CD** app-of-apps, sync automático + self-heal | `k8s/argocd/` |
| Gestión de manifiestos | **Kustomize** (app) + **Helm** (terceros vía Argo CD) | `k8s/` |
| Base de datos | **CloudNativePG** (operador CNCF), PostgreSQL 18 | `db-cluster.yaml` |
| Ingress / TLS | **Traefik** (k3s) + **cert-manager** + Let's Encrypt, dominio **sslip.io** | plan 009 |
| Observabilidad: métricas | Micrometer → **Prometheus** (kube-prometheus-stack) → **Grafana** | plan 009 |
| Observabilidad: logs | JSON stdout → **Grafana Alloy** → **Loki** | plan 009 |
| Trazabilidad distribuida | **OpenTelemetry** (Quarkus) → Alloy (OTLP) → **Tempo**; traceId en logs | plan 009 |
| Resiliencia | probes live/ready/started, rolling update maxUnavailable 0, PDB, graceful shutdown, CNPG failover (prod 2 instancias) | base manifests |
| Configuración | env vars (12-factor III), ConfigMap | base manifests |
| Secretos | Secret K8s; en git solo **Sealed Secrets** (prod) | plan 009 |
| Seguridad | no-root, readOnlyRootFilesystem, drop ALL caps, seccomp RuntimeDefault, NetworkPolicies, Trivy | base + plan 011 |
| IaC | **OpenTofu** + provider hcloud + cloud-init (k3s) | plan 010 |
| CI | GitHub Actions (por repo + repo deploy) | plans 006/007/011 |

## Notas de implementación

- Versiones fijadas: k3s `v1.37.1-k3s1`, Argo CD chart `10.11.1`, chart `cloudnative-pg` `0.29.1`, PostgreSQL `ghcr.io/cloudnative-pg/postgresql:18.6`.
- Argo CD / Kustomize: una `kustomization.yaml` solo puede referenciar archivos dentro de su directorio, por eso cada Application vive en su propio directorio (`k8s/platform/cnpg-operator/`, `k8s/apps/propuestas-<env>/`).

## Runtime local: k3d (primario) y requisito de podman rootless

El runtime local primario es **k3d** sobre podman rootless. En Fedora, `user@.service`
solo delega `cpu io memory pids`; k3s (y kind) exigen además `cpuset`. Sin ello:
k3s falla con `failed to find cpuset cgroup (v2)` y kind con
`running kind with rootless provider requires setting systemd property "Delegate=yes"`
(`KubeletInUserNamespace=true` no lo evita). Solución (una vez, requiere sudo):

```
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload
```

Luego cerrar sesión y volver a entrar (o reiniciar) y ejecutar `scripts/cluster-local-up.sh`.
Verificación: `cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers` debe incluir `cpuset`.
