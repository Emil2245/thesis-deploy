# Etapa 05 — retiro de descargas legadas, verificación local (11 de noviembre de 2026)

**Resultado local:** con el código de las ramas `feat/microservices-stage05`, los GET de bytes antiguos ya no existen (404) y la única descarga, POST → Documentos → FLoCI → ticket de Core, funciona para siete combinaciones de documento y formato. Es evidencia **local** con FLoCI 2.4.0; no es prueba de AWS ni de producción.

## Entorno

- `scripts/stage03-local-up.sh` reconstruyó `core`, `documentos` y `web` desde `thesis-back-quarkus` y `thesis-front-react` en `feat/microservices-stage05` (backend en `062cc86` + registros posteriores). Pila aislada `propuestas-stage03-local`, bucket `propuestas-stage03-local`, FLoCI en `127.0.0.1:14569`. No se tocó el contenedor `floci` preexistente ni `propuestas-backups`.
- Datos: una cuenta desechable nueva (proyecto vacío) y la cuenta desechable de la etapa 04 en esta misma base local, cuyo acceso se recuperó con `/auth/recuperar` + `/auth/restablecer` vía Mailpit local. La contraseña nueva solo existió en memoria del script.

## Resultados

| Comprobación | Resultado |
|---|---|
| `GET /documentos/{presupuesto,apus,cronograma,especificaciones-tecnicas}/{id}` | 404 los cuatro (ambas cuentas) |
| Preflight presupuesto / apus | 200 |
| Preflight cronograma sin cronograma | 404 de negocio (esperado) |
| POST sobre presupuesto vacío | 409 `presupuesto-vacio`; con rubro de PU cero, 409 `presupuesto-pu-cero` + `presupuesto-sin-actividad`; sin ticket |
| POST presupuesto XLSX / PDF | 200 → ticket 200, MIME XLSX / `application/pdf`, firma `PK\x03\x04` / `%PDF`, reuso 404 |
| POST APUs XLSX / PDF | 200 → ticket 200, mismos MIME y firmas, reuso 404 |
| POST cronograma XLSX / PDF A3 / MSPDI | 200 → ticket 200, MIME XLSX / PDF / `application/xml` (`<?xm`), reuso 404 |
| POST especificaciones-tecnicas DOCX | 400 `validacion`: el presupuesto de prueba no tiene APUs con ET. El camino DOCX queda cubierto por pruebas automáticas (Core `ExportPostFlowIT`, Documentos `InternalExportResourceTest`), no por esta prueba en vivo. |

Pruebas automáticas de la misma rama: Core 932 pruebas = 928 en verde + GM-19/GM-20 (residuales aceptados del Plan 014) + 2 omitidas (GM-24, `PrivateObjectDeleterFlociIT` sin FLoCI de prueba); Documentos 118, 0 fallos, 1 omitida (`S3PrivateObjectStoreFlociIT`); frontend 102 archivos / 763 pruebas; `build -x test` y `check-document-contract.sh` en verde.

## No verificado

- La prueba de carga k6 (`tests/load/common.js`, ya migrada a POST + ticket) no se ejecutó: k6 no está instalado.
- Las colecciones Bruno modificadas no se ejecutaron.
- Playwright E2E, navegador, varias réplicas, borrado a las 24 h, IAM/TLS/Ingress desplegados: igual que en la etapa 04, sin evidencia.
