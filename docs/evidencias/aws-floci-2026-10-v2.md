# Evidencia: Floci sin brechas y desplegable desde cero (plan 040)

Fecha: 2026-10-26/27. Continúa [`aws-floci-2026-10.md`](aws-floci-2026-10.md) (v1, sin modificar salvo una frase que mencionaba la verificación TLS desactivada, para cumplir `git grep 'verify Off'` vacío).
Entorno: VM `aws-lab-1` **recreada desde la imagen base** (192.168.1.13; 4 vCPU / 12 GB; Ubuntu 24.04), Floci 2.3.0 (última estable el 2026-10-27; `gh release list`). Las credenciales de Floci (`test/test`) no son secretos; las claves del operador, la contraseña de RDS, el par JWT y la contraseña demo no se imprimen ni se versionan.

## Versiones (consultadas en vivo)
Floci 2.3.0 · OpenTofu 1.13.2 · `hashicorp/aws` 6.70.0 · AWS CLI 2.38.6 (v2, instalador oficial) · k3s 1.37.0 · Argo CD chart 10.11.1 · External Secrets chart 2.14.0 · Traefik chart 42.1.3 (ingress-nginx está retirado) · kube-prometheus-stack 92.14.0 · Tempo chart 1.24.4 · Fluent Bit 5.1.5 · `alpine/socat` 1.8.1.3 · k6 2.3.0 · `postgres:18.6-alpine` · `amazon/aws-cli:2.38.5`.

## Ejecución desde cero
| Paso | Resultado |
|---|---|
| Host antes/después | `Get-VM`: solo `aws-lab-1` se borró y recreó; `k3s-lab-1/2/3` Running sin reinicio (uptime creciente). RAM libre del host 12.9 GB antes del borrado (con la VM vieja) |
| VM + cloud-init + Floci | 06:01:25Z -> 06:11:48Z (~10 min 20 s): `cloud-init status: done`, `floci/floci:2.3.0`, `/_floci/health` -> `2.3.0` |
| `scripts/aws-floci/up.sh` | **811 s (13 min 31 s)**, 06:12:34Z -> 06:26:05Z, un solo comando, salida 0 (las 9 fases + smoke). Fases: tofu 130 s · kubeconfig 5 s · nodos 11 s · imágenes 52 s · CoreDNS+CA 34 s · Argo CD 88 s · espera de las 9 Applications 430 s |
| `tofu apply` | 56 recursos añadidos; segundo `tofu plan -detailed-exitcode`: `No changes.` (exit 0) |
| Primer intento | `up.sh` falló en el plan con `Invalid for_each argument` (IP de nodos desconocidas); corregido (`count`) y repetido desde el mismo estado limpio: ver «Desviaciones» |

