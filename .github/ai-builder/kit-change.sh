#!/usr/bin/env bash
# The change Claude made, as a patch. Used by the AI Builder workflows (claude.yml, the fixer, the
# review and the guard). Only the workflow runs this, never Claude (Claude has no Bash). Each job runs
# its OWN copy, taken from the commit the workflow runs on (the default branch) into $RUNNER_TEMP
# before Claude starts, never a copy from a working tree Claude has written in.
#
#   kit-change.sh rules  <plan|change|review>          the Edit rules Claude is allowed (one line, comma separated)
#   kit-change.sh settle <plan|change|review> <saved>  after Claude stopped, before pack (see below)
#   kit-change.sh pack   <plan|change|review> <out>    in the Claude job's working copy, after settle
#   kit-change.sh apply  change <patch file>           in a clean checkout of the same commit
#   kit-change.sh guard  <file with one path per line> prints the protected paths in it; fails if any
#
# Needs KIT_JSON: the path of the trusted copy of .github/ai-builder/kit.json. Its "editable" list
# names what Claude may change: "public/" (a folder, everything under it) or "index.html" (one file).
# Its "guard" list names extra files no change may touch (the site's test scripts, its server).
#
# settle: <saved> is the copy of .git/config made before Claude started. If .git/config changed in
#        any way but the Claude action's own lines (git user, origin URL, the checkout's auth header,
#        the action's credential helper), it refuses. Then it puts the saved copy back, and puts back
#        the files the Claude action itself resets from the base branch on pull requests (.claude/,
#        CLAUDE.md, AGENTS.md, .mcp.json, .npmrc, package.json and so on: ACTION_PATHS below) to
#        what this commit has, and removes the action's .claude-pr/ copy. Claude may never change
#        those files anyway, so nothing of Claude's is lost.
# pack:  stages everything in the working copy, refuses ANY path outside the allow list, and writes
#        <out>/change.patch (the site change only), <out>/changed.txt and <out>/notes/ (Claude's
#        plan.md, summary.md, verify.txt or review.md, kept apart from the patch).
# apply: applies a patch with git apply --index and checks the result again with the same list.
# guard: the one list of protected paths, also used by the guard workflow and the fixer.
#
# Never, whatever kit.json says, at any depth and in any letter case: .github/, .claude/, .husky/,
# node_modules/, CLAUDE.md, CLAUDE.local.md, AGENTS.md, .mcp.json, .claude.json, .ripgreprc,
# REVIEW.md, CODEOWNERS, package files and lock files, .npmrc, .yarnrc, .pnpmfile.cjs, bunfig.toml, .gitattributes,
# .gitmodules, .gitignore, any path with a .git folder in it; .ai-builder/ at the top; the "guard"
# list. Also never links, submodules, files that can be run (only mode 100644), more than 40 files,
# a file over 1 MB or a patch over 4 MB. Anything refused stops the whole change: nothing is half saved.
set -euo pipefail
export LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
G=(git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.quotepath=off -c core.autocrlf=false -c core.symlinks=true)
MAX_FILES=40 MAX_FILE=1048576 MAX_PATCH=4194304 MAX_NOTE=60000
NOTES=.ai-builder/run

die() { echo "::error::$*" >&2; exit 1; }
CMD="${1:-}"
if [ "$CMD" = guard ]; then MODE=change; ARG="${2:-}"; else MODE="${2:-}"; ARG="${3:-}"; fi
[[ "$MODE" == plan || "$MODE" == change || "$MODE" == review ]] || die "The mode must be plan, change or review."

# ---------- What Claude may change (from kit.json) ----------
[ -f "${KIT_JSON:-}" ] || die "No kit.json (KIT_JSON)."
# The site's own extra protected paths, from kit.json ("guard"): "scripts/" (a folder) or "server.js".
GUARD=()
while IFS= read -r e; do
  [ -n "$e" ] || continue
  [[ "$e" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]{0,150}$ && "$e" != *..* ]] || die "kit.json: guard entry \"$e\" is not a plain path."
  GUARD+=("${e,,}")
