// Basic checks run on every change (npm test). Keep them fast and simple.
const fs = require('fs');
const path = require('path');

const pub = path.join(__dirname, '..', 'public');
const errors = [];
const html = fs.readFileSync(path.join(pub, 'index.html'), 'utf8');

// 1. Every local file the page links to must exist.
for (const m of html.matchAll(/(?:href|src)="([^"#:]+)"/g)) {
  if (!fs.existsSync(path.join(pub, m[1]))) errors.push('Missing file linked from index.html: ' + m[1]);
}
// 2. Images need alt text.
for (const m of html.matchAll(/<img\b[^>]*>/g)) {
  if (!/\balt="/.test(m[0])) errors.push('Image without alt text: ' + m[0]);
}
// 3. The demo must stay clearly labelled as a made-up brand.
if (!/made-up brand/i.test(html)) errors.push('The "made-up brand" demo note was removed.');
// 4. No real-money or payment wording sneaks in.
if (/(credit card|card number|iban|real money deposit)/i.test(html)) errors.push('Payment wording found. This demo must not ask for payment details.');
// 5. The JavaScript must parse.
for (const f of fs.readdirSync(pub).filter((f) => f.endsWith('.js'))) {
  try { new Function(fs.readFileSync(path.join(pub, f), 'utf8')); } catch (e) { errors.push(f + ' has a syntax error: ' + e.message); }
}

if (errors.length) { console.error('Checks failed:\n- ' + errors.join('\n- ')); process.exit(1); }
console.log('All checks passed.');
