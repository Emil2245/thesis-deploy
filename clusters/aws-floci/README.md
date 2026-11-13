# aws-floci: AWS emulado en una VM del laboratorio (plan 035)

VM `aws-lab-1` (Ubuntu 24.04, 4 vCPU / 12 GB, Hyper-V, red `LAN`) con Docker Engine (repo apt oficial) y **Floci 2.3.0** (`compose.yaml`),
un emulador de AWS (puerto 4566) que levanta EKS (k3s real), RDS (PostgreSQL real), ECR (registro real) y emula S3, Secrets Manager, KMS, IAM, ALB, ACM, Route 53 y CloudWatch.

| VM | Rol | vCPU / RAM | IP (DHCP) |
|----|-----|-----------|-----------|
| aws-lab-1 | Docker + Floci | 4 / 12 GB | la que asigne el DHCP (`scripts/aws-floci/lab-vm.sh ip`) |

**Recomendado:** reserva DHCP en el router para esa IP (el endpoint de Floci y el kubeconfig la usan; el CORS del overlay `aws` ya no depende de ella: `up.sh` lo parametriza).

- Crear/destruir la VM en el laboratorio: `scripts/aws-floci/lab-vm.sh create|destroy|ip`.
- Seed cloud-init: `scripts/lab/render-seeds.sh floci aws-lab-1` (plantilla `cloud-init/user-data.tmpl` + `compose.yaml`; no necesita token k3s).
- Compose: imagen fijada `floci/floci:2.4.0` (la ejecución integral histórica v1/v2 usó 2.3.0), socket de Docker, persistencia en `${FLOCI_DATA_DIR:-/opt/floci/data}`, `postgres:18.6-alpine` para RDS, TLS habilitado (HTTP y HTTPS conviven en 4566; el certificado cubre el nombre `floci`), puertos 4566, 7001-7099 (proxy RDS), 8080-8089 y 8443-8449 (listeners ALB).
- Infraestructura: `infra/aws-floci/` (OpenTofu). Kubernetes: `k8s/propuestas/overlays/aws`. Scripts: `scripts/aws-floci/`.
- Host del laboratorio: nunca reiniciar el PC; no tocar `k3s-lab-*`. Evidencia completa: `docs/evidencias/aws-floci-2026-10.md` (v1) y `docs/evidencias/aws-floci-2026-10-v2.md` (plan 040). Operación: sección "Entorno aws-floci" del runbook.

**Plan 040:** el entorno se levanta con `scripts/aws-floci/up.sh` (ver runbook y `manual-despliegue-floci/`); 2 nodos (servidor Floci + agente k3s), Pod Identity con relay propio, ESO, Traefik, Prometheus/Tempo, TLS verificado hacia Floci.

**Modo local con microservicios (2026-11):** Floci 2.4.0 en este mismo equipo, sin VM ni SSH, con Core, Documentos y web:
`scripts/aws-floci/local-up.sh --revision <rama>` construye las 3 imágenes desde `BACKEND_DIR`/`FRONTEND_DIR`, las copia a ECR con skopeo y ejecuta `up.sh` con `NODE_COUNT=1`;
`scripts/aws-floci/e2e-export.sh` prueba la exportación POST + ticket de los 8 documentos. Requiere `tofu`, `helm`, `kubectl`, `aws`, `jq`, `skopeo` y `docker`, y los puertos 4566, 7001-7099, 8080-8089 y 8443-8449 libres.
Evidencia y límites (S3 de Floci sin autenticación, HTTP interno Core → Documentos, un nodo): [`docs/evidencias/floci-local-microservicios-2026-11.md`](../../docs/evidencias/floci-local-microservicios-2026-11.md).
