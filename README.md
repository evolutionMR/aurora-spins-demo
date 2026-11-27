# Aurora Spins (demo)

A made-up casino player site used to demo the **AI Builder**: people who are not engineers ask for a change in plain words, Claude Code builds it on its own branch, Railway makes a preview link, and an engineer approves it.

- Run locally: `npm start` then open http://localhost:3000
- Checks: `npm test`
- House rules for Claude: [CLAUDE.md](./CLAUDE.md)

## Workflows
Every workflow starts with a short threat model. In short: Claude runs only in read-only jobs (it can read the code and change files in `public/`, nothing else, and has no command line, web or secrets). Jobs with no AI test the change, save it on its own `claude/` branch and post the results. See the AI Builder's `site-kit/README.md`.
- `.github/workflows/claude.yml`: Claude plans or builds a change when an issue or comment from someone with write access mentions `@claude`. A job with no AI opens the pull request.
- `.github/workflows/ci.yml` ("Checks"): runs `npm test` on every pull request.
- `.github/workflows/ai-builder-review.yml`: one AI review per new version, findings marked Important / Pre-existing / Nit; the `review` check fails on Important.
- `.github/workflows/ai-builder-fixer.yml`: Claude fixes failing checks and important review findings by itself (3 tries, then `needs-a-person`).
- `.github/workflows/ai-builder-guard.yml`: a Claude change may not edit the checks, Claude's settings, the house rules, the test scripts or the server.
- `.github/ai-builder/`: the scripts these workflows run, and `kit.json` (what Claude may change: `public/`; the AI Builder's GitHub account, `evolutionMR`, whose bet card picks are the only ones that count). The site's tests run in the workflows as a separate user with no sudo and a clean environment; their `Verified:` line is a hint, and the `test` and `review` checks are the real gate.

The review rules are in [REVIEW.md](./REVIEW.md); how Claude agrees and tests "done" is in `.claude/skills/`. `npm run verify -- / "Popular games"` starts the site and checks pages.

Needs the repository secret `CLAUDE_CODE_OAUTH_TOKEN` and the Claude GitHub App installed on this repo.

**Branch protection:** this repo is public, and `main` needs a pull request with 1 approval from a code owner, plus the `test` and `review` checks. The workflows never approve or merge.
