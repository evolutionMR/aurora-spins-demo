#!/usr/bin/env bash
# The save step of the AI Builder workflows. No Claude runs in this job and it gets no Claude key.
# The workflow runs its OWN copy (from the default branch, copied to $RUNNER_TEMP), never one from a
# working tree Claude has written in.
#
#   kit-save.sh plan | build | update | fix     after the Claude job (and the test job)
#   kit-save.sh review                          after the AI review's Claude job
#   kit-save.sh failed "<words>"                when the save itself went wrong
#
# plan:   posts Claude's plan (the bet card) on the task. Nothing is pushed.
# build:  applies Claude's patch to a clean clone of the commit Claude started from, with
#         kit-change.sh (the same allow list again), commits it to a NEW branch
#         claude/issue-<task>-<YYYYMMDD-HHMMSS>, pushes, opens the pull request and posts the result.
# update, fix: the same, onto the pull request's own claude/ branch, only if it has not moved since
#         Claude started (never a force push), then posts the result on the pull request.
# review: posts the AI review with the workflow's own summary lines, and fails when it is Important.
# Never pushes to any branch but a claude/ one: never main, never a force push. Never approves or merges.
#
# Every result is ONE comment that starts with the kit's marker line (the review: <!-- ai-builder-review -->):
#   <!-- ai-builder-kit site run=<run id> kind=<plan|build|update|fix> result=<done|failed> -->
# AI Builder trusts it only from this repo's GitHub Actions bot (lib/ship.js). Claude's own words are
# always quoted ("> " on every line), with @ mentions and HTML comments made harmless, so they can
# never look like the workflow's lines.
#
# Needs: REPO, RUN_ID, GH_TOKEN (this job's token: comments and labels), IN (Claude's artifact folder),
# KIT (folder with kit-change.sh), KIT_JSON, RUNNER_TEMP, and per mode: ISSUE, PR, BRANCH, SHA (the
# commit Claude started from), BASE (the default branch), STAMP (YYYYMMDD-HHMMSS, build), OPTION,
# TESTS (the test job's artifact folder). PUSH_TOKEN: Claude's GitHub app token, so pushes start the
# checks (claude-app-token.sh); without it the job's own token is used and the checks may not start.
set -euo pipefail
export LC_ALL=C.UTF-8 GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
die() { echo "::error::$*" >&2; exit 1; }
CMD="${1:-}"
[[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Bad repo name"
[[ "${RUN_ID:-}" =~ ^[0-9]{1,20}$ ]] || die "Bad run id"
num() { [[ "${1:-}" =~ ^[1-9][0-9]{0,8}$ ]]; }
TMP="${RUNNER_TEMP:-/tmp}"
BODY=$(mktemp "$TMP/ai-builder-comment.XXXXXX")
WORK=""
trap 'rm -rf "$BODY" "$BODY.plan" "$BODY.words" ${WORK:+"$WORK" "$WORK.err"}' EXIT

# Every line break first: CR, and the ones that are not "\n" but still start a new line for some
# readers (U+2028, U+2029, U+0085, vertical tab, form feed), so no line can hide inside another.
LINES='gsub("\r\n?|[\u2028\u2029\u0085\u000b\u000c]"; "\n")'
# Claude's words, quoted line by line, at most 20,000 characters.
quoted() {
  head -c 20000 "$1" | jq -Rrs "$LINES"' | gsub("<!--"; "&lt;!--") | gsub("@(?<a>[A-Za-z0-9])"; "@​\(.a)") | rtrimstr("\n") | split("\n") | map("> " + .) | join("\n")'
}
# A short line of plain words from a file (an error message), made harmless the same way.
short() { head -c 300 "$1" | jq -Rrs "$LINES"' | gsub("\n+"; " ") | gsub("::error::"; "") | gsub("<!--"; "&lt;!--") | gsub("@(?<a>[A-Za-z0-9])"; "@​\(.a)") | rtrimstr(" ")'; }
plain() { jq -Rrs "$LINES"' | gsub("<!--"; "&lt;!--") | gsub("@(?<a>[A-Za-z0-9])"; "@​\(.a)")'; }
# A plan over 20,000 bytes keeps its bet card: the start of the plan, a note, then the "Bet card"
# section from its last heading (at most 8,000 bytes). $1 = plan file, $2 = file to write.
fit_plan() {
  local size at card
  size=$(stat -c%s "$1")
  if [ "$size" -le 20000 ]; then cp "$1" "$2"; return; fi
  at=$(grep -niE '^#{1,6}[[:space:]]*bet card[[:space:]]*$' "$1" | tail -1 | cut -d: -f1 || true)
  if [ -z "$at" ]; then head -c 20000 "$1" > "$2"; return; fi
  card=$(mktemp "$TMP/ai-builder-card.XXXXXX")
  tail -n "+$at" "$1" | head -c 8000 > "$card"
  { head -n "$((at - 1))" "$1" | head -c "$((19800 - $(stat -c%s "$card")))"
    printf '\n\n[The plan was too long to show in full, so part of it was cut. The bet card below is complete.]\n\n'
    cat "$card"; } > "$2"
  rm -f "$card"
}

# Where the result goes: the task for plan and build, the pull request for the rest.
case "$CMD" in
  plan|build) num "${ISSUE:-}" || die "Bad task number"; TARGET="$ISSUE"; KIND="$CMD" ;;
  update|fix) num "${PR:-}" || die "Bad pull request number"; TARGET="$PR"; KIND="$CMD" ;;
  review) num "${PR:-}" || die "Bad pull request number"; TARGET="$PR"; KIND=review ;;
  failed) TARGET="${PR:-${ISSUE:-}}"; num "$TARGET" || die "Nothing to post on"; KIND="${KIND:-build}" ;;
  *) die "Usage: kit-save.sh plan|build|update|fix|review|failed" ;;
