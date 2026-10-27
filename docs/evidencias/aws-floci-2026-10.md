# Evidencia: despliegue en AWS emulado (Floci), plan 035

Fecha: 2026-10-26. Entorno: VM `aws-lab-1` (192.168.1.12; 4 vCPU / 12 GB; Ubuntu 24.04; Docker 29.9.2) con `floci/floci:2.3.0`.
Región `us-east-1`, cuenta `000000000000`. Las credenciales de Floci (`test/test`) no son secretos; las claves del operador, la contraseña de RDS,
el par JWT y la contraseña demo no se imprimen ni se versionan (el estado de tofu es local y está en `.gitignore`).

## Versiones (consultadas en vivo el 2026-10-26)
OpenTofu 1.13.2 · `hashicorp/aws` 6.70.0 (`~> 6.70`) · `random` 3.9.1 · `tls` 4.4.2 · Floci 2.3.0 · Docker CE 29.9.2 (repo apt oficial) · Fluent Bit 5.1.5 ·
k6 2.3.0 · `postgres:18.6-alpine` (Floci acepta `engine_version` 18.4 en su catálogo; el contenedor real es 18.6) · `amazon/aws-cli:2.38.5` · Argo CD chart 10.11.1 (igual que `bootstrap.sh`) · k3s 1.37.0 (EKS 1.37).

## Paso 1: VM
Verificación de deriva: `thesis-deploy` main `efb5920`; RAM libre del host 24.8 GB (>= 20). Seed: `scripts/lab/render-seeds.sh floci aws-lab-1` (grep de "thesis|tesis" sobre el directorio y el ISO: 0 coincidencias), copia con `scp` a `C:\lab\seeds\` y `new-vm.ps1 -Name aws-lab-1 -Cpu 4 -MemGB 12` vía `winps.sh`.
Hyper-V no informa la IP del invitado (sin `hv_kvp` hasta terminar cloud-init); se halló por escaneo del puerto 22 de la LAN.

`Get-VM` antes (solo `k3s-lab-*`):
```
k3s-lab-1 Running 12884901888 1.23:39:41      k3s-lab-2 Running 10737418240 1.21:12:02      k3s-lab-3 Running 10737418240 1.21:23:19
```
`Get-VM` después (las 3 VMs existentes sin reinicio: el uptime sigue creciendo; RAM libre del host 13.2 GB):
```
aws-lab-1 Running 12884901888 13:05:51    k3s-lab-1 Running 12884901888 2.12:45:47    k3s-lab-2 Running 10737418240 2.10:18:07    k3s-lab-3 Running 10737418240 2.10:29:24
```
`curl http://192.168.1.12:4566/_floci/health` -> `{"version":"2.3.0","services":{... "rds":"running" ...}}`. CPU: Floci y todas las imágenes arrancan en el Xeon E5-1620 v2 (sin x86-64-v3).

## (a) tofu apply e idempotencia
`tofu apply`: 28 recursos en 2 min 12 s (EKS, RDS 1 min 44 s); luego se añadieron ALB/ACM/Route 53 (10), usuario IAM de cargas y addon `eks-pod-identity-agent`. Segundo `tofu plan -detailed-exitcode` (tras todos los cambios): `No changes. Your infrastructure matches the configuration.` (exit 0).
Salidas (sin secretos):
```
alb_dns_name = "propuestas-7aded4c73f1c4e26.elb.localhost.floci.io"   alb_listener_port = 8080
eks_cluster_name = "propuestas"   eks_cluster_endpoint = "https://localhost:6500"   (se reescribe a https://<ip>:6500)
rds_endpoint = "floci:7001"   backups_bucket = "propuestas-backups"   kms_key_alias = "alias/propuestas"   log_group = "/propuestas/api"
ecr_repository_urls = 000000000000.dkr.ecr.us-east-1.localhost:4566/propuestas-{api,web}
secret_arns = propuestas/db-DCD9VW, propuestas/jwt-RIMZ9K   workload_role_arn = arn:aws:iam::000000000000:role/propuestas-workload
```
Incidencias resueltas: `aws_lb_target_group` pasó de `instance` a `ip` (ver desviaciones) y obligó a reemplazar listener/regla (`-replace`).

## Imágenes (GHCR -> ECR, sin reconstruir; `skopeo copy --all`, digest del índice idéntico)
```
propuestas-api:02f8774  ghcr sha256:a54fe37d66a4689a927b9a048a7ec86baea8e1aa75ae84d54b385a877ddfc2f0  ecr sha256:a54fe37d66a4689a927b9a048a7ec86baea8e1aa75ae84d54b385a877ddfc2f0
propuestas-web:7fdbaf0  ghcr sha256:5c42383ed2cbd48c7c3845ee313cd40aa8c4b042a6e9915a14325f9bd179df3f  ecr sha256:5c42383ed2cbd48c7c3845ee313cd40aa8c4b042a6e9915a14325f9bd179df3f
```

