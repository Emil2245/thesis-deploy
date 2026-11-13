# Floci local con microservicios (Core + Documentos + web)

## Objetivo
Desplegar la versión de microservicios (etapa 05) en el entorno AWS emulado
(`infra/aws-floci`, overlay `aws`, `scripts/aws-floci/`) ejecutando Floci en
este portátil, con el mínimo necesario para que el sistema funcione de punta a
punta (login, edición, exportación POST + ticket, descarga).

## Problema / por qué
El entorno Floci documentado despliega el monolito (`propuestas-api:02f8774`).
No existen Documentos, su bucket privado, su ECR, su identidad ni la clave JWT
de servicio. Core rechaza `http://` a hosts no loopback, así que con pods
separados no puede llamar a Documentos.

## Decisiones (usuario, 2026-11-12)
- Floci **local** en el portátil; no se toca `aws-lab-1` ni `k3s-lab-*`.
- **Pods separados** (Deployments/Services propios) + flag de configuración en
  Core que permite `http` solo a hosts internos listados explícitamente.
  Sin TLS interno (declarado como límite); NetworkPolicy restringe el acceso.
- Argo CD lee la rama `feat/floci-microservicios` **subida a GitHub**
  (rama feature; sin PR ni merge a `main`).
- **Alcance mínimo**: solo overlay `aws`; sin cambios en overlays
  local/lab/prod/vps, sin `release.yml`, sin tesis/manual, sin CronJob de
  limpieza (opcional), sin nodos agentes extra (`NODE_COUNT=1`).
- Herramientas faltantes (`tofu`, `helm`) las instala el usuario.

## Restricciones
- No editar migraciones, `motor/`, `recalculo/`.
- No secretos en git; la clave de servicio la genera OpenTofu y llega por
  Secrets Manager + ESO.
- Floci 2.4.0 para el entorno local (S3 condicional `If-None-Match` verificado
  en etapa 03 con 2.4.0; EKS con 2.4.0 no verificado — riesgo abierto).
- TDD estricto (fuente: `~/.claude/CLAUDE.md`), runner
  `./gradlew :core:test --tests '<clase>'` para el cambio Java. Infra: checks
  funcionales (`tofu validate`, `kubectl kustomize`, smoke).
- RDD: **off** (global) → entrega `disabled/unmanaged`.

## Tareas
- [x] **T1 (backend, delegado: writer 2 archivos)** — propiedad
  `documentos.allowed-http-hosts` (lista, vacía por defecto) en Core;
  `DocumentosExportClient` acepta `http` solo si el host está en la lista o es
  loopback. RED → GREEN en `DocumentosExportClientTest`. Commit en
  `thesis-back-quarkus` rama `feat/core-documentos-internal-http`.
- [x] **T2 (deploy, delegado)** — OpenTofu `infra/aws-floci`: ECR
  `propuestas-documentos`; bucket privado `propuestas-documentos`; roles pod
  identity `documentos` (Put/Get/Head) y `api` (Get); clave RSA de servicio +
  secreto `propuestas/documentos-service-jwt`; permiso ESO y outputs.
  Check: `tofu fmt -check`, `tofu validate`.
- [x] **T3 (deploy, delegado)** — overlay `aws`: Deployment/Service/
  ServiceAccount/NetworkPolicy de Documentos; ExternalSecrets (pública →
  Documentos, privada → Core); parches a Core (`serviceAccountName`,
  `DOCUMENTOS_BASE_URL`, clave de servicio, `CORE_STORAGE_BUCKET`,
  `QUARKUS_S3_*`, `DOCUMENTOS_ALLOWED_HTTP_HOSTS`). Check:
  `kubectl kustomize k8s/propuestas/overlays/aws` y de los demás overlays sin
  cambios.
- [x] **T4 (deploy, delegado)** — modo local de scripts: `compose.yaml` con
  directorio de datos local y Floci 2.4.0; `lib.sh` sin SSH cuando
  `FLOCI_IP` es local; construir imágenes desde los worktrees y `docker push` a
  ECR emulado (en vez de skopeo desde GHCR); `up.sh` espera rollout de
  Documentos. Check: `bash -n`, `shellcheck` si existe.
- [x] **T5 (ejecución)** — push de la rama; `up.sh` local; smoke existente +
  prueba E2E (registro/login, POST exportación, ticket 200, reuso 404, objeto en
  bucket `propuestas-documentos`). Registrar evidencia en
  `docs/evidencias/floci-local-microservicios-2026-11.md`.
- [x] **T6 (docs mínimos)** — sección corta en `clusters/aws-floci/README.md`
  (modo local + Documentos). Tesis/manual quedan fuera de alcance.

## Criterios de aceptación
- `up.sh` local termina sin errores; Argo CD `Synced/Healthy`.
- 3 Deployments (`propuestas-api`, `propuestas-documentos`,
  `propuestas-web`) listos.
- Exportación desde la web/API: POST 200, descarga por ticket 200, segundo uso
  404, objeto presente en el bucket de documentos (no en backups).

## Entrega
Forecast ≈ 350–450 líneas. Estrategia `ask-on-risk`. Push solo de las ramas
feature autorizadas; PR/merge quedan a decisión del usuario.

