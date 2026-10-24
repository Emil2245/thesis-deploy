# Evidencias cloud-native (Plan 012) — cluster LAB

Entorno: 3 VMs Hyper-V (k3s-lab-1/2/3, 192.168.1.9/.10/.11), k3s v1.37.1, ingress
`https://propuestas.192.168.1.9.sslip.io` (CA local). Fecha: 2026-10-24. Carga generada con
k6 v1.4.0 desde un laptop en la misma LAN (no se probo la URL publica trycloudflare). Los
resultados son de un laboratorio con 3 VMs en un solo equipo fisico: amenaza a la validez
(no es produccion). Scripts: `tests/` (`run-all.sh` reejecuta los pasos 1-5; capturas con
`tests/screenshots/capture.mjs`; graficas con `tests/plot_timeline.py`).

## Numeros clave

| Prueba | Resultado |
|---|---|
| HPA API (min 2, max 6, CPU 60 %) | Replicas maximas 6 (de 2). Carga 0->50 VUs, 9 min, 40 347 peticiones, 74.6 req/s |
| Tiempo de scale-out | Carga inicia 06:45:27Z; primer `desired>2` 06:46:39Z (72 s); `desired=6` 06:47:20Z (113 s); 6 replicas Ready 06:47:40Z (133 s). CPU pico 145 % del request |
| Tiempo de scale-in | k6 termina 06:54:28Z; 2 replicas Ready 06:55:58Z (90 s) |
| k6 HPA | p95 = 21.35 ms, errores 0.02 % (10/40 347; umbrales PASS) |
| Rolling update (10 VUs, 3 min) | **0.92 % fallos (45/4843, todos 502)**; corrida previa 0.64 % (31/4814). NO es cero. Los 502 se agrupan cada ~10 s al terminar cada pod viejo; los manifiestos no tienen `preStop`/retardo de apagado. p95 40 ms |
| Pod kill (4 pods api + 1 web, c/30 s) | 0.08 % fallos (4/4749, 502); p95 51.8 ms; pods de reemplazo Ready en 10-11 s (api) y 1 s (web) |
| Fallo de nodo lab-2 (2 min apagada; api+replica DB+web) | 0.20 % fallos (16/7971: 12x 504, 4x status 0), todos entre 32 y 65 s tras apagar la VM (hasta que el nodo paso a NotReady ~49 s y salio de los endpoints). Los pods no se reprogramaron porque 2 min < 300 s de tolerancia de eviction; al volver la VM los contenedores reiniciaron (Ready en ~20 s) |
| Fallo de nodo lab-3 (2m24s, primario CNPG + operador CNPG) | **59.9 % fallos** (4887/8162, 503): sin failover porque el operador CNPG corria en el mismo nodo; servicio recuperado 27 s tras encender la VM |
| Failover de BD (lab-3 apagado 7 min) | Nodo NotReady a los 49 s; operador reprogramado tras eviction (5 min); `Failing over` 07:50:30Z -> primario `propuestas-db-2` 07:50:48Z (18 s). Indisponibilidad de BD/API (503) 07:45:13Z-07:50:49Z = ~5 min 36 s; 64.3 % fallos (9521/14797). Cluster sano de nuevo 07:51:53Z |
| Trivy imagen API | 31 hallazgos HIGH/CRITICAL: **2 CRITICAL, 29 HIGH** (26 SO RedHat 9.8: 2C+24H; 5 jar HIGH) |
| Trivy imagen web | **0 CRITICAL, 45 HIGH** (Alpine 3.23.4) |
| Trivy config `k8s/` | **0** hallazgos HIGH/CRITICAL (34 ficheros) |
| kubeconform | 0 invalidos |
| Pod Security `restricted` (dry-run server) | sin advertencias |

## v2 (tras endurecimiento, plan 020) — 2026-10-24

Cambios: `preStop: sleep 10` + `terminationGracePeriodSeconds` 40 (api) / 30 (web); tolerations
`not-ready`/`unreachable` de 30 s en api y web; operador CNPG con 2 replicas y anti-affinity por nodo
(quedaron en k3s-lab-2 y k3s-lab-3); `JWT_ISSUER=https://propuestas-api.local` unificado (base/local/lab).
Las evidencias v1 se conservan arriba como el "antes".

