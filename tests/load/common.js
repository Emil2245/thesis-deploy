import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
export const badStatus = new Counter('bad_status');

export const BASE = __ENV.BASE_URL || 'https://propuestas.192.168.1.9.sslip.io';
export const API = `${BASE}/api/v1`;
export const PRESUPUESTO = '0192f6c4-7c8a-7abc-8000-000000001201';
export const PROYECTO = '0192f6c4-7c8a-7abc-8000-000000001102';
const EXPECTED_EXPORT = http.expectedStatuses(200, 409); // seed: cronograma no exportable (409 de negocio)

export function login() {
  const pass = __ENV.DEMO_PASSWORD;
  if (!pass) throw new Error('DEMO_PASSWORD requerido');
  const r = http.post(`${API}/auth/login`,
    JSON.stringify({ email: 'john@uce.edu.ec', password: pass }),
    { headers: { 'Content-Type': 'application/json' } });
  if (r.status !== 200) throw new Error(`login fallo: ${r.status}`);
  return r.json('accessToken');
}

// Idempotency-Key debe ser UUIDv7 (contrato §8): 48 bits de ms + versión 7 + variante RFC 4122.
export function uuidv7() {
  const h = Date.now().toString(16).padStart(12, '0');
  const r = () => Math.floor(Math.random() * 16).toString(16);
  let rnd = '';
  for (let i = 0; i < 16; i += 1) rnd += r();
  const variante = (8 + Math.floor(Math.random() * 4)).toString(16);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-7${rnd.slice(0, 3)}-${variante}${rnd.slice(3, 6)}-${rnd.slice(6, 16)}${r()}${r()}`;
}

// Export de cronograma (etapa 05: el GET de bytes se retiró): POST con clave única por
// iteración y, si Core emite ticket (200), GET del ticket de un solo uso. 409 de negocio
// (seed no exportable) se acepta y no hay ticket que consumir.
export function exportarCronograma(p) {
  const r = http.post(`${API}/documentos/cronograma/${PRESUPUESTO}/exportaciones`,
    JSON.stringify({ formato: 'xlsx' }),
    { headers: { ...p.headers, 'Content-Type': 'application/json', 'Idempotency-Key': uuidv7() },
      responseCallback: EXPECTED_EXPORT });
  if (r.status !== 200) return r;
  return http.get(`${BASE}${r.json('downloadUrl')}`, { tags: { name: 'ticket' } });
}

// Mezcla: ~70 % lecturas, ~25 % lecturas pesadas (arbol/cronograma), ~5 % export
export function iteration(token) {
  const p = { headers: { Authorization: `Bearer ${token}` } };
  const x = Math.random();
  let r;
  if (x < 0.35) r = http.get(`${API}/proyectos?page=0&size=25`, p);
  else if (x < 0.70) r = http.get(`${API}/proyectos/${PROYECTO}/insumos?page=0&size=25`, p);
  else if (x < 0.85) r = http.get(`${API}/presupuestos/${PRESUPUESTO}`, p);
  else if (x < 0.95) r = http.get(`${API}/presupuestos/${PRESUPUESTO}/cronograma`, p);
  else r = exportarCronograma(p);
  if (!(r.status === 200 || (r.status === 409 && r.url.includes('/documentos/')))) { badStatus.add(1, { status: String(r.status), err: r.error_code ? String(r.error_code) : 'none' }); console.error(`FALLO status=${r.status} err=${r.error || ''} url=${r.url.replace(BASE, '')}`); }
  check(r, { 'status esperado': (res) => res.status === 200 || (res.status === 409 && res.url.includes('/documentos/')) });
  sleep(0.2 + Math.random() * 0.3);
}
