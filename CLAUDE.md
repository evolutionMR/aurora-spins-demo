# Aurora Spins demo site: house rules

This is a demo player website for a made-up casino brand, "Aurora Spins". People who are not engineers ask for changes through the AI Builder. Your job is to make their change safely and simply.

## How to work
- Make only the change the request asks for. Keep it small.
- Work in `public/` (index.html, styles.css, app.js). Do not change `server.js`, `scripts/`, `package.json` or `.github/` unless the request is clearly about them.
- Run `npm test` before you finish. Fix anything it reports.
- Write a short, plain-language summary of what you changed for a non-technical reader.

## Brand rules
- Colours and fonts live in the `:root` block of `styles.css`. Use those variables (`--accent`, `--surface`, etc.). Add a new variable there if you need a new colour.
- Headings use `--font-head` (DM Serif Display). Body text uses `--font-body` (Inter).
- Keep the friendly, simple tone. Short sentences.

## Must always stay true
- The page says it is a demo with a made-up brand. Never remove that note.
- No real money, no payment forms, no card or bank fields, no real game names or real brands.
- Prices, balances and amounts stay as placeholders in square brackets, like `€[0.00]`.
- Accessible: buttons and links at least 44px tall, text easy to read on its background (contrast 4.5:1), alt text on images, real `<button>` and `<a>` elements.
- Works on a phone (390px wide) and on a laptop.
