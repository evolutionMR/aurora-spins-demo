// Tiny static file server for the demo site. Railway runs `npm start`.
const http = require('http');
const fs = require('fs');
const path = require('path');

const crypto = require('crypto');

const root = path.join(__dirname, 'public');

// Previews (Railway pull request copies, named like "aurora-spins-demo-pr-5") are password protected:
// a preview can show work that is not approved yet. The live site is never affected.
// Set PREVIEW_PASSWORD in Railway. Without it, a preview stays locked rather than open.
const isPreview = /-pr-\d+$/.test(process.env.RAILWAY_ENVIRONMENT_NAME || '');
const previewPassword = process.env.PREVIEW_PASSWORD || '';
function samePassword(given) {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(previewPassword).digest();
  return crypto.timingSafeEqual(a, b);
}
function previewAllowed(req, res) {
  if (!isPreview) return true;
  if (!previewPassword) {
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('This preview is locked. Ask an admin to set PREVIEW_PASSWORD for previews in Railway.');
    return false;
  }
  const m = /^Basic ([A-Za-z0-9+/=]+)$/.exec(req.headers.authorization || '');
  const decoded = m ? Buffer.from(m[1], 'base64').toString('utf8') : '';
  const given = decoded.slice(decoded.indexOf(':') + 1);
  if (m && decoded.includes(':') && samePassword(given)) return true;
  res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="Aurora Spins preview", charset="UTF-8"', 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('This preview needs the preview password.');
  return false;
}
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon' };

http.createServer((req, res) => {
  if (!previewAllowed(req, res)) return;
  let urlPath;
  try { urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname); } catch (e) { res.writeHead(400); return res.end('Bad request'); }
  if (urlPath.includes('\0')) { res.writeHead(400); return res.end('Bad request'); }
  const file = path.normalize(path.join(root, urlPath === '/' ? 'index.html' : urlPath));
  if (file !== root && !file.startsWith(root + path.sep)) { res.writeHead(403); return res.end('Forbidden'); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
}).listen(process.env.PORT || 3000, () => console.log('Aurora Spins demo on port ' + (process.env.PORT || 3000)));