esac
[[ "$KIND" =~ ^(plan|build|update|fix|review)$ ]] || die "Bad kind"
marker() { printf '<!-- ai-builder-kit site run=%s kind=%s result=%s -->\n' "$RUN_ID" "$KIND" "$1"; }
post() {
  jq -n --rawfile b "$BODY" '{body: $b}' | gh api "repos/$REPO/issues/$TARGET/comments" --method POST --input - >/dev/null
  echo "Posted the $KIND result on #$TARGET."
}
what() { case "$KIND" in plan) echo plan ;; fix) echo fix ;; *) echo change ;; esac; }
failed() {
  { marker failed
    echo "**Claude could not finish this $(what).** $1"
    echo
    echo "Nothing was saved. Try again, or ask for the change in simpler words."
  } > "$BODY"
  post
}
if [ "$CMD" = failed ]; then failed "${2:-The workflow stopped early.}"; exit 0; fi

# ---------- The AI review ----------
if [ "$CMD" = review ]; then
  [[ "${SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "Bad commit"
  note="${IN:-/nonexistent}/notes/review.md"
  outcome=$(head -c 20 "${IN:-/nonexistent}/outcome" 2>/dev/null | tr -cd '[:lower:]' || true)
  line=""
  if [ "$outcome" = success ] && [ -f "$note" ] && [ ! -L "$note" ] && [ -s "$note" ]; then
    # Claude's own counts line (the last one). The workflow writes its own copy below.
    line=$(grep -E '^AI review: Important [0-9]{1,3}[^0-9A-Za-z]+Pre-existing [0-9]{1,3}[^0-9A-Za-z]+Nit [0-9]{1,3}\s*$' "$note" | tail -1 || true)
  fi
  if [ -z "$line" ]; then
    echo "::error::The AI review did not finish or did not write its summary for this version. Run it again."
    exit 1
  fi
  read -r imp pre nit < <(sed -E 's/^AI review: Important ([0-9]+)[^0-9A-Za-z]+Pre-existing ([0-9]+)[^0-9A-Za-z]+Nit ([0-9]+).*/\1 \2 \3/' <<<"$line")
  { echo "<!-- ai-builder-review -->"
    echo "**AI review of this change.** Claude reviewed it in a read-only job; the workflow posted this."
    echo
    grep -vE '^AI review: ' "$note" > "$BODY.words" || true
    quoted "$BODY.words"; rm -f "$BODY.words"
    echo
    echo "Reviewed commit: $SHA"
    echo "AI review: Important $imp · Pre-existing $pre · Nit $nit"
  } > "$BODY"
  post
  if [ "$imp" -gt 0 ]; then echo "::error::The AI review found $imp important problem(s). The AI Builder fixer will try to fix them."; exit 1; fi
  exit 0
fi

# ---------- Claude's result ----------
[ -d "${IN:-}" ] || { failed "Claude's work did not reach the save step."; exit 0; }
outcome=$(head -c 20 "$IN/outcome" 2>/dev/null | tr -cd '[:lower:]' || true)
if [ -f "$IN/refused.txt" ]; then
  failed "It tried to change a file it may not change, so nothing was kept. ($(short "$IN/refused.txt"))"
  exit 0
fi
[ "$outcome" = success ] || { failed "Claude stopped before it was done (${outcome:-no answer})."; exit 0; }

if [ "$CMD" = plan ]; then
  note="$IN/notes/plan.md"
  [ -f "$note" ] && [ ! -L "$note" ] && [ -s "$note" ] || { failed "Claude did not write a plan."; exit 0; }
  if [ -s "$IN/change.patch" ]; then failed "Claude changed files while planning, so nothing was kept."; exit 0; fi
  fit_plan "$note" "$BODY.plan"
  { marker "done"
    echo "**Claude's plan for this change.** Claude could only read the website's code and write this note; the workflow posted it. Pick an option in AI Builder."
    echo
    quoted "$BODY.plan"
  } > "$BODY"
  rm -f "$BODY.plan"
  post
  exit 0
fi

# ---------- build, update, fix: save the change ----------
[[ "${SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "Bad commit"
[[ "${BASE:-}" =~ ^[A-Za-z0-9._/-]{1,100}$ && "$BASE" != *..* ]] || die "Bad default branch name"
if [ "$CMD" = build ]; then
  [[ "${STAMP:-}" =~ ^[0-9]{8}-[0-9]{6}$ ]] || die "Bad stamp"
  BRANCH="claude/issue-$ISSUE-$STAMP"
else
  [[ "${BRANCH:-}" =~ ^claude/[A-Za-z0-9._/-]{1,150}$ && "$BRANCH" != *..* ]] || die "Not a claude/ branch"
fi
[ "$BRANCH" != "$BASE" ] || die "Never the default branch"
patch="$IN/change.patch"
[ -f "$patch" ] && [ ! -L "$patch" ] || { failed "Claude's change did not reach the save step."; exit 0; }
summary="$IN/notes/summary.md"
have_summary=no; [ -f "$summary" ] && [ ! -L "$summary" ] && [ -s "$summary" ] && have_summary=yes
says() {
  echo "### What Claude says"
  if [ "$have_summary" = yes ]; then quoted "$summary"; else echo "> Claude did not write a note."; fi
}
if [ ! -s "$patch" ]; then
  # Nothing changed. The fixer hands over to a person (it reads nochange); an update says so.
  : > "$TMP/ai-builder-nochange"
  case "$CMD" in
    build) failed "Claude finished but did not change any files." ;;
    fix) { marker failed; echo "**Claude changed nothing this time.**"; echo; says; } > "$BODY"; post ;;
    update) { marker "done"; echo "**Claude looked at the feedback and changed nothing.**"; echo; says; } > "$BODY"; post ;;
  esac
  exit 0
fi

AUTH_FOR() { printf 'AUTHORIZATION: basic %s' "$(printf 'x-access-token:%s' "$1" | base64 | tr -d '\n')"; }
echo "::add-mask::$GH_TOKEN"
PUSH="${PUSH_TOKEN:-}"; if [ -n "$PUSH" ]; then echo "::add-mask::$PUSH"; else PUSH="$GH_TOKEN"; fi
WORK=$(mktemp -d "$TMP/ai-builder-save.XXXXXX")
g() { git -C "$WORK" -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
g init -q
g remote add origin "${GITHUB_SERVER_URL:-https://github.com}/$REPO.git"
export GIT_AUTHOR_NAME="github-actions[bot]" GIT_COMMITTER_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com" GIT_COMMITTER_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
g -c http.extraheader="$(AUTH_FOR "$GH_TOKEN")" fetch -q --depth=1 origin "$SHA"
remote_head() { g -c http.extraheader="$(AUTH_FOR "$GH_TOKEN")" ls-remote origin "refs/heads/$BRANCH" | cut -f1; }
now=$(remote_head)
if [ "$CMD" = build ]; then
  [ -z "$now" ] || { failed "A branch of that name already exists, so nothing was overwritten."; exit 0; }
else
  [ "$now" = "$SHA" ] || { failed "The change moved on while Claude worked (someone pushed to it), so this try was not saved. Ask again."; exit 0; }
fi
g checkout -q -B "$BRANCH" FETCH_HEAD
if ! changed=$(cd "$WORK" && bash "$KIT/kit-change.sh" apply change "$patch" 2>"$WORK.err"); then
  failed "The change touched a file it may not change, or did not fit this version, so nothing was kept. ($(short "$WORK.err"))"
  exit 0
fi
[ -n "$changed" ] || { failed "Claude did not change any files."; exit 0; }
extra=$(g diff --cached --name-only | grep -v -x -F -f <(printf '%s\n' "$changed") || true)
[ -z "$extra" ] || die "Unexpected files staged: $extra"

# The test job's results: only lines of the shape below are shown; Verified comes from the job too.
CHECK_RE='^- (✅|❌|⬜) [^<>@`]{1,300}$'
verified="none (the tests did not run)"
if [ -f "${TESTS:-/nonexistent}/verified.txt" ] && [ ! -L "$TESTS/verified.txt" ]; then
  v=$(head -n1 "$TESTS/verified.txt" | LC_ALL=C sed 's/\xe2\x80[\xa8\xa9]\|\xc2\x85//g' | tr -d '\r\v\f<>@`' | head -c 300)
  [ -n "$v" ] && verified="$v"
fi
case "$CMD" in
  build) title="AI Builder: change for task #$ISSUE" ;;
  update) title="AI Builder: update from feedback on #$PR" ;;
  fix) title="AI Builder fixer: try ${TRY:-?} on #$PR" ;;