## (b) Kubernetes en el EKS emulado
Kubeconfig `~/.kube/propuestas-aws.yaml` (`scripts/aws-floci/kubeconfig.sh`). Floci rechaza `test/test` en la autenticación EKS (daría cluster-admin): se crea el usuario IAM `propuestas-operator` con clave propia en `~/.config/propuestas-aws/credentials` (0600, fuera de git); el certificado del API server cubre `127.0.0.1`, no la IP de la VM, por eso `tls-server-name: 127.0.0.1` (CA verificada).
```
NAME                               STATUS   ROLES           VERSION        INTERNAL-IP
i-4e55973e304034aba.ec2.internal   Ready    control-plane   v1.37.0+k3s1   172.17.0.3
argocd  (5 pods) Running · kube-system coredns, metrics-server Running · logging fluent-bit Running
propuestas  propuestas-api x2 Running · propuestas-web x2 Running · backup jobs Completed
```
Argo CD (chart 10.11.1) + `k8s/argocd/root-aws.yaml`: Applications `propuestas` (overlay `aws`) y `fluent-bit` Synced/Healthy.
Flyway sobre RDS (api): `Successfully validated 22 migrations`, PostgreSQL 18.6, `flyway_schema_history`: máx. versión 22, 22 filas correctas (consulta con psql).

## (c) Smoke vía ALB (`http://192.168.1.12:8080`)
```
/ -> 200    /api/v1/config/display -> 200    /privacidad -> 200
POST /api/v1/auth/login (john@uce.edu.ec, contraseña leída de 04-SEED-ESCENARIOS.md a variable) -> 200 (token de 596 caracteres, no impreso)
GET /api/v1/proyectos?page=0&size=25 (Bearer) -> 200
OPTIONS /api/v1/auth/login con Origin = ALB -> access-control-allow-origin: http://192.168.1.12:8080
```
Repetido tras activar TLS en Floci: mismos resultados.

## (d) HPA con k6 2.3.0 a través del ALB (`scripts/aws-floci/hpa-test.sh`, perfil `tests/load/hpa-scaling.js`: 20 -> 50 VU en 9 min)
Resultado: 38 492 iteraciones, 0.00 % de peticiones fallidas, 100 % de checks, p95 74.79 ms, máx. 10.91 s (arranque de pods nuevos). Línea de tiempo completa en `aws-floci/hpa/timeline.csv` (cada 10 s):
```
06:26:15Z  cpu 0 %    deseadas 2  listas 2     inicio de k6 06:26:14Z
06:28:08Z  cpu 192 %  deseadas 6  listas 2     scale-out
06:28:55Z  cpu 138 %  deseadas 6  listas 4
06:29:06Z  cpu 144 %  deseadas 6  listas 5     (pico; la 6.ª réplica no llegó a programarse: un solo nodo de 4 vCPU)
06:35:27Z  fin de k6
06:36:21Z  cpu 0 %    deseadas 4  listas 4     scale-in (ventana de estabilización 120 s)
06:37:01Z  deseadas 3 · 06:37:15Z deseadas 2 listas 2   (de vuelta a minReplicas)
```
Una primera corrida fue invalidada y descartada: reiniciar Floci (para activar TLS) recreó el contenedor k3s en mitad de la prueba. Una salida de k6 imprimió el token de `setup()`; se eliminó de `k6-output.txt` antes de versionar y el script ya no usa `--summary-export /dev/stdout`.

## (e) Respaldo a S3 y restauración
CronJob `propuestas-backup` (diario 03:17; `pg_dump -Fc` desde RDS con `postgres:18.6-alpine` y subida con `amazon/aws-cli:2.38.5`), ejecutado a mano dos veces:
```
$ aws s3 ls s3://propuestas-backups/db/
2026-10-26 01:11:20     228663 propuestas-20261026T061049Z.dump
2026-10-26 13:58:04     228846 propuestas-20261026T185801Z.dump
```
Restauración de prueba (`scripts/aws-floci/restore-test.sh`): `create database restore_test` en la misma instancia RDS, `pg_restore`, conteo y `drop database`:
```
rubros restaurados: 310     rubros en vivo: 310     (restore_test eliminada)
```
Credenciales de las cargas: Secret `aws-workload-credentials` (clave del usuario IAM `propuestas-workload`, misma política que el rol `propuestas-workload`). Pod identity: con TLS activo y el addon `eks-pod-identity-agent` Floci muta los pods (`AWS_CONTAINER_CREDENTIALS_FULL_URI` inyectada), pero el relay `169.254.170.23` no arranca porque la imagen k3s no trae gestor de paquetes (`Could not install Pod Identity relay dependencies ... No supported package manager`): las credenciales no se entregan, por eso se usa el Secret.

