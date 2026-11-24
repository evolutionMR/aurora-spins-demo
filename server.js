// Tiny static file server for the demo site. Railway runs `npm start`.
const http = require('http');
const fs = require('fs');
const path = require('path');

const crypto = require('crypto');

const root = path.join(__dirname, 'public');

// Every copy of the site on Railway except the live one (previews of changes that are not approved
// yet) asks for a password. Locked by default: only the live environment is open, so a preview can
// never be public by accident. Set PREVIEW_PASSWORD in Railway; without it, previews stay locked.
// LIVE_ENVIRONMENT is the live environment's name in Railway ("production" unless set).
// Local runs (no Railway) are not affected.
const envName = (process.env.RAILWAY_ENVIRONMENT_NAME || '').trim();
const isPreview = !!envName && envName !== (process.env.LIVE_ENVIRONMENT || 'production').trim();
const previewPassword = process.env.PREVIEW_PASSWORD || '';
function samePassword(given) {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(previewPassword).digest();
  return crypto.timingSafeEqual(a, b);
}
function previewAllowed(req, res) {
  if (!isPreview) return true;
  if (!previewPassword) {
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('This preview is locked. Ask an admin to set PREVIEW_PASSWORD for previews in Railway.');
    return false;
  }
  const m = /^Basic ([A-Za-z0-9+/=]+)$/.exec(req.headers.authorization || '');
  const decoded = m ? Buffer.from(m[1], 'base64').toString('utf8') : '';
  const given = decoded.slice(decoded.indexOf(':') + 1);
  if (m && decoded.includes(':') && samePassword(given)) return true;
  res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="Aurora Spins preview", charset="UTF-8"', 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
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
