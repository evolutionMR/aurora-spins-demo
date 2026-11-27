---
name: done-when
description: Turn a plain-words change request into 3 to 6 "done when" checks before building, then mark each one honestly. Use at the start of every AI Builder request and again when the request is updated. In the AI Builder workflows Claude cannot open the site; the workflow runs the tests and looks at the pages afterwards.
---

# Done when: agree what "working" means before you build

A request like "add a welcome offer banner" can be built many ways. Before changing anything,
write down what a person should see when it works. Then build, then mark every check.
The checks are shown to the person who asked, the AI reviewer checks them, and so does the engineer.

## 1. Write the checks (before building)
Write 3 to 6 short lines. Each one is something a person could check on the preview in under a minute.
- **What they see**: "The banner shows at the top of the home page, above the games list."
- **What happens when they act**: "Tapping 'Claim' opens the sign-up form."
- **Tricky cases** (pick the ones that fit this change):
  - phone size and laptop size;
  - logged in and logged out;
  - empty or missing data (no offer set, no games in the list);
  - very long text (another language, a long offer name);
  - a place, country or state where it must **not** show, and an unknown location;
  - a second tap or a slow connection (nothing sent twice).
- **House rules that apply**: from CLAUDE.md and the company settings in the request
  (for regulated sites: offer terms visible next to the offer, 18+ and safer-gambling lines still there).

Rules for writing them:
- Plain words a non-technical person understands. No code, file names or jargon.
- Only what the request asked for. If you think something extra is needed, say so in your summary; do not add it.
- If the request is unclear, write the check the way you understood it and say so. Do not guess silently.

## 2. Build, then mark each check honestly
In the AI Builder workflows you can only read and write files: you cannot run the tests or open the
site. So you have NOT seen any of it working. After you stop, the workflow runs the tests and opens
the pages you list in `.ai-builder/run/verify.txt` (see the verify skill), and the preview and the
AI review come after that.
- ⬜ for every check you could not see yourself, with a few words, for example "The workflow checks the home page shows it" or "Look at the preview on a phone."
- ❌ for a check you know is not done (you could not do it, or it would break a house rule). Say why.
- Never mark ✅: you did not see it working.

## 3. Report them in your summary
At the end of `.ai-builder/run/summary.md`, add a heading line `### Done when` and put the checks
under it, one list line each, each starting with one mark:

```
### Done when
- ⬜ The banner shows at the top of the home page, above the games list. The workflow checks the home page shows it.
- ⬜ On a phone the banner fits the screen and the button is easy to tap. Look at the preview on a phone.
- ❌ The offer is hidden in states where it is not allowed. The list of states is not in this website's code.
```

Use that heading only once, for the final list.

## When the request is updated
Read the new message, change or add checks to match, mark them all again (not only the new ones),
and report the full list again in the same way.