## (f) Logs en CloudWatch
Fluent Bit 5.1.5 (DaemonSet en `logging`, `cloudwatch_logs`, endpoint `172.18.0.2:4566`): el plugin solo habla TLS (la propiedad `tls` no es válida en este plugin) y el certificado de Floci no cubre la IP, por lo que se desactivó la verificación TLS (propiedad `tls.verify`) y Floci tiene `FLOCI_TLS_ENABLED=true` (HTTP y HTTPS conviven en 4566).
```
$ aws logs describe-log-streams --log-group-name /propuestas/api   -> flujos pod-kube.var.log.containers.propuestas-api-...  (>= 4)
$ aws logs filter-log-events --log-group-name /propuestas/api --filter-pattern Flyway
  {"time":"2026-10-26T06:28:38Z","stream":"stdout", ... "log":"{\"timestamp\":...Flyway..."}
```

## (g) Costo
Cost Explorer de Floci (`ce get-cost-and-usage`, 2026-10, agrupado por servicio): **USD 71.42** total, solo `AmazonEC2` (744 h x USD 0.096 de `m5.large`, el nodo EKS sintetizado); el snapshot de precios de Floci solo cubre EC2, S3 y Lambda, así que EKS, RDS, ALB y demás figuran en 0.
**Estimación manual** (no es una factura): precios de lista de AWS, región us-east-1, descargados el 2026-10-26 de `pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<servicio>/current/` (versiones de oferta de 2026-09 a 2026-10), 730 h/mes:

| Concepto | Precio de lista | USD/mes |
|---|---|---|
| EKS plano de control | 0.10/h | 73.00 |
| Nodo (1 x m5.large, precio del snapshot de Floci) | 0.096/h | 70.08 |
| RDS PostgreSQL db.t3.small Single-AZ | 0.036/h | 26.28 |
| RDS almacenamiento 20 GB gp3 (0.115/GB-mes, valor no re-consultado en la lista) | | 2.30 |
| ALB | 0.0225/h | 16.43 |
| ALB LCU (supuesto: 1 LCU promedio) | 0.008/LCU-h | 5.84 |
| S3 Standard (1 GB) | 0.023/GB | 0.02 |
| Secrets Manager (2 secretos) | 0.40/secreto | 0.80 |
| KMS (1 clave) | 1.00/clave | 1.00 |
| Route 53 (1 zona) | 0.50/zona | 0.50 |
| CloudWatch Logs (1 GB ingerido, supuesto) | 0.50/GB | 0.50 |
| ECR (1 GB, supuesto) | 0.10/GB-mes | 0.10 |
| **Total estimado** | | **~196.85** |

El nodo real equivalente a los 4 vCPU / 12 GB de la VM sería m5.xlarge (aprox. el doble de la fila de nodo). ACM público y IAM no cuestan.

## (h) Capturas (`docs/evidencias/aws-floci/*.png`, `scripts/aws-floci/screenshots.mjs`, Playwright)
`01-consola-inicio`, `02-eks` (clúster `propuestas` ACTIVE 1.37), `03-rds` (`propuestas-db` postgres 18.4 db.t3.small), `04-s3`, `05-secrets-manager` (solo nombres `propuestas/db`, `propuestas/jwt`), `06-elb`, `07-cloudwatch-logs`, `08-app-via-alb` (login de la app por el ALB). La consola web (puerto 4500, sidecar de Floci) no tiene vista de ECR: el contenido de ECR se evidencia con `describe-images` arriba.

## Omitido o limitado
- ESO / Secrets Store CSI: no probados; se usa `sync-secrets.sh` (el endpoint personalizado de Floci hace impracticable el operador).
- Pod identity: solo plano de gestión (ver (e)).
- Un solo nodo EKS; réplica 6 del HPA sin programar.
- Argo CD: instalado sin problemas de memoria; no hizo falta `kubectl apply -k`.

## Desviaciones del plan
1. Targets del ALB de tipo `ip` (IP del nodo) en lugar de `instance`: Floci no resuelve el id de instancia de los nodos EKS (`Refusing to proxy to target i-...`). En AWS real sería `instance`.
2. Sin Ingress/Traefik (el nodo k3s de Floci no los trae): el ALB reparte por regla de ruta `/api/*` a NodePorts 30081 (api) y 30080 (web).
3. `engine_version` 18.4 (catálogo de Floci: 18.1, 18.4) con imagen real 18.6.
4. Floci con TLS y `FLOCI_HOSTNAME=floci` (necesarios para Fluent Bit y la mutación de pod identity).
5. Credenciales de cargas por Secret/usuario IAM en lugar de pod identity operativo.
6. aws CLI v1 (pip) en el portátil; v2 no se distribuye por pip.