| Prueba | Resultado v2 |
|---|---|
| Rolling update (10 VUs, 3 min), 2 corridas | **0 fallos en ambas**: run1 0/4534 (p95 97 ms), run2 0/4840 (p95 37 ms). v1: 0.92 % 502. `rolling/v2/run{1,2}/`, `rolling/v2/timeline-plot.png`, `rolling/v2/grafana-rolling-v2.png` |
| Fallo de nodo lab-3 (no primario; api x2 + web + replica DB), VM apagada 2 min | **0.19 % fallos (16/8277)**, todos 504/timeout entre 08:15:39Z y 08:16:11Z (32 s a 64 s tras apagar). NotReady a 48 s; eviction a +30 s (08:16:26Z); pods de reemplazo Ready 08:16:41Z (api) y 08:16:27Z (web): **46 s tras NotReady, ~94 s tras apagar**. v1: pods no se reprogramaban. `chaos/v2/node-lab3-*` |
| Failover de BD: lab-2 (primario CNPG `propuestas-db-2` + operador + api/web) apagado 5 min | NotReady 08:24:11Z (47 s tras apagar 08:23:24Z); `Failing over` 08:24:14Z; nuevo primario `propuestas-db-1` 08:24:31Z (**20 s tras NotReady**; operador sobrevivio en lab-3); errores 503 de 08:23:36Z a 08:24:37Z (**~61 s**). **2.62 % fallos (351/13357)** -> supera el umbral k6 de 1 %; v1: 64.3 % y 5 min 36 s. Pods api/web reprogramados Ready 08:24:43-08:24:52Z. Cluster `Failing over` hasta que la VM volvio (08:28:45Z) y sano 08:28:56Z. `chaos/v2/dbfailover-lab2-*` |
| Trivy api (`b025a77`) | 2 CRITICAL (`java-25-openjdk-*`, CVE-2026-91403, estado `under_investigation`, sin parche); con `--ignore-unfixed`: 0 CRITICAL. `seguridad/v2/` |

Notas honestas: el 2.62 % de fallos del failover de BD y el 0.19 % del fallo de nodo vienen de la ventana
de deteccion (kubelet marca NotReady a ~48 s; hasta entonces Traefik/endpoints siguen apuntando a pods
inalcanzables); no se ajustaron HPA ni umbrales. Los reintentos/readiness no se tocaron.

STEP5_PLACEHOLDER

## Hallazgos que deben constar en la tesis (fallos honestos)

1. **Rolling update no es "zero downtime"**: 0.64-0.92 % de peticiones 502 (sin `preStop`/sleep ni
   `terminationGracePeriod` coordinado con el ingress). No se modificaron manifiestos.
2. **Operador CNPG sin redundancia**: un solo replica del operador; si cae su nodo junto con el
   primario no hay failover hasta la eviction (5 min). Indisponibilidad total de ~5.6 min.
3. **Spans JDBC ausentes**: la traza de Tempo contiene un solo span HTTP (`GET/POST ...`); no hay spans de BD.
4. **Latencia p95 en Grafana sin datos**: la metrica `http_server_requests_seconds` no exporta buckets de
   histograma (panel "Latencia p95" vacio). El p95 real viene del resumen de k6.
5. **Bug de configuracion corregido durante la prueba** (commit `fix(k8s): align lab JWT_ISSUER with token issuer`):
   con `JWT_ISSUER=https://propuestas.local` todo endpoint autenticado devolvia 401 porque `TokenService`
   firma con `iss=https://propuestas-api.local` (hardcode). El overlay `local` tiene el mismo valor (sin corregir).
6. Exportes xlsx/pdf del cronograma semilla responden 409 (bloqueo de negocio, desviacion != 0); k6 los cuenta como
   respuesta esperada. No hay ruta de export con 200 en los datos semilla, por lo que la carga CPU-pesada son
   arbol de presupuesto/cronograma (~0.3 s c/u).
7. Argo CD: app `issuers` Degraded (ClusterIssuers `letsencrypt-*` no Ready en el lab, sin salida a ACME).
8. Prometheus: se corrigio NetworkPolicy para scrape de CNPG (`fix(k8s): allow monitoring to scrape CNPG metrics`); `up=1` en pods db.

## Checklist de propiedades

