#!/usr/bin/env bash
# The change Claude made, as a patch. Used by the AI Builder workflows (claude.yml, the fixer).
# Only the workflow runs this, never Claude (Claude has no Bash). Each job runs its OWN copy, taken
# from the commit the workflow runs on (the default branch) into $RUNNER_TEMP before Claude starts,
# never a copy from a working tree Claude has written in.
#
#   kit-change.sh rules <plan|change|review>          the Edit rules Claude is allowed (one line, comma separated)
#   kit-change.sh pack  <plan|change|review> <out>    in the Claude job's working copy, after Claude stopped
#   kit-change.sh apply change <patch file>           in a clean checkout of the same commit
#
# Needs KIT_JSON: the path of the trusted copy of .github/ai-builder/kit.json. Its "editable" list
# names what Claude may change: "public/" (a folder, everything under it) or "index.html" (one file).
#
# pack:  stages everything in the working copy, refuses ANY path outside the allow list, and writes
#        <out>/change.patch (the site change only), <out>/changed.txt and <out>/notes/ (Claude's
#        plan.md, summary.md, verify.txt or review.md, kept apart from the patch).
# apply: applies a patch with git apply --index and checks the result again with the same list.
#
# Never, whatever kit.json says: .github/, .claude/, .mcp.json, CLAUDE.md, REVIEW.md, CODEOWNERS,
# package files, .npmrc, node_modules/, .gitattributes, .gitmodules, .gitignore, any path with a .git
# folder in it, links, submodules, files that can be run (only mode 100644), more than 40 files,
# a file over 1 MB or a patch over 4 MB. Anything refused stops the whole change: nothing is half saved.
set -euo pipefail
export LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
G=(git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.quotepath=off -c core.autocrlf=false -c core.symlinks=true)
MAX_FILES=40 MAX_FILE=1048576 MAX_PATCH=4194304 MAX_NOTE=60000
NOTES=.ai-builder/run

die() { echo "::error::$*" >&2; exit 1; }
CMD="${1:-}"; MODE="${2:-}"; ARG="${3:-}"
[[ "$MODE" == plan || "$MODE" == change || "$MODE" == review ]] || die "The mode must be plan, change or review."

# ---------- What Claude may change (from kit.json) ----------
[ -f "${KIT_JSON:-}" ] || die "No kit.json (KIT_JSON)."
# A path no change may touch, in any mode, in any folder (any case for .git).
protected() {
  local p="/${1}/" l="/${1,,}/"
  [[ "$l" == */.git/* ]] && return 0
  [[ "$p" =~ /(\.github|\.claude|node_modules)/ ]] && return 0
  [[ "$p" =~ /(CLAUDE\.md|CLAUDE\.local\.md|\.mcp\.json|REVIEW\.md|CODEOWNERS|package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|\.npmrc|\.yarnrc|\.yarnrc\.yml|\.gitattributes|\.gitmodules|\.gitignore)/$ ]] && return 0
  [[ "$1" == .ai-builder || "$1" == .ai-builder/* ]] && return 0
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

"${G[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git working copy."

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
  *) die "Usage: kit-change.sh rules|pack|apply <plan|change|review> [folder|patch]" ;;
esac
