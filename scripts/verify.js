// Run the site and check pages the way a visitor would (the "verify" step).
//   npm run verify -- /index.html "Welcome" /tipoff.html?state=NJ "Claim"
// Each page path can be followed by text that must appear on it. With no pages, the home page is checked.
// Uses Playwright for phone (390px) and laptop (1280px) checks when it is installed;
// otherwise it checks over plain HTTP and says so (then text hidden on the page still counts as shown).
// Claude may run this but never edit it.
const { spawn } = require('child_process');
const path = require('path');

const args = process.argv.slice(2);
const pages = [];
const stray = [];
for (const a of args) {
  if (a.startsWith('/')) pages.push({ path: a, texts: [] });
  else if (pages.length) pages[pages.length - 1].texts.push(a);
  else stray.push(a);
}
if (stray.length) { console.log('❌ Put a page before the text to look for, for example: npm run verify -- / "' + stray[0] + '"'); process.exit(1); }
if (!pages.length) pages.push({ path: '/', texts: [] });

const port = 3100 + Math.floor(Math.random() * 800);
const base = 'http://127.0.0.1:' + port;
const results = [];
const ok = (t) => results.push('✅ ' + t);
const bad = (t) => results.push('❌ ' + t);
const note = (t) => results.push('⬜ ' + t);
const plain = (html) => html.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try { await fetch(base + '/'); return true; } catch (e) { await new Promise((r) => setTimeout(r, 100)); }
  }
  return false;
}

async function main() {
  const server = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { env: Object.assign({}, process.env, { PORT: String(port) }), stdio: 'ignore' });
  try {
    if (!(await waitForServer())) { bad('The site did not start.'); return; }
    for (const p of pages) {
      const res = await fetch(base + p.path);
      const body = await res.text();
      if (res.status !== 200) { bad(p.path + ' did not load (status ' + res.status + ').'); continue; }
      ok(p.path + ' loads.');
      const text = plain(body).toLowerCase();
      for (const t of p.texts) (text.includes(t.toLowerCase()) ? ok : bad)(p.path + ' shows "' + t + '".');
      if (/text\/html/.test(res.headers.get('content-type') || '')) {
        if (!/<meta[^>]+name="viewport"/i.test(body)) bad(p.path + ' has no viewport tag, so it will not fit phones.');
        if (!/made-up brand/i.test(body)) bad(p.path + ' is missing the "made-up brand" demo note.');
      }
    }
    let playwright = null;
    try { playwright = require('playwright'); } catch (e) { /* not installed */ }
    if (!playwright) { note('Phone and laptop look not checked: Playwright is not installed here. Checked over HTTP only.'); return; }
    const browser = await playwright.chromium.launch();
    try {
      for (const p of pages) {
        for (const [label, width, height] of [['phone', 390, 844], ['laptop', 1280, 800]]) {
          const page = await browser.newPage({ viewport: { width, height } });
          const errors = [];
          page.on('pageerror', (e) => errors.push(e.message));
          page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
          await page.goto(base + p.path, { waitUntil: 'networkidle' });
          const wide = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
          const shot = '/tmp/verify' + p.path.replace(/[^a-z0-9]+/gi, '-') + '-' + label + '.png';
          await page.screenshot({ path: shot, fullPage: true });
          (wide ? bad : ok)(p.path + ' on a ' + label + (wide ? ' is wider than the screen.' : ' fits the screen.') + ' Screenshot: ' + shot);
          (errors.length ? bad : ok)(p.path + ' on a ' + label + (errors.length ? ' has errors: ' + errors.slice(0, 3).join(' | ') : ' has no errors.'));
          await page.close();
        }
      }
    } finally { await browser.close(); }
  } finally { server.kill(); }
}

main().catch((e) => bad('Verify could not finish: ' + e.message)).finally(() => {
  console.log(results.join('\n'));
  process.exit(results.some((r) => r.startsWith('❌')) ? 1 : 0);
});