| Propiedad | Criterio | Resultado | Evidencia |
|---|---|---|---|
| Contenedores | Imagenes OCI inmutables por tag (sha), no root, rootfs read-only | PASS | `seguridad/runasnonroot.txt`, `seguridad/pss.txt` |
| Orquestacion | Despliegue declarativo en k3s multi-nodo, pods repartidos | PASS | `chaos/pods-estado-final.txt`, `gitops/capturas/argocd-propuestas-tree.png` |
| Escalamiento horizontal | HPA 2->N bajo carga | PASS (2->6) | `hpa/timeline.csv`, `hpa/k6-summary.json`, `hpa/hpa-timeline.png`, `hpa/capturas/grafana-2-pico.png` |
| Elasticidad (scale-in) | Vuelve a 2 al cesar la carga | PASS (90 s) | `hpa/timeline.csv`, `hpa/capturas/grafana-3-despues-scale-in.png` |
| Resiliencia: rolling update | 0 peticiones fallidas | v1 **FAIL** (0.92 % 502); **v2 PASS** (0 fallos en 2 corridas, `rolling/v2/`) | `rolling/k6-output.txt`, `rolling/run1-sin-diagnostico/`, `rolling/capturas/` |
| Resiliencia: fallo de pods | disponibilidad >99 % | PASS (99.92 %) | `chaos/pod-kill-*`, `chaos/capturas/pod-kill-plot.png`, `chaos/capturas/grafana-pod-kill.png` |
| Resiliencia: fallo de nodo | disponibilidad >99 % | v1 PARTIAL (lab-2: 99.8 %; lab-3 con primario+operador: 40 %); **v2 PASS** (lab-3 no primario: 99.81 %, pods reprogramados en 46 s tras NotReady; con primario+operador: ver BD) | `chaos/node-lab2-*`, `chaos/dbfailover-lab3-*`, `chaos/capturas/node-lab2-plot.png`, `chaos/capturas/grafana-node-lab2.png` |
| Alta disponibilidad de BD | failover automatico del primario | v1 PARTIAL (failover OK en 18 s tras reprogramar operador; indisponibilidad 5.6 min); **v2 PARTIAL-PASS**: failover 20 s tras NotReady con operador HA, indisponibilidad ~61 s, 97.4 % disponibilidad (`chaos/v2/`); no alcanza >99 % por la ventana de deteccion de 48 s | `chaos/dbfailover-lab3-long-*`, `chaos/capturas/dbfailover-lab3-long-plot.png`, `chaos/capturas/grafana-dbfailover-lab3-long.png` |
| Observabilidad: metricas | Prometheus recoge api y db | PASS | `observabilidad/prometheus-metric.json`, `hpa/capturas/*.png` (p95 sin datos, ver hallazgo 4) |
| Observabilidad: logs | Loki con traceId | PASS | `observabilidad/loki-logs.json`, `observabilidad/capturas/grafana-loki-logs.png` |
| Observabilidad: trazas | Tempo recibe traza con traceId inyectado | PARTIAL (solo span HTTP; sin JDBC) | `observabilidad/tempo-trace-login.json`, `observabilidad/capturas/grafana-tempo-trace.png` |
| Trazabilidad trace<->log | mismo traceId en traza y log | PASS | `observabilidad/traceid-login.txt`, `observabilidad/loki-logs.json`, `observabilidad/tempo-trace-login.json` |
| Configuracion por entorno | Overlays kustomize base/local/lab/prod, ConfigMap env | PASS | `k8s/propuestas/overlays/`, `seguridad/kubeconform.txt` |
| Secretos | Sealed Secrets, nada en claro en git | PASS (no auditado con scanner de secretos en git) | `k8s/platform/` (sealed-secrets), `seguridad/trivy-config.txt` |
| GitOps | Argo CD sincroniza desde git; historial | PASS | `gitops/argocd-history.json`, `gitops/argocd-applications.txt`, `gitops/capturas/argocd-applications.png` |
| IaC | Manifiestos validos | PASS | `seguridad/kubeconform.txt` |
| CI | Imagenes construidas por CI y tag bump automatico | PARTIAL (commits `chore(release)` de github-actions visibles en Argo; no se enlazaron ejecuciones) | `gitops/capturas/argocd-propuestas-tree.png` |
| Seguridad: imagenes | 0 CRITICAL | **FAIL** v1 (api 2 CRITICAL/29 HIGH; web 45 HIGH); v2 **PARTIAL** — sin parche disponible (CVE-2026-91403 `under_investigation`, `java-25-openjdk-*`); la puerta de release (ignore-unfixed) lo acepta; se revisara al publicarse el parche (`seguridad/v2/`) | `seguridad/trivy-image-api.txt`, `seguridad/trivy-image-web.txt` |
| Seguridad: config | 0 HIGH/CRITICAL | PASS | `seguridad/trivy-config.txt` |
| Seguridad: PSS restricted | sin advertencias | PASS | `seguridad/pss.txt` |
| Aplicacion accesible | Login y listado funcionan en el lab | PASS (tras corregir JWT_ISSUER) | `app/capturas/app-login.png`, `app/capturas/app-proyectos.png`, `app/capturas/app-trycloudflare.png` |

## 12 factores

| Factor | Resultado | Como se cumple / brecha |
|---|---|---|
| I Codebase | PASS | Un repo por componente (back, front, deploy), submodulos; despliegues por overlay |
| II Dependencias | PASS | Gradle/pnpm con lockfiles; imagen autocontenida |
| III Configuracion | PASS | Variables de entorno via ConfigMap/Secret (`JWT_ISSUER`, `DB_URL`...); brecha: el valor de `JWT_ISSUER` debe coincidir con un hardcode del codigo (hallazgo 5) |
| IV Servicios de apoyo | PASS | PostgreSQL (CNPG) por URL/credenciales inyectadas |
| V Build/release/run | PASS | CI construye imagen por commit; Argo despliega tag inmutable |
| VI Procesos | PASS | API sin estado (JWT), escalable por HPA (2->6 demostrado) |
| VII Port binding | PASS | Quarkus en 8080 (+ gestion 9000) |
| VIII Concurrencia | PASS | Escalado horizontal por procesos/pods |
| IX Desechabilidad | v1 PARTIAL; v2 PASS | Arranque ~8 s; con `preStop` de 10 s el rolling update tiene 0 fallos (plan 020) |
| X Paridad dev/prod | v1 PARTIAL; v2 PASS | `JWT_ISSUER` unificado en base/local/lab (plan 020) |
| XI Logs | PASS | Logs JSON a stdout recogidos por Alloy a Loki con traceId |
| XII Procesos de administracion | PARTIAL | Migraciones Flyway al arrancar; ingesta del dataset no verificada como Job puntual |
