---
name: verify
description: Say which pages the workflow should open to check your change, and what each must show. Use on every AI Builder change, before you stop. The workflow (not Claude) runs the tests and the verify step and writes the commit's "Verified:" line.
---

# Verify: the workflow runs it, you say what to look at

In the AI Builder workflows you cannot run commands. After you stop, a job with no AI applies your
change to a clean copy and runs the commands an engineer set in `.github/ai-builder/kit.json`:
- the site's tests (`npm test`: links point to files that exist, images have alt text, the
  "made-up brand" note is there, no payment wording, the JavaScript parses);
- the verify step (`npm run verify --`), on the pages you list below: it starts the site, checks each
  page loads and shows your texts, keeps the "made-up brand" note, and checks phone (390px) and
  laptop (1280px) sizes with Playwright.
It writes what happened into the pull request and the commit's `Verified:` line. You never write a
`Verified:` line yourself.

## 1. Read the code you changed again
Before you stop, read every file you changed once more, the way a careful reviewer would:
- links and pictures point to files that exist; pictures have alt text;
- buttons and links are real `<button>` and `<a>` elements, at least 44px tall;
- text is easy to read on its background (contrast 4.5:1); nothing is wider than a phone screen;
- the house rules in CLAUDE.md still hold (for regulated sites: offer terms, 18+ and safer-gambling lines).

## 2. Say which pages to look at
Write `.ai-builder/run/verify.txt`: one line per page your change touches (at most 5), the page's
address first, then short texts that must show on it, each after ` | `:

```
/ | 18+ only. Play responsibly. | made-up brand
```

- The address starts with `/`. Texts are plain words from the page (no code, no `<`, `>`, `@` or backticks), at most 5 per page.
- Only pages your change touches. If none of them can be opened on their own, write `/`.

## 3. Walk the matching lines of the feature map
Only the lines whose part of the page you changed. Put what the workflow can check into verify.txt
(on this site everything is on `/`), and the rest into your "done when" list as ⬜ with what a person
should look at.

| Feature | Where | What to do | What should happen |
| --- | --- | --- | --- |
| Main menu | top of `/` | open Lobby, Missions, Wallet | each jumps to its section |
| Lobby | `/#lobby` | look at the game tiles and the promo card | tiles show, promo links to Missions |
| Mission | `/#missions` | press "Make a deposit (demo)" | demo message only; no payment form ever |
| Wallet | `/#wallet` | read balances and "The rules, in plain words" | amounts are placeholders like `€[0.00]` |
| Demo note | footer of every page | look for it | "made-up brand" note is there |

## Rules
- If the same check still fails after 3 rounds of fixing, stop and explain what is wrong. Do not keep trying.
- Never skip, delete or weaken a test to make it pass. Never add waits or retries to hide a flaky test.
- Never edit this skill (or anything in `.claude/`), `.mcp.json`, REVIEW.md, the kit in `.github/ai-builder/` or the workflows in `.github/`. They judge your work, and the workflow refuses any change to them.
