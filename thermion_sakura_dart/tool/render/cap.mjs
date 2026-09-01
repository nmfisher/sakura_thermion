// Generic compositor capture: screenshot a URL to PNG (works for both the
// reference Three.js app and the Thermion web build).
//   node cap.mjs <url> <out.png> [waitSeconds] [--hideOverlay]
import { chromium } from 'playwright';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname, normalize } from 'node:path';

const serveDirArg = process.argv.find((a) => a.startsWith('--serve='));
const urlArg = process.argv[2];
const out = process.argv[3];
const waitSec = parseFloat(process.argv[4] || '8');
const hideOverlay = process.argv.includes('--hideOverlay');

let url = urlArg;
if (serveDirArg) {
  const root = serveDirArg.split('=')[1];
  const mime = { '.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.png':'image/png','.jpg':'image/jpeg','.svg':'image/svg+xml','.mp3':'audio/mpeg','.ktx':'image/ktx','.wasm':'application/wasm','.mjs':'text/javascript' };
  const server = http.createServer(async (req, res) => {
    try {
      let p = decodeURIComponent(req.url.split('?')[0]);
      if (p === '/') p = '/index.html';
      const f = normalize(join(root, p));
      if (!f.startsWith(normalize(root))) { res.writeHead(403); res.end(); return; }
      const data = await readFile(f);
      res.writeHead(200, { 'content-type': mime[extname(f)] || 'application/octet-stream' });
      res.end(data);
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  url = `http://127.0.0.1:${server.address().port}/`;
  console.log(`serving ${root} on ${url}`);
}

const browser = await chromium.launch({
  headless: true,
  args: [
    '--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage',
    '--use-gl=angle', '--use-angle=swiftshader-webgl',
    '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
  ],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text().slice(0, 200)}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message.slice(0, 300)}`));
try {
  await page.goto(url, { waitUntil: 'networkidle', timeout: 90000 });
} catch (e) { console.error('goto failed:', e.message); }

if (hideOverlay) {
  await page.evaluate(() => {
    const o = document.querySelector('.overlay');
    if (o) { o.classList.add('hidden'); o.dataset.mode = 'paused'; }
    document.querySelector('.crosshair')?.classList.add('on');
  });
}
await new Promise((r) => setTimeout(r, waitSec * 1000));
await page.screenshot({ path: out, type: 'png', timeout: 120000 });
console.log('saved', out);
console.log('--- logs ---');
console.log(logs.slice(0, 12).join('\n') || '(none)');
await browser.close();
