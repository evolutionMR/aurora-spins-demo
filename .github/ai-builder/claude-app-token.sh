#!/usr/bin/env bash
# A short-lived token of Claude's GitHub app, for the save job ONLY (no AI runs in that job).
# Pushes and pull requests made with it start the site's checks again; pushes made with the
# workflow's own token do not (GitHub's rule). It is the same exchange the official Claude action
# does when no github_token is given (src/github/token.ts in anthropics/claude-code-action v1.0.290):
# the job's GitHub OIDC token (audience "claude-code-github-action") is swapped for an app token.
# Anthropic only swaps it when this workflow file is the same as on the default branch, so a change
# that edits the workflow can never get one. It needs "id-token: write" on the job, and no secret.
# The Claude jobs never get id-token: write, so Claude can never get this token.
#
# Prints the token on stdout (masked in the log first). Prints nothing and fails if it cannot.
set -euo pipefail
[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] && [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ] || { echo "No id-token permission on this job." >&2; exit 1; }
oidc=$(curl -sS --fail --max-time 20 -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=claude-code-github-action" | jq -r '.value // empty')
[ -n "$oidc" ] || { echo "Could not get an OIDC token." >&2; exit 1; }
echo "::add-mask::$oidc" >&2
answer=$(curl -sS --max-time 30 -X POST -H "Authorization: Bearer $oidc" -w '\n%{http_code}' \
  https://api.anthropic.com/api/github/github-app-token-exchange || true)
code=$(tail -n1 <<<"$answer")
token=$(sed '$d' <<<"$answer" | jq -r '.token // .app_token // empty' 2>/dev/null || true)
if [ "$code" != 200 ] || [ -z "$token" ]; then
  # The answer's message only (never the body: it could hold a token).
  why=$(sed '$d' <<<"$answer" | jq -r '.error.message // .message // empty' 2>/dev/null | head -c 200 || true)
  echo "Claude's GitHub app gave no token (status $code${why:+: $why}). Is the Claude GitHub app installed, and is this workflow the same as on the default branch?" >&2
  exit 1
fi
echo "::add-mask::$token" >&2
printf '%s' "$token"