## Cierre de brechas
| # | Estado | Evidencia |
|---|---|---|
| G1 | **Fallback parcial** | `aws_eks_node_group.workers` (desired 2) creado, pero Floci 2.3.0 materializa **un solo** contenedor k3s por clúster: `kubectl get nodes` sigue con 1 nodo (docs de Floci, «Single shared node mapping»; el EC2 `RunInstances` + user data solo registra un objeto Node sin kubelet). Fallback: `scripts/aws-floci/add-workers.sh` une un agente k3s real (`rancher/k3s:v1.37.0-k3s1`, IP fija 172.18.0.201 en `floci_default` y también en `bridge`). `kubectl get nodes`: 2 Ready. HPA llegó a **6 réplicas Ready, 3 por nodo** (ver abajo) |
| G2 | **Cerrada (opción a, relay propio)** | Pod Identity operativa: el relay de Floci falla con `Could not install Pod Identity relay dependencies ... No supported package manager found for IMDS proxy dependencies` (imagen k3s sin gestor de paquetes). DaemonSet `pod-identity-relay` (`alpine/socat` 1.8.1.3, hostNetwork, `169.254.170.23/32` en `lo`, TLS verificado hacia `floci:4566`). Probado con aws-cli: `sts get-caller-identity` -> `assumed-role/propuestas-workload/eks-propuestas-propuestas-workload-...` y `s3 ls`; ESO, Fluent Bit y el CronJob de respaldo la usan. `kubectl get secret -A \| grep -ci aws` -> `0`; el usuario IAM `propuestas-workload` y el Secret `aws-workload-credentials` ya no existen |
| G3 | **Cerrada** | ESO chart 2.14.0 por Argo CD; `ClusterSecretStore aws-secrets-manager` `Valid`/`READY True`; `ExternalSecret propuestas-db-app` y `propuestas-jwt` `SecretSynced`; endpoint `AWS_ENDPOINT_URL_SECRETS_MANAGER`/`_STS=https://floci:4566` y `AWS_CA_BUNDLE`; `sync-secrets.sh` solo break-glass. Incidente: el store quedó `InvalidProviderConfig` (`failed to load credentials ... invalid character '<'`) mientras el Service de Traefik era `LoadBalancer` (el servicelb de k3s capturaba `169.254.170.23:80`); con `NodePort` pasó a `Valid` |
| G4 | **Cerrada** | `tls.verify On`, `tls.ca_file /floci/ca.pem`, `endpoint floci` (CoreDNS `coredns-custom` -> IP del contenedor Floci; certificado de Floci con SAN `floci` por `FLOCI_HOSTNAME`); CA en ConfigMap `floci-ca` (propuestas, logging, external-secrets, pod-identity, monitoring). `aws logs filter-log-events --log-group-name /propuestas/api` -> eventos de `pod-kube.var.log.containers.propuestas-web-...`. `git grep 'verify Off'` vacío |
| G5 | **Cerrada** | Traefik chart 42.1.3 (`NodePort 30080`, 2 réplicas repartidas en los 2 nodos); un `Ingress propuestas` (web + `/api`, sin host); un solo target group `ip` de Floci con **todos los nodos** (172.18.0.5 y 172.18.0.201) en 30080. `instance` sigue siendo limitación de Floci (`Refusing to proxy to target i-...`) |
| G6 | **Fallback** | Listener HTTPS 8443 con certificado importado en ACM (CA propia generada por `tls_*`, SAN: IP de la VM, `app.propuestas.aws.internal`, `localhost`) creado y descrito (`describe-listeners`), pero **Floci 2.3.0 no termina TLS**: `curl https://192.168.1.13:8443` -> `curl: (35) TLS connect error: error:0A00010B:SSL routines::wrong version number` (el puerto responde HTTP plano, `curl http://...:8443/` -> 200). El código de terminación (`ElbV2DataPlane`, `setSsl(true)`) está en `main` de Floci y no en 2.3.0 (`git show 2.3.0:...` solo registra «ELBv2 listener port started on N»); existe imagen `floci/floci:nightly`, no estable; no encontré issue upstream. Lo que hace AWS real: certificado público de ACM validado por DNS y redirección 301 HTTP->HTTPS. Variable `alb_redirect_http` (false con 2.3.0; true cuando haya versión estable con TLS) y la app se sirve por `http://192.168.1.13:8080`; CORS admite ambos orígenes. `scripts/aws-floci/ca.sh` exporta la CA para importarla en el navegador |
| G7 | **Cerrada** | `scripts/aws-floci/restore-drill.sh`: último `.dump` de S3 -> base `restore_drill` en la misma RDS -> conteo vs vivo: rubro 310/310 · apu 311/311 · apu_detalle 2592/2592 · insumo 768/768 · actividad 310/310, todas `OK`; base temporal eliminada |
| G8 | **Cerrada** | `up.sh` (idempotente, 9 fases), `down.sh` (`--reset`), `smoke.sh`; 811 s desde la VM limpia |
| G9 | **Cerrada** | Métricas: kube-prometheus-stack ligero (sin Grafana/Alertmanager/node-exporter) en vez de CloudWatch (coherente con los otros entornos; no depende de `PutMetricData`): `sum(up{namespace="propuestas"})` = 4 y `http_server_requests_seconds_count` = 8 tras tráfico. Trazas: la API exporta OTLP a `tempo.monitoring.svc:4317`; `/api/search` -> 5 trazas, p. ej. `rootServiceName=propuestas-api`. Tempo sin PVC (Floci desactiva el StorageClass local) |

