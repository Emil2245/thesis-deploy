# Floci local con microservicios (Core + Documentos + web) — 2026-11-13

Despliegue del entorno AWS emulado (`infra/aws-floci`, overlay `aws`) con la
versión de microservicios, ejecutando Floci **en el portátil de desarrollo**
(modo local, sin VM `aws-lab-1` ni SSH). Registro de tareas:
[`odd/tasks/floci-microservicios.md`](../../odd/tasks/floci-microservicios.md).

## Entorno
- Floci `2.4.0` en Docker (Fedora 44); EKS emulado = 1 nodo k3s `v1.37.0+k3s1`
  (`NODE_COUNT=1`; ~2 CPU asignables).
- Rama GitOps `feat/floci-microservicios` (Argo CD la lee desde GitHub).
- Imágenes construidas en local y copiadas a ECR emulado con `skopeo`:
  `propuestas-api:12deae1`, `propuestas-documentos:12deae1`
  (`thesis-back-quarkus` `feat/core-documentos-internal-http`),
  `propuestas-web:58ac778` (`thesis-front-react` `feat/microservices-stage05`).
- Comando: `scripts/aws-floci/local-up.sh --revision feat/floci-microservicios`.

## Resultados
**`local-up.sh`** (tercera ejecución): fases 1–8 completas; Applications
`Synced/Healthy` a los 575 s. Incidencias resueltas por el camino:
1. Nombre de contenedor `floci` ocupado por un Floci viejo detenido (etapa 01):
   renombrado a `floci-anterior-20261106`, no borrado.
2. `aws_db_instance.main` → `DBInstanceAlreadyExists`: la instancia sí se creó
   (`available`); el proveedor reintentó la creación. Resuelto con
   `tofu import aws_db_instance.main propuestas-db`.
3. `docker push` a `000000000000.dkr.ecr.us-east-1.localhost:4566` falló por
   TLS: el certificado de Floci cubre `*.localhost`, no el host anidado. Se
   cambió a `skopeo copy docker-daemon: … --dest-tls-verify=false` (commit
   `fix(aws-floci): push local images to ECR with skopeo…`); sin sudo ni
   `daemon.json`.

**Smoke** (`scripts/aws-floci/smoke.sh`): **17/17 OK**, incluidos los 4
ExternalSecrets (2 nuevos de la clave de servicio), respaldo a S3 por pod
identity, métricas, trazas y CloudWatch Logs. Novedad de 2.4.0: el listener
`:8443` **termina TLS** con el certificado ACM (verificado con la CA); en
2.3.0 respondía HTTP plano. El smoke acepta ambos comportamientos.

**E2E de exportación** (`scripts/aws-floci/e2e-export.sh`): cuenta desechable
(verificada por SQL en el RDS emulado, porque en `prod` el correo no registra
el token), proyecto con insumo con precio, APU, especificación técnica,
capítulo, rubro y cronograma programado; `validacion.exportable=true`.

| Documento | POST | Descarga ticket | Bytes | Tipo | Reuso ticket |
|---|---|---|---|---|---|
| presupuesto xlsx | 200 | 200 | 4291 | Excel 2007+ | 404 |
| presupuesto pdf | 200 | 200 | 27951 | PDF 2.0 | 404 |
| apus xlsx | 200 | 200 | 4639 | Excel 2007+ | 404 |
| apus pdf | 200 | 200 | 29383 | PDF 2.0 | 404 |
| especificaciones-tecnicas docx | 200 | 200 | 2535 | Word 2007+ | 404 |
| cronograma xlsx | 200 | 200 | 4293 | Excel 2007+ | 404 |
| cronograma pdf | 200 | 200 | 18023 | PDF 2.0 | 404 |
| cronograma mspdi | 200 | 200 | 5485 | XML | 404 |

- `Content-Type`/`Content-Disposition` correctos; tamaño = `sizeBytes`; 0
  cabeceras `s3`/`amz` en la descarga.
- Idempotencia: misma clave + mismo cuerpo → 200 dos veces, misma operación y
  mismo sha256, un solo objeto; misma clave + otro cuerpo → 409.
- Objetos en `propuestas-documentos`; ninguno en `propuestas-backups`.
- Pods separados: `propuestas-api-*` y `propuestas-documentos-*` con IP propia;
  Core ya no renderiza, así que los archivos sólo pueden venir de Documentos.

## Límites (no se infieren de esta prueba)
- **S3 sin autenticación en Floci:** `GET http://127.0.0.1:4566/propuestas-documentos/`
  anónimo devuelve 200 y lista objetos. Floci no aplica IAM por defecto (ver
  plan 01: hacen falta `FLOCI_SERVICES_S3_ENFORCE_AUTH` +
  `FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED`); el bloqueo de acceso público y
  las políticas mínimas por servicio quedan **declarados, no comprobados**.
  El puerto 4566 se publica en todas las interfaces del equipo.
- Core → Documentos va por **HTTP** dentro del clúster
  (`DOCUMENTOS_ALLOWED_HTTP_HOSTS=propuestas-documentos`), protegido por
  NetworkPolicy y JWT de servicio; sin TLS interno (decisión de alcance).
  Pods → S3 por `http://floci:4566`.
- Un solo nodo: durante el E2E el HPA de Core subió a 5 réplicas y 2 quedaron
  `Pending` por CPU insuficiente (sin errores en peticiones); vuelve a 2 tras la
  ventana de estabilización.
- Sin limpieza física a las 24 h (CronJob de limpieza fuera de alcance).
- Documentos no registra líneas por petición; la prueba de la ruta
  Core → Documentos es funcional, no por logs.
- EKS/IAM/KMS emulados; no equivale a AWS real.
