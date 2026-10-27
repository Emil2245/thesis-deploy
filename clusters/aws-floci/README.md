# aws-floci: AWS emulado en una VM del laboratorio (plan 035)

VM `aws-lab-1` (Ubuntu 24.04, 4 vCPU / 12 GB, Hyper-V, red `LAN`) con Docker Engine (repo apt oficial) y **Floci 2.3.0** (`compose.yaml`),
un emulador de AWS (puerto 4566) que levanta EKS (k3s real), RDS (PostgreSQL real), ECR (registro real) y emula S3, Secrets Manager, KMS, IAM, ALB, ACM, Route 53 y CloudWatch.

| VM | Rol | vCPU / RAM | IP (DHCP) |
|----|-----|-----------|-----------|
| aws-lab-1 | Docker + Floci | 4 / 12 GB | 192.168.1.13 |

**Recomendado:** reserva DHCP en el router para esa IP (el endpoint de Floci, el kubeconfig y el CORS del overlay `aws` la usan).

- Seed cloud-init: `scripts/lab/render-seeds.sh floci aws-lab-1` (plantilla `cloud-init/user-data.tmpl` + `compose.yaml`; no necesita token k3s).
- Compose: imagen fijada `floci/floci:2.3.0`, socket de Docker, persistencia en `/opt/floci/data`, `postgres:18.6-alpine` para RDS, TLS habilitado (HTTP y HTTPS conviven en 4566; necesario para Fluent Bit y para la mutación de pod identity), puertos 4566, 7001-7099 (proxy RDS) y 8080-8089 (listeners ALB).
- Infraestructura: `infra/aws-floci/` (OpenTofu). Kubernetes: `k8s/propuestas/overlays/aws`. Scripts: `scripts/aws-floci/`.
- Host del laboratorio: nunca reiniciar el PC; no tocar `k3s-lab-*`. Evidencia completa: `docs/evidencias/aws-floci-2026-10.md`. Operación: sección "Entorno aws-floci" del runbook.
