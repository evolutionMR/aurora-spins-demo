#!/usr/bin/env bash
# Before anything else: this script only runs commands from root-owned system folders. The job's
# PATH also holds folders GitHub's images leave writable for everyone (/usr/local/bin, the Node tool
# cache under /opt), so a command looked up there after the site's code ran could be one it planted.
# Node is looked up now, before any of the site's code has run (the workflow passes KIT_NODE).
KIT_JOB_PATH="${KIT_JOB_PATH:-$PATH}"
KIT_NODE="${KIT_NODE:-$(command -v node 2>/dev/null || true)}"
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
#
# The test job: no AI, no secrets, a read-only token. Runs the site's own tests and its verify step
# on a clean checkout with Claude's patch applied, and writes what happened for the save job.
# The commands come from kit.json on the default branch (an engineer's file), never from Claude.
# Claude only suggests which pages to look at (.ai-builder/run/verify.txt); each page and text is
# checked here and passed as its own argument, never through a shell.
#
#   kit-test.sh <claude artifact folder> <out folder>       (run in the checkout, from its root)
#   kit-test.sh --path-check "<PATH>"                       prints the PATH folders someone else could write to
#   kit-test.sh --sandbox-command <user> <site> <home>      prints the sandbox command, one word per line
#
# Writes <out>/results.md (lines "- ✅|❌|⬜ <plain words>") and <out>/verified.txt (one line for the
# commit's "Verified:" line). Needs KIT_JSON and KIT (the folder with kit-change.sh).
#
# The site's install, test and verify commands may run code Claude changed (any CI does). So in the
# workflows (KIT_RUN_AS set) each one runs in a sandbox: a transient systemd unit (systemd-run) as a
# separate user made here (no sudo, in no other group). In that unit the whole system is read-only
# (ProtectSystem=strict) and every home folder is hidden (ProtectHome=tmpfs) except the site user's
# own, which holds its copy of the checkout and its caches and is the only place it can write; /tmp
# is its own; it cannot gain rights (NoNewPrivileges, no setuid), cannot reach the cloud metadata
# addresses (IPAddressDeny, plus iptables, removed at the end), and gets a clean environment: no
# ACTIONS_* (no runtime token, no cache address), no GITHUB_TOKEN or GH_TOKEN, no NODE_OPTIONS, and
# GITHUB_ENV, GITHUB_PATH and GITHUB_OUTPUT pointed at /dev/null. When the command ends, systemd
# kills everything left in the unit (KillMode=control-group); after 7 minutes the unit is stopped.
# The user may not use cron or at, and gets no lingering systemd --user.
# Why systemd-run and not bubblewrap: GitHub's hosted Ubuntu runners boot with systemd, so it is
# always there; one unit gives the read-only system, the user switch, the clean environment, the
# address block and the kill-everything-at-the-end in one place, and the job needs no extra package.
# Before any of the site's code runs, as root, this script also takes write-for-everyone away from
# every PATH folder, /usr/local, /opt and /usr/share, fails if a PATH folder can still be written by
# others, and checks from inside the sandbox that the site user cannot write to any PATH folder or
# to the node and git programs (actions/checkout's post step runs git later in this job). Afterwards
# it fails if anything new appeared in a PATH folder. Nothing the site's code wrote is run: only its
# printed lines are read, as text, and shown between ::stop-commands:: lines, so they can never be
# read as workflow commands.
# Without KIT_RUN_AS (the AI Builder's own tests) the commands run here, still with the clean environment.
# The results are a hint for the person: the required checks on the pull request are the real gate.
set -uo pipefail
export LC_ALL=C.UTF-8
SUDO=(/usr/bin/sudo -n)
# Stops the job. Any ✅ lines already written are thrown away, so a stop after the site's commands
# (for example something new in a PATH folder) can never show as "tests passed".
R=""
die() {
  echo "::error::$*" >&2
  if [ -n "$R" ]; then
    printf -- '- ❌ %s\n' "The test job stopped: $(printf '%s' "$*" | tr -d '\r\n<>@`' | /usr/bin/head -c 200)" > "$R"
  fi
  exit 1
}