done < <(jq -r '(.guard // []) | if type == "array" then .[] else error("guard must be a list") end | tostring' "$KIT_JSON")
# A path no change may touch, in any mode, at any depth, in any letter case (the same list for the
# guard workflow, the fixer and the build: see the top of this file).
protected() {
  local l="/${1,,}/" e
  [[ "$l" == */.git/* ]] && return 0
  [[ "$l" =~ /(\.github|\.claude|\.husky|node_modules)/ ]] && return 0
  [[ "$l" =~ /(claude\.md|claude\.local\.md|agents\.md|\.mcp\.json|\.claude\.json|\.ripgreprc|review\.md|codeowners|package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|bunfig\.toml|\.npmrc|\.yarnrc|\.yarnrc\.yml|\.pnpmfile\.cjs|\.gitattributes|\.gitmodules|\.gitignore)/$ ]] && return 0
  [[ "$l" == /.ai-builder/* ]] && return 0
  for e in "${GUARD[@]}"; do
    if [[ "$e" == */ ]]; then [[ "${l#/}" == "$e"* ]] && return 0
    else [[ "$l" == "/$e/" ]] && return 0; fi
  done
  return 1
}
EDITABLE=()
while IFS= read -r e; do
  [ -n "$e" ] || continue
  [[ "$e" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,80}(/[A-Za-z0-9_][A-Za-z0-9_.-]{0,80}){0,5}/?$ ]] || die "kit.json: \"$e\" is not a plain folder or file name."
  [[ "$e" != *..* ]] || die "kit.json: \"$e\" may not hold \"..\"."
  protected "${e%/}" && die "kit.json: \"$e\" is a protected path and can never be editable."
  EDITABLE+=("$e")
done < <(jq -r '(.editable // []) | if type == "array" then .[] else error("editable must be a list") end | tostring' "$KIT_JSON")
[ "${#EDITABLE[@]}" -ge 1 ] && [ "${#EDITABLE[@]}" -le 10 ] || die "kit.json: \"editable\" must list 1 to 10 folders or files."

# A site path Claude may change in change mode.
site_path() {
  local p="$1" e
  protected "$p" && return 1
  [[ "$p" =~ ^[A-Za-z0-9_./@+\ -]{1,200}$ && "$p" != *..* && "$p" != /* ]] || return 1
  for e in "${EDITABLE[@]}"; do
    if [[ "$e" == */ ]]; then [[ "$p" == "$e"* ]] && return 0
    else [[ "$p" == "$e" ]] && return 0; fi
  done
  return 1
}
# Claude's notes for this mode (never part of the patch). request.md and context files are the workflow's.
note_path() {
  case "$MODE:$1" in
    "plan:$NOTES/plan.md"|"change:$NOTES/summary.md"|"change:$NOTES/verify.txt"|"review:$NOTES/review.md") return 0 ;;
  esac
  return 1
}
workflow_note() { [[ "$1" == "$NOTES/request.md" || "$1" == "$NOTES/diff.patch" ]]; }

if [ "$CMD" = rules ]; then
  case "$MODE" in
    plan) echo "Edit(./$NOTES/plan.md)" ;;
    review) echo "Edit(./$NOTES/review.md)" ;;
    change)
      out="Edit(./$NOTES/summary.md),Edit(./$NOTES/verify.txt)"
      for e in "${EDITABLE[@]}"; do
        if [[ "$e" == */ ]]; then out+=",Edit(./${e}**)"; else out+=",Edit(./$e)"; fi
      done
      echo "$out" ;;
  esac
  exit 0
fi

if [ "$CMD" = guard ]; then
  [ -f "$ARG" ] && [ ! -L "$ARG" ] || die "No list of files."
  found=0
  while IFS= read -r p || [ -n "$p" ]; do
    p="${p%$'\r'}"
    [ -n "$p" ] || continue
    if protected "$p"; then
      found=$((found + 1))
      [ "$found" -le 20 ] && printf '%s\n' "$p"
    fi
  done < "$ARG"
  [ "$found" -eq 0 ]
  exit
fi

"${G[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git working copy."