esac
g commit -q -m "$title" -m "Made by Claude in a read-only job. Checked and saved by the workflow, not by Claude." -m "Verified: $verified"
# Never a force push: for update and fix, git refuses if the branch moved since the check above.
g -c http.extraheader="$(AUTH_FOR "$PUSH")" push -q origin "HEAD:refs/heads/$BRANCH"
new_sha=$(g rev-parse HEAD)

pr_line=""
if [ "$CMD" = build ]; then
  owner="${REPO%%/*}"
  pr=$(gh api "repos/$REPO/pulls?state=all&head=$owner:$BRANCH" --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -z "$pr" ]; then
    gh api "repos/$REPO/issues/$ISSUE" > "$TMP/issue.json"
    ititle=$(jq -r '.title' "$TMP/issue.json" | tr -d '\r\n' | head -c 200 | plain)
    # The request as the AI Builder quoted it, quoted again line by line after the line breaks are
    # made plain, so no part of it can stand as a line of its own in the pull request.
    request=$(jq -r '.body // ""' "$TMP/issue.json" | tr -d '\r' | awk '/^<!-- request -->$/{on=1; next} /^<!-- \/request -->$/{on=0} on' | head -c 4000 | plain | sed -E 's/^> ?//; s/^/> /')
    settings=""; jq -r '.body // ""' "$TMP/issue.json" | grep -q '^\*\*Company settings (from the AI Builder)' && settings="Company settings were attached to this request. They are shown in full in the task (#$ISSUE)."
    jq -n --arg t "AI Builder: $ititle" --arg h "$BRANCH" --arg b "$BASE" \
      --arg body "$(printf 'Closes #%s\n\nRequested through the AI Builder. Built by Claude in a read-only job; checked and saved by the workflow.\n\n**What was asked:**\n\n%s\n\n%s' "$ISSUE" "$request" "$settings")" \
      '{title: $t, head: $h, base: $b, body: $body}' > "$TMP/pr.json"
    # Opened with Claude's app token so the checks start; the job's own token as a fallback.
    pr=$(GH_TOKEN="$PUSH" gh api "repos/$REPO/pulls" --method POST --input "$TMP/pr.json" --jq '.number' 2>/dev/null || true)
    [ -n "$pr" ] || [ "$PUSH" = "$GH_TOKEN" ] || pr=$(gh api "repos/$REPO/pulls" --method POST --input "$TMP/pr.json" --jq '.number' 2>/dev/null || true)
  fi
  if [ -n "$pr" ]; then
    gh api "repos/$REPO/issues/$pr/labels" --method POST -f 'labels[]=ai-builder' >/dev/null 2>&1 || true
    pr_line="Pull request: #$pr"
  else
    pr_line="The pull request could not be opened here; AI Builder opens it when it next looks at this task."
  fi
