# Aurora Spins (demo)

A made-up casino player site used to demo the **AI Builder**: people who are not engineers ask for a change in plain words, Claude Code builds it on its own branch, Railway makes a preview link, and an engineer approves it.

- Run locally: `npm start` then open http://localhost:3000
- Checks: `npm test`
- House rules for Claude: [CLAUDE.md](./CLAUDE.md)

## Workflows
- `.github/workflows/claude.yml`: Claude builds a change when an issue mentions `@claude`.
- `.github/workflows/ci.yml`: runs `npm test` on every pull request.
- `.github/workflows/claude-review.yml`: Claude reviews every pull request.

Needs the repository secret `ANTHROPIC_API_KEY` and the Claude GitHub App installed on this repo.