# ---------- settle: the git settings, and the files the Claude action resets ----------
# The Claude action (anthropics/claude-code-action v1.0.290) on a pull request deletes these and puts
# back the base branch's version (src/github/operations/restore-config.ts SENSITIVE_PATHS); for a
# pull request a bot opened, also the npm and Bun settings (tool-config.ts: in any folder, and only
# the command fields of package.json). It leaves them changed in the working copy.
ACTION_PATHS=(.claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md AGENTS.md .husky .npmrc bunfig.toml node_modules package.json)
# What the action itself writes to .git/config (src/github/operations/git-config.ts): the git user,
# the origin URL (with or without a token), the checkout's auth header it removes, and the
# credential helper it adds when allowed_bots is set. As `git config --list` prints them: the exact
# keys (letter case too), each with at most one value.
ACTION_CONFIG='^(user\.name|user\.email|remote\.origin\.url|http\.https://github\.com/\.extraheader|credential\.https://github\.com\.helper)='
# Puts one path back to what HEAD has (or removes it, when HEAD has none), if it differs.
back() {
  local p="$1"
  [ -n "$("${G[@]}" --literal-pathspecs status --porcelain --untracked-files=all --ignored=no -- "$p" 2>/dev/null)" ] || return 0
  rm -rf -- "$p"
  if "${G[@]}" cat-file -e "HEAD:$p" 2>/dev/null; then "${G[@]}" --literal-pathspecs checkout -q HEAD -- "$p"; fi
  echo "Put back as this commit has it (the Claude action had reset it): $p"
}
settle() {
  local saved="$1" old new other twice p
  [ -f "$saved" ] && [ ! -L "$saved" ] || die "No saved copy of the git settings."
  [ -f .git/config ] && [ ! -L .git/config ] || die "Refused: the git settings (.git/config) changed while Claude worked"
  if ! cmp -s "$saved" .git/config; then
    old=$(git config --file "$saved" --list) || die "The saved git settings could not be read."
    new=$(git config --file .git/config --list 2>/dev/null) || die "Refused: the git settings (.git/config) changed while Claude worked"
    other=$(diff <(printf '%s\n' "$old" | sort) <(printf '%s\n' "$new" | sort) | sed -n 's/^[<>] //p' | grep -vE "$ACTION_CONFIG" || true)
    [ -z "$other" ] || die "Refused: the git settings (.git/config) changed while Claude worked"
    twice=$(printf '%s\n' "$new" | grep -E "$ACTION_CONFIG" | cut -d= -f1 | sort | uniq -d || true)
    [ -z "$twice" ] || die "Refused: the git settings (.git/config) changed while Claude worked"
  fi
  cp "$saved" .git/config
  for p in "${ACTION_PATHS[@]}"; do back "$p"; done
  # The same names in folders below (npm and Bun read them there too), when anything changed them.
  while IFS= read -r -d '' p; do
    case "/$p" in
      */node_modules/*) p="/$p"; p="${p%%/node_modules/*}"; p="${p#/}"; back "${p:+$p/}node_modules" ;;
      */.npmrc|*/bunfig.toml|*/package.json) back "$p" ;;
    esac
  done < <("${G[@]}" diff --name-only -z HEAD -- 2>/dev/null; "${G[@]}" ls-files -z --others --exclude-standard 2>/dev/null)
  rm -rf .claude-pr
}
if [ "$CMD" = settle ]; then settle "$ARG"; exit 0; fi

