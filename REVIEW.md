# REVIEW.md: what the AI reviewer looks for on this site

The AI Builder review reads this file from the **main branch**, never from the change it is
judging. Change it with a normal pull request from a person. This copy is filled in for the Aurora Spins demo.

## How to mark findings
- **Important**: a bug or rule break this change adds or makes worse. Blocks going live.
- **Pre-existing**: it was already broken. Mention it, do not blame the change, do not block.
- **Nit**: small and optional.

Only bugs and rule breaks. No style opinions. Confirm each finding in the code before reporting it.

## Always check
1. **Does it do what was asked?** Compare the change with the request and Claude's "done when" checks in the linked task. A check marked ✅ that the code does not do is Important. Anything extra that was not asked for is Important.
2. **House rules** in CLAUDE.md: brand, wording, design system.
3. **Phones and laptops**: nothing wider than the screen, buttons big enough to tap, text readable.
4. **Nothing private gets out**: no keys, tokens, passwords, customer data or internal links in the code or the page.
5. **Tests**: if behaviour changed, a test should cover it. A deleted or weakened test is Important.
6. **Verified line**: each commit should end with `Verified: …`. `Verified: none` on a page change is a Nit, with the reason.

## Regulated sites (iGaming): Aurora Spins rules
- Every offer shows its key terms next to it (wagering, minimum deposit, expiry) and links to full terms.
- Age (18+ or 21+) and safer-gambling messages and links are never removed, hidden or made smaller.
- Location rules: offers only show where they are allowed. Check what happens for a place that is **not** on the list and for an **unknown** location.
- No promises the company cannot prove ("best odds", "guaranteed win", "risk free").
- Anything touching bonuses, limits, safer-gambling tools, age or ID checks needs compliance sign-off. Say so in the review.
- Aurora Spins is a made-up brand: the "made-up brand" demo note always stays, amounts stay as placeholders like `€[0.00]`, and there are no payment forms, card or bank fields, real games or real brands (see CLAUDE.md).

## Checks that start from the change
Each line: when the change touches this → check this → the real case it came from.
Add a line every time a bug gets past review. Remove lines that no longer apply.

| When the change… | Check that… | Came from |
| --- | --- | --- |
| shows something only in some states or countries | it stays hidden for every place not on the list, and when the location is unknown | Aurora Spins PR #5: the offer still showed outside NJ and PA |
| adds or changes a form | it shows a clear message when a field is wrong, and nothing is sent twice on a double tap | general rule |
| changes a promo or landing page | the offer terms and the 18+ / safer-gambling lines are still visible on a phone | general rule |
| changes the wallet or the mission | play-through and balances stay placeholders, and the rules box still explains them in plain words | Aurora PR #3 (play-through bar) |
| adds a badge, banner or label on game tiles | it is readable on its background (contrast 4.5:1) and does not cover the game name on a phone | Aurora request #6 ("New" badge) |
