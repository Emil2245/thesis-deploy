// Capturas de evidencia con Playwright. Uso:
//   PW_MODULES_FROM=<dir con playwright en node_modules> node tests/screenshots/capture.mjs <job> [args]
// Secretos solo por variables de entorno (GRAFANA_PASSWORD, ARGO_PASSWORD, DEMO_PASSWORD); nunca se capturan campos de password.
import { createRequire } from 'node:module';
const { chromium } = createRequire((process.env.PW_MODULES_FROM || process.cwd()) + '/package.json')(process.env.PW_PKG || 'playwright');
import fs from 'node:fs';
const [job, ...a] = process.argv.slice(2);
const G = 'https://grafana.192.168.1.9.sslip.io', APP = 'https://propuestas.192.168.1.9.sslip.io';
const out = (p) => { fs.mkdirSync(p.split('/').slice(0, -1).join('/'), { recursive: true }); return p; };
const browser = await chromium.launch();
const ctxOpts = { ignoreHTTPSErrors: true, viewport: { width: 1600, height: 900 } };
async function grafana(path, file, wait = 9000) {
  const ctx = await browser.newContext(ctxOpts);
  const p = await ctx.newPage();
  await p.goto(G + '/login'); await p.fill('input[name=user]', 'admin'); await p.fill('input[name=password]', process.env.GRAFANA_PASSWORD);
  await p.click('button[type=submit]'); await p.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 });
  await p.goto(G + path, { waitUntil: 'networkidle' }).catch(() => {});
  await p.waitForTimeout(wait); await p.screenshot({ path: out(file) }); await ctx.close();
}
if (job === 'dash') { // dash <file> <fromMs|now-30m> <toMs|now>
  const [file, from, to] = a;
  await grafana(`/d/propuestas-overview/propuestas-resumen?orgId=1&from=${from}&to=${to}&kiosk`, file);
} else if (job === 'explore') { // explore <traceId> <fileTempo> <fileLoki>
  const [tid, ft, fl] = a;
  const t = { datasource: 'tempo', queries: [{ refId: 'A', datasource: { type: 'tempo', uid: 'tempo' }, queryType: 'traceql', query: tid }], range: { from: 'now-3h', to: 'now' } };
  await grafana(`/explore?orgId=1&left=${encodeURIComponent(JSON.stringify(t))}`, ft, 12000);
  const l = { datasource: 'loki', queries: [{ refId: 'A', datasource: { type: 'loki', uid: 'loki' }, expr: `{namespace="propuestas"} |= \`${tid}\`` }], range: { from: 'now-3h', to: 'now' } };
  await grafana(`/explore?orgId=1&left=${encodeURIComponent(JSON.stringify(l))}`, fl, 12000);
} else if (job === 'jdbc') { // jdbc <traceId> <fileTrace> <fileDash>  (trace con span hijo JDBC + dashboard p95, ultimos 15 min)
  const [tid, ft, fd] = a;
  const t = { datasource: 'tempo', queries: [{ refId: 'A', datasource: { type: 'tempo', uid: 'tempo' }, queryType: 'traceql', query: tid }], range: { from: 'now-3h', to: 'now' } };
  await grafana(`/explore?orgId=1&left=${encodeURIComponent(JSON.stringify(t))}`, ft, 12000);
  await grafana('/d/propuestas-overview/propuestas-resumen?orgId=1&from=now-15m&to=now&kiosk', fd, 12000);
} else if (job === 'argo') { // requiere port-forward svc/argocd-server 8081:80 ; argo <dir>
  const ctx = await browser.newContext(ctxOpts); const p = await ctx.newPage();
  await p.goto('http://localhost:8081/login'); await p.fill('input[name=username]', 'admin'); await p.fill('input[name=password]', process.env.ARGO_PASSWORD);
  await p.click('button[type=submit]'); await p.waitForURL(/applications/, { timeout: 30000 }); await p.waitForTimeout(5000);
  await p.screenshot({ path: out(`${a[0]}/argocd-applications.png`) });
  await p.goto('http://localhost:8081/applications/argocd/propuestas?view=tree'); await p.waitForTimeout(8000);
  await p.screenshot({ path: out(`${a[0]}/argocd-propuestas-tree.png`) }); await ctx.close();
} else if (job === 'app') { // app <dir> [publicUrl]
  const ctx = await browser.newContext(ctxOpts); const p = await ctx.newPage();
  await p.goto(APP, { waitUntil: 'networkidle' }).catch(() => {}); await p.waitForTimeout(2000);
  await p.screenshot({ path: out(`${a[0]}/app-login.png`) });
  const email = p.locator('input[type=email], input[name=email]').first();
  await email.fill('john@uce.edu.ec'); await p.locator('input[type=password]').first().fill(process.env.DEMO_PASSWORD);
  await p.keyboard.press('Enter'); await p.waitForTimeout(6000);
  await p.goto(APP + '/proyectos', { waitUntil: 'networkidle' }).catch(() => {}); await p.waitForTimeout(3000);
  await p.screenshot({ path: out(`${a[0]}/app-proyectos.png`) }); await ctx.close();
  if (a[1]) { const c2 = await browser.newContext(ctxOpts); const q = await c2.newPage(); await q.goto(a[1], { waitUntil: 'networkidle' }).catch(() => {}); await q.waitForTimeout(2000); await q.screenshot({ path: out(`${a[0]}/app-trycloudflare.png`) }); }
}
await browser.close();
