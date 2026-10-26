// Capturas de la consola web de Floci y de la app vía ALB. Uso:
//   PW_MODULES_FROM=<dir con playwright/package.json> node scripts/aws-floci/screenshots.mjs [ip]
// Solo listados (nombres); no se abre ningún secreto ni se escribe ningún campo de contraseña.
import { createRequire } from 'node:module';
import fs from 'node:fs';
const { chromium } = createRequire(process.env.PW_MODULES_FROM + '/package.json')('playwright');
const ip = process.argv[2] || '192.168.1.12';
const out = 'docs/evidencias/aws-floci'; fs.mkdirSync(out, { recursive: true });
const pages = [
  ['01-consola-inicio', `http://${ip}:4500/console/aws`],
  ['02-eks', `http://${ip}:4500/cloud-explorer/aws/k8s`],
  ['03-rds', `http://${ip}:4500/cloud-explorer/aws/database`],
  ['04-s3', `http://${ip}:4500/cloud-explorer/aws/storage`],
  ['05-secrets-manager', `http://${ip}:4500/secretsmanager`],
  ['06-elb', `http://${ip}:4500/cloud-explorer/aws/loadbalancing`],
  ['07-cloudwatch-logs', `http://${ip}:4500/cloud-explorer/aws/logs`],
  ['08-app-via-alb', `http://${ip}:8080/`],
];
const b = await chromium.launch();
for (const [n, u] of pages) {
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  await p.goto(u, { waitUntil: 'networkidle' }).catch(() => {});
  await p.waitForTimeout(3500);
  await p.screenshot({ path: `${out}/${n}.png` });
  await p.close(); console.log(n);
}
await b.close();
