---
name: done-when
description: Turn a plain-words change request into 3 to 6 "done when" checks before building, then test each one. Use at the start of every AI Builder request and again when the request is updated.
---

# Done when: agree what "working" means before you build

A request like "add a welcome offer banner" can be built many ways. Before writing any code,
write down what a person should see when it works. Then build, then test every check.
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

## 2. Build, then test each check
Use the verify skill (`.claude/skills/verify/`) to run the site and look. Test every check on the
running site, not by reading the code.

## 3. Report them in your final summary
Add a heading line `### Done when` and put the checks under it, one list line each, each starting with one mark:

```
### Done when
- ✅ The banner shows at the top of the home page, above the games list.
- ✅ On a phone the banner fits the screen and the button is easy to tap.
- ❌ The offer is hidden in states where it is not allowed. Still shows in NY: the list of states is not read yet.
- ⬜ Text in Maltese fits. Could not check: no Maltese text on the demo site.
```

Use that heading only once, for the final list.

- ✅ checked on the running site, and it works.
- ❌ checked, and it does not work yet. Say why in a few words.
- ⬜ could not check. Say why.

Never mark ✅ for something you did not actually see working. A ❌ or ⬜ with an honest reason is better than a wrong ✅.

## When the request is updated
Read the new message, change or add checks to match, test them all again (not only the new ones),
and report the full list again in the same way.