# Prints one line for each PATH folder someone other than root could write to: the folder itself
# (sticky or not: a sticky folder still lets anyone add a file), or a folder above it without the
# sticky bit (it could be renamed and replaced). A folder that does not exist counts by the nearest
# one above it that does. A relative entry ("", ".") always counts: it is wherever the command runs.
path_problems() {
  local -a dirs; local d a m first
  IFS=: read -r -a dirs <<< "$1"
  [[ "$1" != *: ]] || dirs+=("")
  for d in "${dirs[@]}"; do
    [[ "$d" == /* ]] || { printf 'PATH has a relative entry ("%s")\n' "$d"; continue; }
    a="$d"; first=1
    while :; do
      if [ -e "$a" ]; then
        m=$(/usr/bin/stat -L -c %a -- "$a" 2>/dev/null || echo 0)
        if (( 8#$m & 2 )) && { (( first )) || ! (( 8#$m & 01000 )); }; then printf 'anyone can write to %s (PATH: %s)\n' "$a" "$d"; fi
        first=0
      fi
      [ "$a" = / ] && break
      a=$(/usr/bin/dirname -- "$a")
    done
  done
}
# The first <name> in the job's PATH, as a later step (actions/checkout's post step) would find it.
lookup() {
  local -a dirs; local d
  IFS=: read -r -a dirs <<< "$KIT_JOB_PATH"
  for d in "${dirs[@]}"; do [[ "$d" == /* && -f "$d/$1" && -x "$d/$1" ]] && { printf '%s\n' "$d/$1"; return 0; }; done
  return 1
}
# The sandbox for one of the site's commands: SANDBOX=(the whole command line). $1 = the unit's
# name, the rest = the command and its arguments. --expand-environment=no: systemd passes every
# argument exactly as given (no $VAR expansion; needs systemd 254 or newer, Ubuntu 24.04).
sandbox_cmd() {
  local unit="$1" e; shift
  SANDBOX=("${SUDO[@]}" /usr/bin/systemd-run --wait --pipe --collect --quiet --expand-environment=no
    "--unit=$unit" "--uid=$RUN_AS" "--gid=$RUN_AS" "--working-directory=$SITE"
    -p ProtectSystem=strict -p ProtectHome=tmpfs -p "BindPaths=$SITE_HOME" -p "ReadWritePaths=$SITE_HOME"
    -p PrivateTmp=yes -p PrivateDevices=yes -p ProtectProc=invisible -p NoNewPrivileges=yes -p RestrictSUIDSGID=yes
    -p KillMode=control-group -p TimeoutStopSec=10 -p RuntimeMaxSec=420
    -p IPAddressDeny=169.254.0.0/16 -p IPAddressDeny=168.63.129.16)
  for e in "${SITE_ENV[@]}"; do SANDBOX+=("--setenv=$e"); done
  SANDBOX+=(-- "$@")
}
# The whole environment the site's commands get (nothing else is passed on).
site_env() {
  SITE_ENV=("PATH=$CLEAN_PATH" "HOME=$SITE_HOME" "LANG=C.UTF-8" "LC_ALL=C.UTF-8" "CI=true" "TERM=dumb"
    "GITHUB_ENV=/dev/null" "GITHUB_PATH=/dev/null" "GITHUB_OUTPUT=/dev/null" "GITHUB_STATE=/dev/null" "GITHUB_STEP_SUMMARY=/dev/null"
    "KIT_SITE=$SITE")
  [ -z "$pw_path" ] || SITE_ENV+=("NODE_PATH=$pw_path/node_modules" "PLAYWRIGHT_BROWSERS_PATH=$pw_path/browsers")
}
node_dir=""; [[ "$KIT_NODE" == /* && -x "$KIT_NODE" ]] && node_dir=$(/usr/bin/dirname -- "$KIT_NODE")
CLEAN_PATH="${node_dir:+$node_dir:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
pw_path=""

case "${1:-}" in
  --path-check)
    problems=$(path_problems "${2:-}"); [ -z "$problems" ] || { printf '%s\n' "$problems"; exit 1; }; exit 0 ;;
  --sandbox-command)
    RUN_AS="${2:-}" SITE="${3:-}" SITE_HOME="${4:-}"; site_env; sandbox_cmd ai-builder-site-test-1 /bin/true
    printf '%s\n' "${SANDBOX[@]}"; exit 0 ;;
esac

IN="${1:-}"; OUT="${2:-}"
[ -d "$IN" ] && [[ "$OUT" = /* ]] || die "Usage: kit-test.sh <in> <out>"
RUN_AS="${KIT_RUN_AS:-}"
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "$RUN_AS" ]; then die "KIT_RUN_AS is not set: the site's commands never run as the runner's own user."; fi
mkdir -p "$OUT"
R="$OUT/results.md"; : > "$R"
line() { printf -- '- %s %s\n' "$1" "$(printf '%s' "$2" | tr -d '\r\n<>@`' | /usr/bin/head -c 280)" >> "$R"; }
# Prints text the site's code wrote, with workflow commands switched off around it (a new random
# token each time, so the text cannot switch them back on).
show() {
  local token
  token=$(/usr/bin/od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  [[ "$token" =~ ^[0-9a-f]{32}$ ]] || die "Could not make a random token."
  printf '::stop-commands::%s\n' "$token"
  "$@"
  printf '\n::%s::\n' "$token"
}
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

if [ -n "$RUN_AS" ]; then
  [[ "$RUN_AS" =~ ^[a-z][a-z0-9-]{2,30}$ ]] || die "KIT_RUN_AS is not a plain user name."
  [ "$RUN_AS" != "$(id -un)" ] && [ "$RUN_AS" != root ] || die "KIT_RUN_AS must be a separate user."
  [ -d /run/systemd/system ] && [ -x /usr/bin/systemd-run ] || die "This runner has no systemd, so the site's commands cannot be sandboxed. Use a GitHub-hosted ubuntu-24.04 runner."
  v=$(/usr/bin/systemd-run --version | /usr/bin/head -1 | /usr/bin/grep -oE '^systemd [0-9]+' | /usr/bin/grep -oE '[0-9]+' || echo 0)
  [ "$v" -ge 254 ] || die "systemd $v is too old for the sandbox (254 or newer needed: ubuntu-24.04)."
  [ -n "$node_dir" ] || die "Node was not found (KIT_NODE)."
fi

# Pinned Playwright, installed before any of the site's code runs, outside the checkout (so nothing
# in it changes what is installed). In the workflows root installs it, and the site's user can read
# it but not change it.
if [ -n "$verify" ] && [ -n "$pw" ] && [[ "$pw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  as=(); p="${RUNNER_TEMP:-$OUT}/pw"
  if [ -n "$RUN_AS" ]; then as=("${SUDO[@]}"); p=/opt/ai-builder-playwright; fi
  npm_env=(/usr/bin/env -i "PATH=${node_dir:+$node_dir:}/usr/sbin:/usr/bin:/sbin:/bin" "HOME=${HOME:-/root}" "LANG=C.UTF-8")
  [ -z "$RUN_AS" ] || npm_env=(/usr/bin/env -i "PATH=$node_dir:/usr/sbin:/usr/bin:/sbin:/bin" "HOME=/root" "LANG=C.UTF-8")
  if "${as[@]}" /usr/bin/rm -rf "$p" && "${as[@]}" /usr/bin/mkdir -p "$p" \
    && (cd "$p" && "${as[@]}" "${npm_env[@]}" "${node_dir:+$node_dir/}npm" i --no-save --no-audit --no-fund --ignore-scripts --prefix "$p" "playwright@$pw" >/dev/null \
      && "${as[@]}" "${npm_env[@]}" "PLAYWRIGHT_BROWSERS_PATH=$p/browsers" "$p/node_modules/.bin/playwright" install --with-deps chromium >/dev/null) \
    && { [ -z "$RUN_AS" ] || { "${SUDO[@]}" /usr/bin/chown -R root:root "$p" && "${SUDO[@]}" /usr/bin/chmod -R a+rX,go-w "$p"; }; }; then
    pw_path="$p"
  else line "⬜" "Phone and laptop look not checked: the browser could not be installed."; fi
fi

# Where and as whom the site's commands run.
FW=(); SNAP=""
if [ -n "$RUN_AS" ]; then
  id -u "$RUN_AS" >/dev/null 2>&1 || "${SUDO[@]}" /usr/sbin/useradd --create-home --home-dir "/home/$RUN_AS" --shell /bin/bash --user-group "$RUN_AS" \
    || die "Could not make the user the site's tests run as."
  # Never in a group that gives power (sudo, docker, the runner's own group…).
  extra=$(id -nG "$RUN_AS" | tr ' ' '\n' | /usr/bin/grep -vxF "$RUN_AS" || true)
  [ -z "$extra" ] || die "The user the site's tests run as is in other groups: $(printf '%s' "$extra" | tr '\n' ' ')"
  # No cron, no at, no lingering systemd --user: nothing of that user's runs after its command ends.
  for f in /etc/cron.deny /etc/at.deny; do
    /usr/bin/grep -qxF "$RUN_AS" "$f" 2>/dev/null || printf '%s\n' "$RUN_AS" | "${SUDO[@]}" /usr/bin/tee -a "$f" >/dev/null || die "Could not write $f."
  done
  "${SUDO[@]}" /usr/bin/loginctl disable-linger "$RUN_AS" 2>/dev/null || true
  [ ! -e "/var/lib/systemd/linger/$RUN_AS" ] || die "The test user could keep a systemd --user running."
  # The runner's home holds this job's temp folder, the runner's own files and its settings
  # (the sandbox hides it too).
  "${SUDO[@]}" /usr/bin/chmod o-rwx "$HOME" || die "Could not close the runner's home folder."
  # Nobody but root may write to a folder a later command is looked up in.
  IFS=: read -r -a job_dirs <<< "$KIT_JOB_PATH"
  for d in "${job_dirs[@]}" "$node_dir" /usr/local /opt /usr/share; do
    [[ "$d" == /* && -d "$d" ]] || continue
    # Only what others can write to is changed (fast on the big hosted images); path_problems
    # below and the probe inside the sandbox are the hard checks.
    "${SUDO[@]}" /usr/bin/find -H "$d" -xdev -perm -0002 ! -type l -exec /usr/bin/chmod o-w {} + || die "Could not close $d."
  done
  git_bin=$(lookup git || echo /usr/bin/git)
  problems=$(path_problems "$KIT_JOB_PATH:$CLEAN_PATH:$(/usr/bin/dirname -- "$(/usr/bin/realpath -- "$git_bin")"):$(/usr/bin/dirname -- "$(/usr/bin/realpath -- "$KIT_NODE")")")
  [ -z "$problems" ] || die "Others can still write to a folder on PATH: $(printf '%s' "$problems" | tr '\n' ';')"
  SITE="/home/$RUN_AS/site"; SITE_HOME="/home/$RUN_AS"
  "${SUDO[@]}" /usr/bin/rm -rf "$SITE" && "${SUDO[@]}" /usr/bin/mkdir -p "$SITE" && "${SUDO[@]}" /usr/bin/cp -a . "$SITE/" && "${SUDO[@]}" /usr/bin/chown -R "$RUN_AS:$RUN_AS" "$SITE_HOME" \
    || die "Could not copy the site for the test user."
  # The cloud metadata addresses, a second time (the unit's IPAddressDeny is the first). Removed at the end.
  for addr in 169.254.0.0/16 168.63.129.16/32; do
    if "${SUDO[@]}" /usr/sbin/iptables -I OUTPUT -m owner --uid-owner "$RUN_AS" -d "$addr" -j REJECT 2>/dev/null; then FW+=("$addr")
    else echo "::warning::Could not block $addr for the test user (the sandbox still blocks it)."; fi
  done
  # What is in the PATH folders now; anything new after the site's commands fails the job.
  SNAP=$(/usr/bin/mktemp)
  /usr/bin/find -H "${job_dirs[@]}" -mindepth 1 -maxdepth 1 -printf '%p\t%i %C@ %s\0' 2>/dev/null | LC_ALL=C /usr/bin/sort -z > "$SNAP"
else
  SITE="$PWD"; SITE_HOME=$(/usr/bin/mktemp -d)
fi
site_env

# Stops everything the site's commands left running. In the sandbox systemd already killed the
# unit; this kills anything of that user's that is left anyway. Here: the command's process group.
stop_site() {
  if [ -n "$RUN_AS" ]; then
    "${SUDO[@]}" /usr/bin/systemctl kill --signal=KILL 'ai-builder-site-*.service' 2>/dev/null || true
    "${SUDO[@]}" /usr/bin/pkill -KILL -u "$RUN_AS" 2>/dev/null || true
  elif [ -n "${GROUP:-}" ]; then kill -KILL -- "-$GROUP" 2>/dev/null || true; fi
}
cleanup() {
  stop_site
  local a
  for a in "${FW[@]}"; do "${SUDO[@]}" /usr/sbin/iptables -D OUTPUT -m owner --uid-owner "$RUN_AS" -d "$a" -j REJECT 2>/dev/null || true; done
  [ -z "$SNAP" ] || /usr/bin/rm -f "$SNAP"
  [ -n "$RUN_AS" ] || /usr/bin/rm -rf "$SITE_HOME"
}
trap cleanup EXIT

# The sandbox, checked for real from inside before the site's code runs: it must run as the site's
# user, and that user must not be able to write to any PATH folder, to node or git, or to the
# runner's checkout, nor read the runner's home, use sudo or reach the metadata addresses.
if [ -n "$RUN_AS" ]; then
  # shellcheck disable=SC2016 # for the shell inside the sandbox
  probe='me=$(id -un); for d in "$@"; do
      if [ -d "$d" ]; then f="$d/.ai-builder-probe-$$"; if (: > "$f") 2>/dev/null; then echo "CAN-WRITE $d"; rm -f "$f"; fi
      elif [ -e "$d" ] && [ -w "$d" ]; then echo "CAN-WRITE $d"; fi
    done
    [ -z "$(ls -A "$RUNNER_HOME" 2>/dev/null)" ] || echo "CAN-READ $RUNNER_HOME"
    /usr/bin/sudo -n true 2>/dev/null && echo "CAN-SUDO"
    for a in 169.254.169.254 168.63.129.16; do timeout 3 bash -c "exec 3<>/dev/tcp/$a/80" 2>/dev/null && echo "CAN-REACH $a"; done
    echo "PROBE-DONE $me"'
  IFS=: read -r -a clean_dirs <<< "$CLEAN_PATH"
  targets=("${job_dirs[@]}" "${clean_dirs[@]}" /usr/local /opt /usr/share "$git_bin" "$(/usr/bin/realpath -- "$git_bin")" "$KIT_NODE" "$(/usr/bin/realpath -- "$KIT_NODE")" "$PWD" "$PWD/.git/config")
  sandbox_cmd "ai-builder-site-probe-$$" /usr/bin/env "RUNNER_HOME=$HOME" /bin/bash -c "$probe" probe "${targets[@]}"
  said=$("${SANDBOX[@]}" < /dev/null 2>&1)
  /usr/bin/grep -qxF "PROBE-DONE $RUN_AS" <<<"$said" || die "The sandbox did not start as $RUN_AS: $(printf '%s' "$said" | /usr/bin/head -c 300 | tr '\n' ' ')"
  bad=$(/usr/bin/grep -E '^CAN-' <<<"$said" || true)
  [ -z "$bad" ] || die "The sandbox is not tight: $(printf '%s' "$bad" | tr '\n' ';')"
  stop_site
fi

# as_local <command> [args…]: here (no KIT_RUN_AS), in the checkout, with the clean environment. It
# ends with exec, so run it only in a background subshell (run below): its pid is the command's own.
as_local() { cd / && exec /usr/bin/env -i "${SITE_ENV[@]}" "$@"; }
run() { # run <label> <command> [args…]: the command is from kit.json; args are passed as they are.
  local label="$1" cmd="$2" rc; shift 2
  local log="$OUT/$label.log"
  # shellcheck disable=SC2016 # $KIT_SITE and $@ are for the inner shell
  local inner=(/bin/bash -c 'cd -- "$KIT_SITE" || exit 97; '"$cmd"' "$@"' kit "$@")
  echo "::group::$label"
  # Into a file, not a pipe: a process the command leaves running cannot hold the step open.
  if [ -n "$RUN_AS" ]; then
    sandbox_cmd "ai-builder-site-$label-$$" "${inner[@]}"
    "${SANDBOX[@]}" > "$log" 2>&1 < /dev/null; rc=$?
  else
    (as_local /usr/bin/setsid /usr/bin/timeout -k 10 600 "${inner[@]}") > "$log" 2>&1 < /dev/null &
    GROUP=$!
    wait "$GROUP"; rc=$?
  fi
  stop_site; GROUP=""
  show /usr/bin/tail -n 200 -- "$log"
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
  done < <(/usr/bin/head -c 4000 "$IN/notes/verify.txt")
fi
if [ "${#pages[@]}" -eq 0 ]; then pages=("/"); args=("/"); fi
if [ -n "$verify" ]; then
  run verify "$verify" "${args[@]}"; rc=$?
  # The verify step prints one line per check, starting with ✅, ❌ or ⬜. Keep up to 12 of them.
  /usr/bin/grep -E '^(✅|❌|⬜) ' "$OUT/verify.log" 2>/dev/null | /usr/bin/head -12 | while IFS= read -r v; do line "${v%% *}" "${v#* }"; done
  # Sizes only when the verify step's own lines say it looked at a phone and a laptop.
  sizes=""; /usr/bin/grep -qE '^(✅|❌) .*on a phone' "$OUT/verify.log" && /usr/bin/grep -qE '^(✅|❌) .*on a laptop' "$OUT/verify.log" && sizes=" at 390px and 1280px"
  if [ "$rc" -eq 0 ]; then verified+=("$verify ${pages[*]}$sizes")
  else verified+=("$verify ${pages[*]}$sizes found problems"); fi
fi

# Nothing new may have appeared in a PATH folder (the sandbox and the closed folders should make
# that impossible). If something did, it is removed before any later step can run it, and the job fails.
if [ -n "$SNAP" ]; then
  now=$(/usr/bin/mktemp)
  /usr/bin/find -H "${job_dirs[@]}" -mindepth 1 -maxdepth 1 -printf '%p\t%i %C@ %s\0' 2>/dev/null | LC_ALL=C /usr/bin/sort -z > "$now"
  # NUL-separated (any file name is safe); new or changed entries (inode, change time, size) count.
  changed=()
  while IFS= read -r -d '' e; do changed+=("${e%$'\t'*}"); done < <(LC_ALL=C /usr/bin/comm -z -13 "$SNAP" "$now")
  /usr/bin/rm -f "$now"
  if [ "${#changed[@]}" -gt 0 ]; then
    for f in "${changed[@]}"; do [[ "$f" == /* ]] && "${SUDO[@]}" /usr/bin/rm -rf -- "$f"; done
    die "Something new or changed in a PATH folder while the site's commands ran (removed): $(printf '%s ' "${changed[@]}" | tr -d '\r\n' | /usr/bin/head -c 300)"
  fi
  # Nothing of the test user's may outlive its commands: no lingering systemd --user, no process.
  [ ! -e "/var/lib/systemd/linger/$RUN_AS" ] || die "The test user turned on a lingering systemd --user."
  # A process killed a moment ago can still be listed while it dies: kill again, wait a little, then judge.
  "${SUDO[@]}" /usr/bin/pkill -KILL -u "$RUN_AS" 2>/dev/null || true
  left=1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -u "$RUN_AS" > /dev/null 2>&1; rc=$?
    [ "$rc" -eq 1 ] && { left=0; break; }        # 1 = none found
    [ "$rc" -eq 0 ] || break                       # anything else: pgrep failed, so fail closed
    /usr/bin/sleep 0.2
  done
  [ "$left" -eq 0 ] || die "A process of the test user was still running after its commands (or it could not be checked)."
  "${SUDO[@]}" /usr/bin/find /dev/shm /dev/mqueue -xdev -user "$RUN_AS" -delete 2>/dev/null || true
  problems=$(path_problems "$KIT_JOB_PATH")
  [ -z "$problems" ] || die "Others can write to a folder on PATH: $(printf '%s' "$problems" | tr '\n' ';')"
fi
if [ "${#verified[@]}" -eq 0 ]; then echo "none (kit.json names no test or verify command)" > "$OUT/verified.txt"
else (IFS=';'; printf '%s\n' "${verified[*]}" | /usr/bin/sed 's/;/; /g') > "$OUT/verified.txt"; fi
show /usr/bin/cat -- "$R"
exit 0