# Checks the staged change against HEAD. $1 = notes allowed (yes|no). Prints the site paths that changed.
check_staged() {
  local notes="$1" count=0 meta path oldmode newmode status
  local -a paths=()
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    # ":<old mode> <new mode> <old sha> <new sha> <status>"
    read -r oldmode newmode _ _ status <<<"${meta#:}"
    if [[ "$path" == "$NOTES"/* ]]; then
      [ "$notes" = yes ] || die "Refused: $path (notes never go in the change)"
      workflow_note "$path" && continue
      note_path "$path" || die "Refused: $path (only the notes for this step may be written)"
      [[ "$status" == A || "$status" == M ]] || die "Refused: $path ($status)"
      [ "$newmode" = 100644 ] || die "Refused: $path (not a plain file)"
      continue
    fi
    [ "$MODE" = change ] || die "Refused: $path (this step changes no file of the site)"
    site_path "$path" || die "Refused: $path (outside the files Claude may change)"
    case "$status" in
      A|M) [ "$newmode" = 100644 ] || die "Refused: $path (not a plain file: mode $newmode)" ;;
      D) [ "$oldmode" = 100644 ] || die "Refused: $path (deleting something that is not a plain file)" ;;
      *) die "Refused: $path (change of type $status)" ;;
    esac
    if [ "$status" != D ]; then
      local size
      size=$("${G[@]}" cat-file -s ":$path")
      [ "$size" -le "$MAX_FILE" ] || die "Refused: $path is over 1 MB"
    fi
    count=$((count + 1))
    [ "$count" -le "$MAX_FILES" ] || die "Refused: more than $MAX_FILES files changed"
    paths+=("$path")
  done < <("${G[@]}" diff --cached --no-renames --no-ext-diff --no-textconv --raw -z HEAD)
  [ "${#paths[@]}" -eq 0 ] || printf '%s\n' "${paths[@]}"
}

case "$CMD" in
  pack)
    OUT="$ARG"
    [[ "$OUT" = /* ]] || die "The out folder must be an absolute path."
    rm -rf "$OUT"; mkdir -p "$OUT/notes"
    "${G[@]}" add -A -- .
    changed=$(check_staged yes)
    printf '%s' "$changed" > "$OUT/changed.txt"
    "${G[@]}" diff --cached --binary --no-renames --no-ext-diff --no-textconv --full-index HEAD -- . ":(exclude)$NOTES" > "$OUT/change.patch"
    [ "$(stat -c%s "$OUT/change.patch")" -le "$MAX_PATCH" ] || die "Refused: the change is over 4 MB"
    for n in plan.md summary.md verify.txt review.md; do
      f="$NOTES/$n"
      if [ -f "$f" ] && [ ! -L "$f" ] && note_path "$f"; then head -c "$MAX_NOTE" "$f" > "$OUT/notes/$n"; fi
    done
    echo "Packed $(printf '%s' "$changed" | grep -c . || true) changed file(s) for $MODE."
    ;;
  apply)
    PATCH="$ARG"
    [ "$MODE" = change ] || die "Only a change is applied."
    [ -f "$PATCH" ] && [ ! -L "$PATCH" ] || die "No patch file."
    [ "$(stat -c%s "$PATCH")" -le "$MAX_PATCH" ] || die "Refused: the change is over 4 MB"
    "${G[@]}" diff --quiet HEAD -- && "${G[@]}" diff --cached --quiet HEAD -- || die "The checkout is not clean."
    if [ -s "$PATCH" ]; then
      # No path in the patch may name a .git folder, however it is written…
      if grep -qaiE '^(diff --git |--- |\+\+\+ |rename (from|to) |copy (from|to) )(.*/)?"?\.git(/|"|$| )' "$PATCH"; then die "Refused: a path in the patch names a .git folder"; fi
      # …then the paths as the patch names them, before anything is written…
      list=$(mktemp)
      "${G[@]}" apply --numstat -z "$PATCH" > "$list" 2>/dev/null || die "The patch could not be read."
      while IFS= read -r -d '' line; do
        p="${line#*$'\t'}"; p="${p#*$'\t'}"
        [[ "$p" == "$NOTES"/* ]] && die "Refused: $p (notes never go in the change)"
        site_path "$p" || die "Refused: $p (outside the files Claude may change)"
      done < "$list"
      rm -f "$list"
      # …then applied to the index and the files, and checked again as git now sees it.
      "${G[@]}" apply --index --whitespace=nowarn "$PATCH" || die "The patch does not apply to this commit."
    fi
    check_staged no
    ;;
  *) die "Usage: kit-change.sh rules|settle|pack|apply <plan|change|review> [saved|folder|patch], or guard <file>" ;;
esac
