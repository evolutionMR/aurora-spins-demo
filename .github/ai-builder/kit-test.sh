#!/usr/bin/env bash
# The test job: no AI, no secrets, a read-only token. Runs the site's own tests and its verify step
# on a clean checkout with Claude's patch applied, and writes what happened for the save job.
# The commands come from kit.json on the default branch (an engineer's file), never from Claude.
# Claude only suggests which pages to look at (.ai-builder/run/verify.txt); each page and text is
# checked here and passed as its own argument, never through a shell.
#
#   kit-test.sh <claude artifact folder> <out folder>       (run in the checkout, from its root)
#
# Writes <out>/results.md (lines "- ✅|❌|⬜ <plain words>") and <out>/verified.txt (one line for the
# commit's "Verified:" line). Needs KIT_JSON and KIT (the folder with kit-change.sh).
# Note: the site's tests may run code Claude changed (any CI does). That is why this job has no
# secret and cannot write anywhere, and why its results are a hint: the required checks on the
# pull request are the real gate.
set -uo pipefail
export LC_ALL=C.UTF-8
IN="${1:-}"; OUT="${2:-}"
die() { echo "::error::$*" >&2; exit 1; }
[ -d "$IN" ] && [[ "$OUT" = /* ]] || die "Usage: kit-test.sh <in> <out>"
mkdir -p "$OUT"
R="$OUT/results.md"; : > "$R"
line() { printf -- '- %s %s\n' "$1" "$(printf '%s' "$2" | tr -d '\r\n<>@`' | head -c 280)" >> "$R"; }
verified=()

if [ -f "$IN/refused.txt" ] || [ ! -s "$IN/change.patch" ]; then
  echo "none (there was no change to test)" > "$OUT/verified.txt"; exit 0
fi
if ! bash "$KIT/kit-change.sh" apply change "$IN/change.patch" > "$OUT/changed.txt"; then
  line "❌" "The change could not be applied to a clean copy, so nothing was tested."
  echo "none (the change could not be applied)" > "$OUT/verified.txt"; exit 0
fi

cfg() { jq -r --arg k "$1" '.[$k] // "" | if type == "string" then . else "" end' "$KIT_JSON"; }
run() { # run <label> <command> [args…]: the command is from kit.json; args are passed as they are.
  local label="$1" cmd="$2"; shift 2
  echo "::group::$label"
  timeout 600 bash -c "$cmd \"\$@\"" kit "$@" 2>&1 | tee "$OUT/$label.log" | tail -n 200
  local rc=${PIPESTATUS[0]}
  echo "::endgroup::"
  return "$rc"
}

install=$(cfg install); test=$(cfg test); verify=$(cfg verify); pw=$(cfg playwright)
if [ -n "$install" ] && ! run install "$install"; then
  line "❌" "Installing the site's packages failed."
fi
if [ -n "$test" ]; then
  if run test "$test"; then line "✅" "The site's automatic tests passed."; verified+=("$test passed")
  else line "❌" "The site's automatic tests failed."; verified+=("$test failed"); fi
fi

# The pages Claude asked to look at: "/path" then texts that must show, one page per line, texts
# after " | ". Only plain paths and short plain texts; at most 5 pages and 5 texts each.
args=(); pages=()
if [ -n "$verify" ] && [ -f "$IN/notes/verify.txt" ] && [ ! -L "$IN/notes/verify.txt" ]; then
  while IFS= read -r l; do
    [ "${#pages[@]}" -lt 5 ] || break
    l="${l%$'\r'}"
    page="${l%% | *}"; page="${page%% }"
    [[ "$page" =~ ^/[A-Za-z0-9._~/?=\&%-]{0,200}$ && "$page" != *..* ]] || continue
    pages+=("$page"); args+=("$page")
    rest="${l#"$page"}"; n=0
    while [[ "$rest" == " | "* ]] && [ "$n" -lt 5 ]; do
      rest="${rest# | }"; t="${rest%% | *}"; rest="${rest#"$t"}"
      if [[ "$t" =~ ^[^\<\>@\`$\\]{1,120}$ && "$t" != -* && "$t" != /* ]]; then args+=("$t"); n=$((n + 1)); fi
    done
  done < <(head -c 4000 "$IN/notes/verify.txt")
fi
if [ "${#pages[@]}" -eq 0 ]; then pages=("/"); args=("/"); fi
if [ -n "$verify" ]; then
  if [ -n "$pw" ] && [[ "$pw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Pinned Playwright, installed outside the checkout, so nothing in it changes what is installed.
    p="$RUNNER_TEMP/pw"; mkdir -p "$p"
    if (cd "$p" && npm i --no-save --no-audit --no-fund --prefix "$p" "playwright@$pw" >/dev/null && "$p/node_modules/.bin/playwright" install --with-deps chromium >/dev/null); then
      export NODE_PATH="$p/node_modules"
    else line "⬜" "Phone and laptop look not checked: the browser could not be installed."; fi
  fi
  run verify "$verify" "${args[@]}"; rc=$?
  # The verify step prints one line per check, starting with ✅, ❌ or ⬜. Keep up to 12 of them.
  grep -E '^(✅|❌|⬜) ' "$OUT/verify.log" 2>/dev/null | head -12 | while IFS= read -r v; do line "${v%% *}" "${v#* }"; done
  sizes=""; [ -n "${NODE_PATH:-}" ] && sizes=" at 390px and 1280px"
  if [ "$rc" -eq 0 ]; then verified+=("$verify ${pages[*]}$sizes")
  else verified+=("$verify ${pages[*]}$sizes found problems"); fi
fi
if [ "${#verified[@]}" -eq 0 ]; then echo "none (kit.json names no test or verify command)" > "$OUT/verified.txt"
else (IFS=';'; printf '%s\n' "${verified[*]}" | sed 's/;/; /g') > "$OUT/verified.txt"; fi
cat "$R"
exit 0
