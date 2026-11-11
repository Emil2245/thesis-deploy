# Etapa 04 — verificación local de cronograma (11 de noviembre de 2026)

**Resultado:** Core → Documentos → FLoCI → ticket de Core funciona por HTTP para XLSX, PDF y MSPDI XML. La descarga real desde Chromium **no está verificada**: el ejecutable requerido por Playwright no está instalado. Esta evidencia no cierra el criterio de navegador de la etapa 04.

## Entorno y caso aislado

Se ejecutó `scripts/stage03-local-up.sh` desde `thesis-deploy` con los worktrees de etapa 04. Construyó las tres imágenes locales y dejó listos Core (`127.0.0.1:8082`; health de administración `:9000`), Documentos (`:8081`), nginx/frontend (`:8080`), PostgreSQL aislado (`:55432`), Mailpit (`:18025`) y FLoCI 2.4.0 con namespace y bucket **`propuestas-stage03-local`** (`:14569`). Los cuatro endpoints de health consultados devolvieron 200. No se tocó la instancia FLoCI preexistente ni `propuestas-backups`; no se borró ningún volumen.

Se registró y verificó por Mailpit una cuenta descartable en esa base local; el proyecto creó su presupuesto inicial. Mediante API pública del mismo propietario se creó un cronograma de cuatro períodos, un capítulo y un insumo MATERIAL de 10.000000, y un APU manual asociado al capítulo. No se utilizó SQL directo para crear el caso. Antes del APU, el preflight devolvió `exportable:false` y bloqueos `cronograma-total-cero`/`cronograma-borrador`; el POST y el GET heredado devolvieron 409 `export-bloqueado` sin ticket. Tras el APU, los tres preflight devolvieron `exportable:true`, cero bloqueos y una advertencia de cronograma desactualizado.

## Comprobaciones observadas

| Formato | Preflight | POST JSON | Ticket (primer/segundo GET) | GET de bytes heredado | Bytes del ticket |
| --- | --- | --- | --- | --- | ---: |
| XLSX | 200 | 200 | 200 / 404 | 200 | 4281 |
| PDF A4 | 200 | 200 | 200 / 404 | 200 | 18160 |
| MSPDI XML | 200 | 200 | 200 / 404 | 200 | 5541 |

Cada POST devolvió una ruta **relativa de Core**, no una URL S3; el nombre terminó en `.xlsx`, `.pdf` o `.xml` según el formato. Las advertencias coincidieron con el preflight; tamaño, SHA-256 y MIME coincidieron con la descarga. Se validó la firma ZIP del XLSX, la cabecera PDF y el parseo XML con raíz `Project` del MSPDI. El GET anterior conservó la entrega de bytes para cada formato. Estas pruebas atravesaron nginx, Core, Documentos y la instancia FLoCI aislada, pero no verifican un navegador.

El frontend pasó 781 pruebas en 104 archivos, typecheck, lint, formato y build tras el ajuste de origen **solo para Vitest**. Una comparación diferencial de presupuesto/APU frente al commit base, con la nueva opción `papel` y MIME XML de un formato hermano, mantuvo código de salida, stdout de aplicación y stderr iguales. No se instaló ni cambió Node.

## Incidentes y límites

- Un primer intento de proyecto envió `plazoUnidad:MESES`; el contrato acepta `MES` y esa entrada produjo 500. Se corrigió el **dato del caso** sin modificar el servicio; la cuenta de ese intento quedó en la base descartable. Antes de crear el cronograma, el preflight devolvió 404 `Cronograma no encontrado` como correspondía a su ausencia.
- Dos intentos iniciales del script de comprobación asumieron erróneamente `advertencias` en JSON; la clave pública es `warnings`. Ambos POST alcanzaron Documentos, pero esos scripts se detuvieron antes de consumir el ticket. La comprobación corregida pasó para los tres formatos. No se atribuyen a producto esos fallos del script de prueba.
- La prueba Chromium no llegó a abrir el navegador: Playwright informó que falta `chromium_headless_shell-1248/.../chrome-headless-shell`; **no se descargó ni se intentó otro verificador**. Por ello quedan pendientes el clic, el aviso y las descargas observadas en un navegador real (incluido PDF A3 desde UI).
- No se probó pérdida de instancia, múltiples réplicas, limpieza física a las 24 horas, límites de tiempo/conexiones ni recuperación independiente del renderer después de PUT incierto. No se ejecutó la suite completa de Core: GM_19/GM_20 siguen diferidos. `scripts/check-document-contract.sh` no está aprobado. No se regeneró el PDF del manual.
- Una instancia local de FLoCI no prueba IAM, TLS, Ingress, retención desplegada ni AWS real. La aprobación del flujo de navegador y las garantías de producción requieren evidencia separada.