fi

{ marker "done"
  case "$CMD" in
    build) echo "**Claude made the change.** Claude could only read the website's code and write the allowed files; the workflow checked the change, ran the tests, saved it and posted this." ;;
    update) echo "**Claude updated the change with the feedback.** The workflow checked it, ran the tests and saved it." ;;
    fix) echo "**Claude's fix (try ${TRY:-?} of 3).** The workflow checked it, ran the tests and saved it. To undo it: git revert $new_sha" ;;
  esac
  echo
  echo "Branch: $BRANCH"
  echo "Commit: $new_sha"
  [ -z "$pr_line" ] || echo "$pr_line"
  echo
  says
  echo
  echo "### Tests the workflow ran"
  echo "A hint only: the site's own code ran these tests, in a locked-down job. The checks on the pull request, and the engineer, are the real gate."
  echo
  if [ -f "${TESTS:-/nonexistent}/results.md" ] && [ ! -L "$TESTS/results.md" ] && grep -qE "$CHECK_RE" "$TESTS/results.md"; then
    grep -E "$CHECK_RE" "$TESTS/results.md" | head -14
  else
    echo "- ⬜ The tests did not run, so nothing was checked automatically. The checks on the pull request still run."
  fi
  echo
  echo "Verified: $verified"
} > "$BODY"
post
