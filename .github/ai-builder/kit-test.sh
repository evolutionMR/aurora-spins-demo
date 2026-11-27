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
#
# The site's install, test and verify commands may run code Claude changed (any CI does). So in the
# workflows (KIT_RUN_AS set) they run as that separate user, made here: no sudo, not in the runner's
# groups (no docker), cannot read the runner's home folder (the runner's own files and this job's
# temp folder), cannot reach the cloud metadata addresses, in its own copy of the checkout, with a
# clean environment: no ACTIONS_* (no runtime token, no cache address), no GITHUB_TOKEN or GH_TOKEN,
# no NODE_OPTIONS, and GITHUB_ENV, GITHUB_PATH and GITHUB_OUTPUT pointed at /dev/null, so nothing it
# does reaches a later step. Its processes are killed after each command. Nothing the site's code
# wrote is run afterwards: only its printed lines are read, as text.
# (A container with no network would isolate more, but the install and the browser need the network,
# and the image could not be pinned like the actions are; a plain user works on every hosted runner.)
# Without KIT_RUN_AS (the AI Builder's own tests) the commands run here, still with the clean environment.
# The results are a hint for the person: the required checks on the pull request are the real gate.
set -uo pipefail
export LC_ALL=C.UTF-8
IN="${1:-}"; OUT="${2:-}"
die() { echo "::error::$*" >&2; exit 1; }
[ -d "$IN" ] && [[ "$OUT" = /* ]] || die "Usage: kit-test.sh <in> <out>"
RUN_AS="${KIT_RUN_AS:-}"
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "$RUN_AS" ]; then die "KIT_RUN_AS is not set: the site's commands never run as the runner's own user."; fi
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
install=$(cfg install); test=$(cfg test); verify=$(cfg verify); pw=$(cfg playwright)

# Pinned Playwright, installed before any of the site's code runs, outside the checkout (so nothing
# in it changes what is installed), where the site's user can read it but not change it.
pw_path=""
if [ -n "$verify" ] && [ -n "$pw" ] && [[ "$pw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  if [ -n "$RUN_AS" ]; then p=/opt/ai-builder-playwright; else p="${RUNNER_TEMP:-$OUT}/pw"; fi
  if { [ -z "$RUN_AS" ] || { sudo -n rm -rf "$p" && sudo -n mkdir -p "$p" && sudo -n chown "$(id -u):$(id -g)" "$p"; }; } \
    && (cd "$p" && npm i --no-save --no-audit --no-fund --prefix "$p" "playwright@$pw" >/dev/null \
      && PLAYWRIGHT_BROWSERS_PATH="$p/browsers" "$p/node_modules/.bin/playwright" install --with-deps chromium >/dev/null) \
    && { [ -z "$RUN_AS" ] || { sudo -n chown -R root:root "$p" && sudo -n chmod -R a+rX,go-w "$p"; }; }; then
    pw_path="$p"
  else line "⬜" "Phone and laptop look not checked: the browser could not be installed."; fi
fi

# Where and as whom the site's commands run.
node_bin=$(command -v node 2>/dev/null || true)
CLEAN_PATH="${node_bin:+$(dirname "$node_bin"):}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if [ -n "$RUN_AS" ]; then
  [[ "$RUN_AS" =~ ^[a-z][a-z0-9-]{2,30}$ ]] || die "KIT_RUN_AS is not a plain user name."
  [ "$RUN_AS" != "$(id -un)" ] && [ "$RUN_AS" != root ] || die "KIT_RUN_AS must be a separate user."
  id -u "$RUN_AS" >/dev/null 2>&1 || sudo -n useradd --create-home --home-dir "/home/$RUN_AS" --shell /bin/bash --user-group "$RUN_AS" \
    || die "Could not make the user the site's tests run as."
  # Never in a group that gives power (sudo, docker, the runner's own group…).
  extra=$(id -nG "$RUN_AS" | tr ' ' '\n' | grep -vxF "$RUN_AS" || true)
  [ -z "$extra" ] || die "The user the site's tests run as is in other groups: $(printf '%s' "$extra" | tr '\n' ' ')"
  # The runner's home holds this job's temp folder, the runner's own files and its settings.
  sudo -n chmod o-rwx "$HOME" || die "Could not close the runner's home folder."
  # No cloud metadata service for that user (best effort: the hosted runners have iptables).
  for addr in 169.254.0.0/16 168.63.129.16/32; do
    sudo -n iptables -I OUTPUT -m owner --uid-owner "$RUN_AS" -d "$addr" -j REJECT 2>/dev/null \
      || echo "::warning::Could not block $addr for the test user."
  done
  SITE="/home/$RUN_AS/site"; SITE_HOME="/home/$RUN_AS"
  sudo -n rm -rf "$SITE" && sudo -n mkdir -p "$SITE" && sudo -n cp -a . "$SITE/" && sudo -n chown -R "$RUN_AS:$RUN_AS" "$SITE_HOME" \
    || die "Could not copy the site for the test user."
  # The checks that matter, checked for real: no sudo, and the runner's home cannot be read.
  if sudo -n -u "$RUN_AS" -- sudo -n true 2>/dev/null; then die "The test user can use sudo."; fi
  if sudo -n -u "$RUN_AS" -- ls "$HOME" >/dev/null 2>&1; then die "The test user can read the runner's home folder."; fi
else
  SITE="$PWD"; SITE_HOME=$(mktemp -d)
fi
# as_site <command> [args…]: as the site's user, in its copy, with a clean environment. It ends with
# exec, so run it only in a background subshell (run below): its pid is then the command's own.
as_site() {
  local env=(env -i "PATH=$CLEAN_PATH" "HOME=$SITE_HOME" "LANG=C.UTF-8" "LC_ALL=C.UTF-8" "CI=true" "TERM=dumb"
    "GITHUB_ENV=/dev/null" "GITHUB_PATH=/dev/null" "GITHUB_OUTPUT=/dev/null" "GITHUB_STATE=/dev/null" "GITHUB_STEP_SUMMARY=/dev/null"
    "KIT_SITE=$SITE")
  [ -z "$pw_path" ] || env+=("NODE_PATH=$pw_path/node_modules" "PLAYWRIGHT_BROWSERS_PATH=$pw_path/browsers")
  if [ -n "$RUN_AS" ]; then cd / && exec sudo -n -u "$RUN_AS" -- "${env[@]}" "$@"
  else exec "${env[@]}" "$@"; fi
}
# Stops everything the site's commands left running: as the site's user, every process of that user;
# here, the command's own process group (it starts in a new one).
stop_site() {
  if [ -n "$RUN_AS" ]; then sudo -n pkill -KILL -u "$RUN_AS" 2>/dev/null || true
  elif [ -n "${GROUP:-}" ]; then kill -KILL -- "-$GROUP" 2>/dev/null || true; fi
}
trap 'stop_site; [ -n "$RUN_AS" ] || rm -rf "$SITE_HOME"' EXIT
run() { # run <label> <command> [args…]: the command is from kit.json; args are passed as they are.
  local label="$1" cmd="$2"; shift 2
  echo "::group::$label"
  # Into a file, not a pipe: a process the command leaves running cannot hold the step open.
  # shellcheck disable=SC2016 # $KIT_SITE and $@ are for the inner shell
  (as_site setsid timeout -k 10 600 bash -c 'cd -- "$KIT_SITE" || exit 97; '"$cmd"' "$@"' kit "$@") > "$OUT/$label.log" 2>&1 &
  GROUP=$!
  wait "$GROUP"; local rc=$?
  stop_site; GROUP=""
  tail -n 200 "$OUT/$label.log"
  echo "::endgroup::"
  return "$rc"
}

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
  run verify "$verify" "${args[@]}"; rc=$?
  # The verify step prints one line per check, starting with ✅, ❌ or ⬜. Keep up to 12 of them.
  grep -E '^(✅|❌|⬜) ' "$OUT/verify.log" 2>/dev/null | head -12 | while IFS= read -r v; do line "${v%% *}" "${v#* }"; done
  # Sizes only when the verify step's own lines say it looked at a phone and a laptop.
  sizes=""; grep -qE '^(✅|❌) .*on a phone' "$OUT/verify.log" && grep -qE '^(✅|❌) .*on a laptop' "$OUT/verify.log" && sizes=" at 390px and 1280px"
  if [ "$rc" -eq 0 ]; then verified+=("$verify ${pages[*]}$sizes")
  else verified+=("$verify ${pages[*]}$sizes found problems"); fi
fi
if [ "${#verified[@]}" -eq 0 ]; then echo "none (kit.json names no test or verify command)" > "$OUT/verified.txt"
else (IFS=';'; printf '%s\n' "${verified[*]}" | sed 's/;/; /g') > "$OUT/verified.txt"; fi
cat "$R"
exit 0
