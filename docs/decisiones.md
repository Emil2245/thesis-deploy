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
- Plan 009, charts de plataforma (Application por directorio, `values.yaml` junto a cada una, multi-source `$values` de Argo CD):

  | Chart | Repo | Versión | Namespace | Wave |
  |---|---|---|---|---|
  | `cert-manager` | https://charts.jetstack.io | `v1.21.3` | cert-manager | -10 |
  | `sealed-secrets` | https://bitnami.github.io/sealed-secrets (el antiguo `bitnami-labs.github.io` da 404) | `2.20.0` (controller 0.40.0) | kube-system | -10 |
  | `kube-prometheus-stack` | https://prometheus-community.github.io/helm-charts | `92.11.0` | monitoring | -5 |
  | `loki` (SingleBinary, filesystem, sin gateway: `svc/loki:3100`) | https://grafana.github.io/helm-charts | `7.5.0` | monitoring | -4 |
  | `tempo` (single binary; **chart marcado deprecated** upstream, se mantiene por el plan; migrar a `tempo-distributed`/Alloy en el futuro) | https://grafana.github.io/helm-charts | `1.24.4` | monitoring | -4 |
  | `alloy` (DaemonSet, Service `alloy` :4317/:4318) | https://grafana.github.io/helm-charts | `1.14.3` | monitoring | -3 |

  Issuers (`k8s/platform/issuers/manifests`, wave -5) y dashboard (`k8s/platform/dashboards/manifests`, wave -4) son Applications de ruta git. En prod, `kube-prometheus-stack` suma `values-prod.yaml` mediante un parche en `k8s/platform/prod/kustomization.yaml`. `kubeseal` v0.41.1 se instala con `scripts/install-tools.sh`.

  | Pilar | Evidencia (cluster vivo) |
  |---|---|
  | TLS | `kubectl -n propuestas get certificate` -> `propuestas-tls READY True` |
  | Métricas | Prometheus `up{namespace="propuestas"}` = 1; dashboard `Propuestas - Resumen` en Grafana |
  | Logs | Loki `{namespace="propuestas",container="api"}` devuelve líneas |
  | Trazas | Tempo `/api/search?tags=service.name%3Dpropuestas-api`; mismo `traceId` en Loki con `\|=` |
  | Secretos | `kubectl -n scratch get secret propuestas-jwt` tras aplicar un SealedSecret |

  Estado: manifiestos validados offline (`scripts/validate.sh`, `helm template`); verificación en cluster pendiente.
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

## IaC: OpenTofu (plan 010)

OpenTofu en vez de Terraform (licencia BSL), Pulumi (requiere lenguaje general + backend propio) o Ansible
(imperativo, sin state ni plan/diff): es el fork open-source bajo la Linux Foundation, compatible con HCL y
con el provider `hcloud`. k3s se instala por cloud-init (sin Ansible). Versiones: OpenTofu 1.13.2, provider
hcloud ~> 1.70, tflint 0.65.0, k3s `v1.37.1+k3s1` (igual al local). Defaults de región/tipos y costos en
[infra/hetzner/README.md](../infra/hetzner/README.md).

Nota: `scripts/seal-jwt.sh` aún no existe (plan 009), por lo que `prod-up.sh` trata ese paso como condicional.
El paso 5 del plan (apply) no se ejecutó: sin `HCLOUD_TOKEN`.

## Entorno `lab` (plan 017)
Clúster de pruebas de 3 nodos k3s en VMs Hyper-V; overlay `lab` = `local` + CNPG 2 instancias, imágenes GHCR (tags copiados de prod con `scripts/lab/sync-tags.sh`), hosts `*.192.168.1.9.sslip.io`, emisor `local-ca`.

## Resiliencia (plan 020)
`preStop: sleep 10` (+ `terminationGracePeriodSeconds` 40 api / 30 web, cumpliendo sleep < grace - apagado de Quarkus 20 s) elimina los 502 del rolling update (0 fallos en 2 corridas). `tolerationSeconds: 30` para `not-ready`/`unreachable` acelera la reprogramacion (46 s tras NotReady) a costa de mas churn ante cortes breves de red. Operador CNPG con 2 replicas (leader election) y anti-affinity por nodo: el failover del primario ocurre 20 s tras NotReady aunque caiga su nodo. Evidencia en `docs/evidencias/README.md` (seccion v2). `JWT_ISSUER=https://propuestas-api.local` en base y overlays.