## Progreso / evidencia
- **T1** (ruta: delegated; trigger: writer 2 archivos) — `thesis-back-quarkus` commit `12deae1` (rama `feat/core-documentos-internal-http`). RED: `acceptsHttpOnlyForExplicitlyListedInternalHosts` falló con stub (1/9); GREEN: `DocumentosExportClientTest` 9/9; `documento.exportacion.*` 70 = 69 pass + 1 skipped (`PrivateObjectDeleterFlociIT`, condicional preexistente); spotlessCheck y `:core:build -x test` PASS.
- **T2** (ruta: delegated; trigger: writer 2 archivos + mapeo >4) — commit `7b9747d`.
  `infra/aws-floci/main.tf`, `outputs.tf`: ECR `propuestas-documentos`, bucket
  privado SSE-KMS + public access block, roles pod identity `api` (SA
  `propuestas-api`, GetObject + kms:Decrypt) y `documentos` (SA
  `propuestas-documentos`, Put/GetObject + ListBucket para 404 + KMS), clave
  RSA `tls_private_key.documentos_service_jwt` → secreto
  `propuestas/documentos-service-jwt`, ARN en la política ESO y outputs.
  Checks: `tofu` no instalado → sustituido por Terraform 1.17.2:
  `terraform fmt -check -recursive infra/aws-floci` → 0;
  `terraform init -backend=false && terraform validate` sobre una copia en
  scratch (el lock es de registry.opentofu.org) → `Success! The configuration
  is valid.` `tofu validate` real: **pendiente** (usuario instala tofu).
- **T3** (ruta: delegated) — commit `65d8c82`. `overlays/aws/documentos.yaml`
  (SA ×2, Deployment 1 réplica restricted + `/tmp` emptyDir, Service 8081,
  NetworkPolicy solo desde `propuestas-api`), `overlays/aws/kustomization.yaml`
  (imagen ECR `propuestas-documentos:dec7a4b` placeholder, ConfigMap Core
  `DOCUMENTOS_*`/`CORE_STORAGE_BUCKET`/`QUARKUS_S3_*` con
  `http://floci:4566`, SA `propuestas-api`, montaje de la privada),
  `eso-config/store.yaml` (ExternalSecrets `-private` y `-public`).
  Checks: `kubectl kustomize k8s/propuestas/overlays/aws` → 3 Deployments;
  overlays local/lab/prod/vps renderizan; `eso-config` (4 ExternalSecret),
  `k8s/platform/aws-floci`, `k8s/apps/propuestas-aws` renderizan.
  `scripts/validate.sh` → **omitido** (exit 127: falta `kubeconform`).
- **T4** (ruta: delegated) — commit `a6bbd2e`. `compose.yaml` (Floci 2.4.0,
  `${FLOCI_DATA_DIR:-/opt/floci/data}`), `lib.sh` (`FLOCI_LOCAL`, `SSH=ssh_local`),
  nuevo `local-up.sh`, `copy-images.sh` (`IMAGES_SOURCE=local`: docker push,
  3.ª imagen), `up.sh` (tags del entorno, NODE_COUNT=1 sin add-workers, rollout
  documentos), `root.sh` (`kustomize.images` en la Application `propuestas`),
  `down.sh --reset` local sin sudo, `smoke.sh` (nodos ≥ NODE_COUNT, ESO nuevos),
  `.gitignore` (`.floci-data/`).
  Checks: `bash -n` en los 15 scripts → OK; `docker compose -f
  clusters/aws-floci/compose.yaml config` → imagen 2.4.0, data dir por defecto
  y por variable; prueba de `$SSH` local (`bash -s a b` recibe args) y de la
  generación jq de parches de `root.sh` → OK. `shellcheck` **omitido** (no
  instalado). Sin ejecución real (T5).

- **T5** (ruta: inline + delegado para datos E2E; trigger: backstop de sesión larga) — rama subida a GitHub.
  `local-up.sh` 3ª ejecución: fases 1–8 OK, Applications Synced/Healthy a 575 s. Correcciones: contenedor `floci`
  viejo renombrado (no borrado); `tofu import aws_db_instance.main propuestas-db` tras `DBInstanceAlreadyExists`
  por reintento; push a ECR con skopeo (TLS de `*.localhost` no cubre el host anidado); smoke acepta TLS real
  en :8443 (Floci 2.4.0). Smoke 17/17 OK. E2E `scripts/aws-floci/e2e-export.sh`: 8/8 documentos POST 200,
  descarga 200, reuso 404, idempotencia OK (409 con otro cuerpo), objetos sólo en `propuestas-documentos`.
  Límites: S3 de Floci acepta GET anónimo (IAM no aplicado); HTTP interno; 1 nodo (HPA dejó 2 pods Pending).
  Evidencia: `docs/evidencias/floci-local-microservicios-2026-11.md`.
- **T6** (ruta: inline) — sección "Modo local con microservicios" en `clusters/aws-floci/README.md`.

## Siguiente paso
Feature cerrada en local. Pendiente decisión del usuario: push de la rama backend
`feat/core-documentos-internal-http` (commit `12deae1`), PR/merge de ambas ramas, y si se endurece S3 de Floci
(`FLOCI_SERVICES_S3_ENFORCE_AUTH` + IAM) o se documenta en la tesis. Entrega: RDD off → `disabled/unmanaged`.
