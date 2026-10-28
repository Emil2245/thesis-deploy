# Evidencia: verificación en frío de los manuales de despliegue (plan 042), 2026-10-27

Resumen de las rondas de lectura en frío de los dos manuales de despliegue (`manual-despliegue-vps/` y `manual-despliegue-floci/`, repositorio `thesis-docs`). El registro completo de cada manual está en su anexo «Registro de verificación»; esta página lo resume. Despliegue verificado: este repositorio en `6a2c836` (`main` al cierre; la verificación del VPS se hizo con `4773915`).

## Método
- **Lector en frío:** en cada ronda, un agente nuevo, sin conocimiento previo del proyecto, sigue el manual al pie de la letra sobre una VM recreada desde la imagen base (`vps-lab-1` o `aws-lab-1`), pegando cada comando tal como está impreso y sustituyendo solo los `<marcadores>`.
- **Solo el PDF:** su entrada es el PDF del manual (las fuentes `.tex` únicamente si el PDF no se puede leer) y el repositorio que el manual manda clonar.
- **Entradas prohibidas:** los planes 040/041, `docs/evidencias/` y las transcripciones de las ejecuciones previas. No corrige nada: solo informa.
- **Reglas del host:** nunca reiniciar el host, no tocar `k3s-lab-*` (plan 035).
- **Clases de desviación:** D1 un comando falla tal como está impreso; D2 la salida difiere de lo escrito; D3 falta un paso (hizo falta conocimiento que el manual no da); D4 redacción ambigua; D5 versión o nombre obsoleto.
- **Regla de recuento:** cada hallazgo cuenta una vez, bajo la **primera clase** que anotó el lector (la clase del encabezado de la entrada del registro).
- **Rondas:** completas (de cero y de principio a fin) y dirigidas (solo capítulos con desviaciones). Tras cada ronda se corrigen el manual y, si la causa está allí, los *scripts* (PR con CI verde). Criterio de cierre: 0 D1–D3 y lista de comprobación completa; D4/D5 solo si son cosméticas y se corrigen en la misma ronda.

## Manual de VPS (8 rondas)
| Ronda | Tipo | D1 | D2 | D3 | D4 | D5 | Correcciones (una línea) |
|---|---|---|---|---|---|---|---|
| 1 | completa | 0 | 3 | 3 | 2 | 0 | huella SSH, clave de demostración, `<pod-api>`, redirección 308/301, cuenta del *smoke*, `initContainer` `esperar-db` (reinicios), `jq`/`k6` en el instalador |
| 2 | completa | 2 | 2 | 0 | 2 | 0 | consultas codificadas y líneas ≤ 88 caracteres (copiado desde el PDF); instalador sin `/tmp` (tmpfs); salida de respaldo y restauración |
| 3 | completa | 0 | 2 | 0 | 2 | 0 | `Location:`, `aws s3 cp --no-progress`, un solo `up.sh`, nombre de la carpeta clonada |
| 4 | completa | 0 | 1 | 0 | 3 | 1 | `hpa-test.sh` imprime avance y código de salida; comprobación 14; factor de carga 1.0 documentado |
| 5 | dirigida | 1 | 4 | 0 | 1 | 1 | resolución de `KUBECONFIG`; `hpa-resultados/` ignorada por git; porcentaje de errores; valores transitorios |
| 6 | dirigida | 0 | 2 | 1 | 1 | 0 | registro de la carga dentro de `hpa-resultados/`; `smoke.sh` autónomo con `<ip> --domain --issuer` |
| 7 | dirigida | 0 | 3 | 1 | 3 | 0 | salidas variables con su intervalo (errores 0–15 %); `mkdir -p ~/.kube`; tipografía; recuento fijo |
| 8 | dirigida | 0 | 0 | 0 | 4 | 0 | criterio de aprobación (máx. réplicas listas > 2), trayectoria de réplicas, fila de escalamiento del registro |

Resultado final: **0 D1–D3; lista de comprobación 19/19**. Dos corridas de `up.sh` desde cero: 560 s y 572 s, sin intervención ([`vps-2026-10.md`](vps-2026-10.md)). Las rondas 1 a 4 fueron completas; las 5 a 8, dirigidas.

## Manual de Floci (5 rondas)
| Ronda | Tipo | D1 | D2 | D3 | D4 | D5 | Correcciones (una línea) |
|---|---|---|---|---|---|---|---|
| 1 | completa | 4 | 6 | 6 | 7 | 0 | `lab-vm.sh create/destroy/ip`; `kubeconfig.sh` recrea credenciales; `up.sh` idempotente (`skopeo`); cachés de OpenTofu bajo `$HOME`; `root.sh` con `CORS_ORIGINS`; salidas variables declaradas |
| 2 | completa | 0 | 1 | 1 | 1 | 0 | tamaños de volcados variables; estado esperado de las *Applications* antes de copiar imágenes; instalador de la AWS CLI con `--update`. Lista 16/16 |
| 3 | dirigida | 0 | 1 | 1 | 2 | 1 | `smoke.sh` y `ca.sh` leen `terraform.tfstate` con `jq` (sin OpenTofu ni proveedores); lista de *Applications*; entrada obsoleta del registro |
| 4 | dirigida | 0 | 2 | 1 | 1 | 1 | disco de los proveedores (~830 MB); comprobación 16 con orden completa; anexo en `longtable` (se cortaba el final) |
| 5 | dirigida | 0 | 0 | 0 | 0 | 0 | ninguna: *smoke* autónomo 17/17 `OK`, comprobación 16 «No changes» con 832 MB, capítulo 14 completo y fiel |

Resultado final: **0 D1–D3; lista de comprobación 16/16** (ronda 2; la ronda 5 repitió el *smoke* autónomo). Ejecución desde cero tras la ronda 1: `up.sh` 741 s, 17 `OK`; el despliegue de referencia del plan 040 tardó 811 s ([`aws-floci-2026-10-v2.md`](aws-floci-2026-10-v2.md)). Las rondas 1 y 2 fueron completas; las 3 a 5, dirigidas.

## Límites declarados
- **VPS:** verificado en una VM de laboratorio detrás de NAT. **Let's Encrypt no se ejercitó** (emisor `selfsigned-ca`). Tampoco `--agent` (segundo servidor), S3 externo (`--s3-endpoint`) ni la ruta OpenTofu en Hetzner (IaC no aplicada). El factor de carga 1.0 es el único fiable en la VM de pruebas (0.6 y 0.8 no escalaron de forma fiable).
- **Floci:** es un emulador: IAM y KMS no se aplican, los precios no son reales y los destinos del ALB son `ip`, no `instance`. El ALB no termina HTTPS en Floci 2.3.0, así que la aplicación se sirve por HTTP en el puerto 8080. El segundo nodo EKS es un agente k3s real unido por *script* (`add-workers.sh`), porque Floci materializa un solo nodo por clúster. No se usó AWS real.
- **Lector:** un agente, no una persona ajena al proyecto: se acredita la reproducibilidad del procedimiento, no su usabilidad para un operador humano.
