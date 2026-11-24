# Aurora Spins (demo)

A made-up casino player site used to demo the **AI Builder**: people who are not engineers ask for a change in plain words, Claude Code builds it on its own branch, Railway makes a preview link, and an engineer approves it.

- Run locally: `npm start` then open http://localhost:3000
- Checks: `npm test`
- House rules for Claude: [CLAUDE.md](./CLAUDE.md)

## Workflows
- `.github/workflows/claude.yml`: Claude builds a change when an issue or comment mentions `@claude`. Its commits are saved through Claude's GitHub app (`use_commit_signing`), so every fix starts the checks again.
- `.github/workflows/ci.yml` ("Checks"): runs `npm test` on every pull request.
- `.github/workflows/ai-builder-review.yml`: one AI review per new version, findings marked Important / Pre-existing / Nit; fails on Important.
- `.github/workflows/ai-builder-fixer.yml`: Claude fixes failing checks and important review findings by itself (3 tries, then `needs-a-person`).
- `.github/workflows/ai-builder-guard.yml`: a Claude change may not edit the checks, Claude's settings, the house rules, the test scripts or the server.

The review rules are in [REVIEW.md](./REVIEW.md); how Claude agrees and tests "done" is in `.claude/skills/`. `npm run verify -- / "Popular games"` starts the site and checks pages.

Needs the repository secret `CLAUDE_CODE_OAUTH_TOKEN` and the Claude GitHub App installed on this repo.

**No branch protection:** this is a private repo on a free GitHub plan, so GitHub cannot force "only an engineer merges". The workflows never merge, but the real lock needs a paid plan or a public repo.
