# Smoke del release en el laboratorio (2026-10-25)

Imágenes desplegadas (overlay `lab` = `prod`): `propuestas-api:738cb0d` (UBI9, x86-64-v2, plan 031) y `propuestas-web:7fdbaf0`.
Release: https://github.com/Emil2245/thesis-deploy/actions/runs/40181660044 (Trivy sin CRITICAL con fix).

| Comprobación | Resultado |
|---|---|
| `GET /` | 200 |
| `GET /api/v1/config/display` | 200, `{"precisionDinero":2,"precisionPorcentaje":4}` |
| `GET /privacidad` (ruta SPA) | 200 |
| `/q/health/ready` (port-forward al puerto de gestión 9000) | 200, `UP` (Database connections health check UP) |
| `POST /api/v1/auth/login` (usuario demo del seed) | 200 |
| `GET /api/v1/proyectos` con el token | 200 |

Pods api sin errores `x86-64-v3`. Flyway: de la versión 020 a 022 (`021 - normalize cronograma advance maps`, `022 - usuario acepta politica`); "Successfully applied 2 migrations ... now at version v022"; el segundo pod reporta "up to date".
