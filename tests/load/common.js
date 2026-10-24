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

// Mezcla: ~70 % lecturas, ~25 % lecturas pesadas (arbol/cronograma), ~5 % export
export function iteration(token) {
  const p = { headers: { Authorization: `Bearer ${token}` } };
  const x = Math.random();
  let r;
  if (x < 0.35) r = http.get(`${API}/proyectos?page=0&size=25`, p);
  else if (x < 0.70) r = http.get(`${API}/proyectos/${PROYECTO}/insumos?page=0&size=25`, p);
  else if (x < 0.85) r = http.get(`${API}/presupuestos/${PRESUPUESTO}`, p);
  else if (x < 0.95) r = http.get(`${API}/presupuestos/${PRESUPUESTO}/cronograma`, p);
  else r = http.get(`${API}/documentos/cronograma/${PRESUPUESTO}?formato=xlsx`,
        { ...p, responseCallback: EXPECTED_EXPORT });
  if (!(r.status === 200 || (r.status === 409 && r.url.includes('/documentos/')))) { badStatus.add(1, { status: String(r.status), err: r.error_code ? String(r.error_code) : 'none' }); console.error(`FALLO status=${r.status} err=${r.error || ''} url=${r.url.replace(BASE, '')}`); }
  check(r, { 'status esperado': (res) => res.status === 200 || (res.status === 409 && res.url.includes('/documentos/')) });
  sleep(0.2 + Math.random() * 0.3);
}
