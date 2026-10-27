// Capturas de la app (login) y de Grafana por HTTPS. Uso:
//   PW_MODULE=<ruta a playwright o playwright-core> [OUT=<dir>] [CA_INSECURE=1] node scripts/vps/screenshots.mjs <dominio>
// Solo paginas publicas (login de la app y de Grafana); no se escribe ningun campo de contrasena.
// CA_INSECURE=1 acepta la CA propia (selfsigned-ca) en la captura; con Let's Encrypt no hace falta.
import { createRequire } from 'node:module';
import fs from 'node:fs';
const { chromium } = createRequire(import.meta.url)(process.env.PW_MODULE || 'playwright');
const d = process.argv[2]; if (!d) { console.error('uso: screenshots.mjs <dominio>'); process.exit(1); }
const out = process.env.OUT || 'docs/evidencias/vps'; fs.mkdirSync(out, { recursive: true });
const pages = [['01-app-login-https', `https://propuestas.${d}/`], ['02-grafana-https', `https://grafana.${d}/login`]];
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1440, height: 800 }, ignoreHTTPSErrors: process.env.CA_INSECURE === '1' });
for (const [n, u] of pages) {
  const p = await ctx.newPage();
  await p.goto(u, { waitUntil: 'networkidle' }).catch(() => {});
  await p.waitForTimeout(2500);
  await p.screenshot({ path: `${out}/${n}.png` });
  await p.close(); console.log(n);
}
await b.close();