Salida del smoke final (`smoke.sh`, dentro de `up.sh`):
```
OK listener :8443 (HTTPS declarado, ACM) responde HTTP plano: limitación documentada de Floci 2.3.0
OK GET / -> 200 · GET /api/v1/config/display -> 200 · GET /privacidad -> 200 (http://192.168.1.13:8080)
OK login (token 596 caracteres, no impreso) · GET /api/v1/proyectos -> 200
OK 2 nodos Ready · Ingress propuestas con clase traefik · ExternalSecret x2 Ready
OK ningún Secret aws-* en el clúster · sin verificación TLS desactivada en el repo
OK respaldo con pod identity subido a S3 (job smoke-backup-...)
OK métrica Prometheus · métrica de la app · traza en Tempo (5) · CloudWatch Logs (5 eventos)
```
Aplicaciones de Argo CD (9) `Synced`/`Healthy`: eso-config, external-secrets, fluent-bit, kube-prometheus-stack, pod-identity-relay, propuestas, root, tempo, traefik. RAM de la VM en reposo: 4.6 GB usados de 12.

## HPA con k6 2.3.0 a través del ALB (2 nodos), `hpa/` en `aws-floci-v2/`
`scripts/aws-floci/hpa-test.sh` (perfil 20 -> 50 VU en 9 min, 06:43:27Z -> 06:52:28Z): 38 005 iteraciones, **0.18 % de peticiones fallidas** (< 1 %), 99.82 % de checks, p95 65.7 ms, máx. 6.6 s (arranque de pods).
```
06:43:29Z cpu 1 %    deseadas 2 listas 2   (1 api en cada nodo)
06:48:14Z cpu 72 %   deseadas 3 listas 2
06:49:13Z cpu 148 %  deseadas 6 listas 3
06:49:49Z cpu 115 %  deseadas 6 listas 6   <- 6.ª réplica programada (en v1 quedaba sin programar)
pods-por-nodo.log 06:49:39Z: i-4e55...=3  worker-1=3
06:53:47Z deseadas 4 · 06:53:59Z 3 · 06:54:11Z 2 listas 2   (scale-in a minReplicas)
```

## Costo
Misma arquitectura que v1 más un segundo nodo: la estimación manual de v1 (USD ~196.85/mes, precios de lista us-east-1) pasa a **~266.93/mes** al añadir un `m5.large` (0.096/h x 730 h = 70.08). Es una estimación, no una factura; el Cost Explorer de Floci solo cubre EC2, S3 y Lambda.

## Capturas
`01-consola-inicio` … `08-app-via-alb` (`scripts/aws-floci/screenshots.mjs`, Playwright; la consola de Floci arranca perezosamente al visitar `http://<ip>:4566/_floci/ui`; solo nombres, sin valores secretos).

## Desviaciones del plan
1. G1 y G6 son *fallbacks* (ver tabla); el resto cerrado.
2. Orden de HPA/nodos: el nodo adicional es un agente k3s propio, no un `aws_eks_node_group` materializado.
3. El primer `up.sh` falló en el plan (`for_each` con valores desconocidos); se corrigió en el repositorio y se repitió. La cifra de 811 s es de la ejecución completa que pasó.
4. La IP de la VM recreada cambió (192.168.1.12 -> .13) y se actualizó el overlay (`CORS_ORIGINS`) con un commit.
5. Se retocó una frase de la evidencia v1 (`verify Off`) para cumplir el criterio `git grep 'verify Off'` vacío.
6. Pod Identity con relay propio en lugar del de Floci; HTTPS del ALB sin terminación TLS en Floci 2.3.0 (reportado).
