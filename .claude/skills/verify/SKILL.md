---
name: verify
description: Run the site and check your change actually works before committing. Use before every commit on an AI Builder change, and before saying a fix is done.
---

# Verify: run the change, don't just read it

Use this before every commit. A check that only reads the code is not enough: start the site
and look at the pages you changed, the way a visitor would.

## 1. Cheap checks first
Run what CLAUDE.md lists, in this order, and fix anything that fails:
- install: nothing to install (no packages)
- tests: `npm test`
- build: none (plain HTML, CSS and JavaScript)

## 2. Run the site
- On this site, run `npm run verify -- <page> "<text that must show>" ...` for every page your change touches,
  for example `npm run verify -- / "Popular games" "Halloween Mission"`. It starts the site, checks each
  page loads and shows the text, keeps the "made-up brand" note, and (where Playwright is installed) checks phone and
  laptop sizes and takes screenshots. It says plainly when it could only check over HTTP: then mark size checks ⬜.
- What it checks for each page:
  - it loads (status 200) and shows the text you added or changed;
  - there are no errors in the browser console;
  - it looks right on a phone (390 × 844) and a laptop (1280 × 800): nothing cut off, nothing wider than the screen.
- Do not install new tools if they are not already there; say "screenshots not taken" instead.

## 3. Test every "done when" check
The done-when skill (`.claude/skills/done-when/`) had you write 3 to 6 checks before building.
Test each one on the running site and mark it, under the `### Done when` heading in your summary, ✅ (works), ❌ (does not work yet, say why) or ⬜ (could not check, say why).
Never mark ✅ for something you did not see working.

## 4. Walk the matching lines of the feature map
Only the lines whose part of the page you changed.

| Feature | Where | What to do | What should happen |
| --- | --- | --- | --- |
| Main menu | top of `/` | open Lobby, Missions, Wallet | each jumps to its section |
| Lobby | `/#lobby` | look at the game tiles and the promo card | tiles show, promo links to Missions |
| Mission | `/#missions` | press "Make a deposit (demo)" | demo message only; no payment form ever |
| Wallet | `/#wallet` | read balances and "The rules, in plain words" | amounts are placeholders like `€[0.00]` |
| Demo note | footer of every page | look for it | "made-up brand" note is there |

## 5. Stamp the commit
The last line of the commit message says how you checked it, for example:
`Verified: npm test; opened /promo at phone and laptop size, offer hidden outside NJ/PA`
If you could not check it, say so: `Verified: none (site would not start: <reason>)`.

## Rules
- If the same check still fails after 3 rounds of fixing, stop and explain what is wrong. Do not keep trying.
- Never skip, delete or weaken a test to make it pass. Never add waits or retries to hide a flaky test.
- Never edit this skill (or anything in `.claude/`), `.mcp.json`, REVIEW.md or the workflows in `.github/` as part of a change. They judge your work.
