#!/usr/bin/env bash
# skills/setup-harness/templates/cloud-setup.sh: the cloud setup's contract. The
# subject is what a cloud session and Ship's cloud bootstrap read: nothing run
# and exit 0 outside a cloud session, one status line on stdout inside one,
# exit non-zero on failure, and a second run that re-runs no satisfied step.
# Each case writes the template into a throwaway git repo with its own
# configuration block, the way setup-harness writes it; the steps log to a file.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
template=$PWD/skills/setup-harness/templates/cloud-setup.sh
log=$fixture/log

# <name> <config>: a git repo whose .claude/hooks/cloud-setup.sh is the template
# with its configuration block replaced by <config>; prints the script's path.
hook_script() {
  local r=$fixture/$1
  mkdir -p "$r/.claude/hooks"
  git -C "$r" init -q
  awk -v cfg="$2" '
    /^# >>> setup-harness/ { print; print cfg; skip = 1; next }
    /^# <<< setup-harness/ { skip = 0 }
    !skip' "$template" > "$r/.claude/hooks/cloud-setup.sh"
  chmod +x "$r/.claude/hooks/cloud-setup.sh"
  printf '%s' "$r/.claude/hooks/cloud-setup.sh"
}
# <remote> <script>: runs it from outside the repo, stdout only; sets rc.
run() { : > "$log"; out=$(cd "$fixture" && CLAUDE_CODE_REMOTE=$1 LOG=$log "$2" 2>/dev/null); rc=$?; }

# The tool step installs a marker the done test looks for, so a second run finds
# it satisfied; the deps step has no done test and runs every time.
s=$(hook_script ok "STEPS='tool|test -e \"\$LOG.tool\"|echo tool >> \"\$LOG\"; : > \"\$LOG.tool\"
deps||echo deps >> \"\$LOG\"'")

run false "$s"
check_rc "outside a cloud session it exits 0" 0 "$rc"
check "and runs no step or prints anything" "" "$out$(cat "$log")"
run '' "$s"
check "an unset CLAUDE_CODE_REMOTE is not a cloud session" "" "$out$(cat "$log")"

rm -f "$log.tool"
run true "$s"
check_rc "in a cloud session every step passing exits 0" 0 "$rc"
check "and prints the ok line alone" "harness cloud setup: ok" "$out"
check "each step ran once, in order" "tool
deps" "$(cat "$log")"
run true "$s"
check "a second run skips a step whose done test passes" "deps" "$(cat "$log")"
check "and still prints ok" "harness cloud setup: ok" "$out"

s=$(hook_script fail "STEPS='first||echo first >> \"\$LOG\"
broken||echo half >> \"\$LOG\"; exit 3
never||echo never >> \"\$LOG\"'")
run true "$s"
check_rc "a failing step exits non-zero" 1 "$rc"
check "and names the step on the status line" "harness cloud setup: FAILED broken" "$out"
check "and stops there" "first
half" "$(cat "$log")"

s=$(hook_script inert "STEPS='tool|test -e \"\$LOG.none\"|echo tool >> \"\$LOG\"'")
run true "$s"
check_rc "a step whose done test still fails after it ran is a failure" 1 "$rc"
check "named on the status line" "harness cloud setup: FAILED tool" "$out"

out=$(cd "$fixture" && CLAUDE_CODE_REMOTE=true LOG=$log "$(hook_script noise "STEPS='chatty||echo installing; echo warn >&2'")" 2>/dev/null)
check "a step's own output stays off stdout" "harness cloud setup: ok" "$out"

# A step reading stdin, as its command or its done test, would otherwise eat the
# rows after it; a command may carry a pipe; steps run from the repo root.
s=$(hook_script stdin "STEPS='cmd-reads||cat >/dev/null; echo cmd >> \"\$LOG\"
test-reads|cat >/dev/null; test -e \"\$LOG.t\"|: > \"\$LOG.t\"; echo test >> \"\$LOG\"
piped||echo a | tr a b >> \"\$LOG\"
where||git rev-parse --show-prefix >> \"\$LOG\"; echo root >> \"\$LOG\"'")
rm -f "$log.t"
run true "$s"
check "no step's stdin reaches the rows after it, a pipe stays in its command, steps run at the root" "cmd
test
b

root" "$(cat "$log")"

# The dockerd and image rows reference/cloud.md gives a container tool, as
# written there. dockerd is a daemon: the row detaches it with every fd off
# the hook's pipes, else the hook waits on it until its timeout. The stub
# daemon stays up, so a row that held stdout would stall this run 20 s.
bin=$fixture/bin; mkdir -p "$bin"
printf '#!/bin/sh\n: > "$LOG.up"; echo dockerd >> "$LOG"; exec sleep 20\n' > "$bin/dockerd"
cat > "$bin/docker" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "info "*) test -e "$LOG.up" ;;
  "image inspect") test -e "$LOG.img" ;;
  "pull "*) : > "$LOG.img"; echo "pull $2" >> "$LOG" ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$bin/dockerd" "$bin/docker"
rows=$(sed -n 's/^   - `\([a-z-]*|docker .*\)`$/\1/p' skills/setup-harness/reference/cloud.md | sed 's/<tag>/v9.9.9/g; s/<digest>/sha256:abc/g')
check "cloud.md gives the two rows" 2 "$(printf '%s\n' "$rows" | grep -c .)"
s=$(hook_script docker "STEPS='$rows'")
# stdout and stderr both reach a pipe, as a hook's do: a writer left holding
# either keeps the pipeline open.
docker_run() { : > "$log"; out=$(cd "$fixture" && PATH="$bin:$PATH" TMPDIR=$fixture CLAUDE_CODE_REMOTE=true LOG=$log "$s" 2>&1 | grep '^harness cloud setup'); }
rm -f "$log.up" "$log.img"
start=$(date +%s)
docker_run
check "the first run starts dockerd and pulls the image" "harness cloud setup: ok
dockerd
pull hadolint/hadolint:v9.9.9@sha256:abc" "$out
$(cat "$log")"
check "without waiting on the daemon" yes "$([ $(( $(date +%s) - start )) -lt 10 ] && echo yes || echo no)"
docker_run
check "the second run is a no-op" "harness cloud setup: ok" "$out$(cat "$log")"
rm -f "$log.up"
docker_run
check "after an idle restart kills dockerd it starts again, the image kept" "harness cloud setup: ok
dockerd" "$out
$(cat "$log")"

# The browser rows reference/cloud.md gives a web UI member, one per route, as
# written there. The member's own Playwright names its revision directories;
# the stub installs a revision by writing each directory's marker, the vendor
# route through Playwright's installer, the mcr route by copying the image's.
pw=$fixture/pw-browsers
cat > "$bin/pnpm" <<'STUB'
#!/bin/sh
case "$*" in
  "exec playwright --version") echo "Version 1.2.3" ;;
  "exec playwright install --dry-run chromium")
    [ -e "$PW.dry-empty" ] && exit 0
    for d in chromium-7 ffmpeg-1 chromium_headless_shell-7 ffmpeg-1; do echo "browser: x"; echo "  Install location:    $PW/$d"; done ;;
  "exec playwright install --with-deps chromium")
    echo vendor >> "$LOG"; for d in chromium-7 ffmpeg-1 chromium_headless_shell-7; do mkdir -p "$PW/$d"; : > "$PW/$d/INSTALLATION_COMPLETE"; done ;;
  *) exit 64 ;;
esac
STUB
cat > "$bin/docker" <<'STUB'
#!/bin/sh
case "$1" in
  create) echo "create $2" >> "$LOG"; echo cid ;;
  cp) [ -e "$PW.cp-fail" ] && exit 1; d=${2#cid:/ms-playwright/}; mkdir -p "$3$d"; : > "$3$d/INSTALLATION_COMPLETE" ;;
  rm) echo "rm $2" >> "$LOG" ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$bin/pnpm" "$bin/docker"
browser_rows=$(sed -n 's/^   - `\(browsers-<member>|.*\)`$/\1/p' skills/setup-harness/reference/cloud.md | sed 's/<member>/web/g; s/<exec>/pnpm exec/g')
check "cloud.md gives a browser row per route" 2 "$(printf '%s\n' "$browser_rows" | grep -c .)"
browser_run() { # <route>: the row whose command takes that route
  local row; row=$(printf '%s\n' "$browser_rows" | grep -e "$1")
  s=$(hook_script "browser-$1" "STEPS='$row'"); mkdir -p "${s%/.claude/hooks/cloud-setup.sh}/web"
  : > "$log"; out=$(cd "$fixture" && PATH="$bin:$PATH" PW=$pw CLAUDE_CODE_REMOTE=true LOG=$log "$s" 2>/dev/null)
}
rm -rf "$pw"; mkdir -p "$pw"
browser_run 'docker create'
check "the mcr row copies the member's revision out of its version's image" "harness cloud setup: ok
create mcr.microsoft.com/playwright:v1.2.3-noble
rm cid" "$out
$(cat "$log")"
check "into the directories Playwright names" "chromium-7 chromium_headless_shell-7 ffmpeg-1" "$(ls "$pw" | tr '\n' ' ' | sed 's/ $//')"
browser_run 'docker create'
check "and a second run, the revision complete, is a no-op" "harness cloud setup: ok" "$out$(cat "$log")"
rm -rf "$pw"; mkdir -p "$pw/chromium-7"
browser_run 'with-deps'
check "the vendor row installs through Playwright's installer" "harness cloud setup: ok
vendor" "$out
$(cat "$log")"
browser_run 'with-deps'
check "and a second run is a no-op" "harness cloud setup: ok" "$out$(cat "$log")"
: > "$pw.dry-empty"
browser_run 'with-deps'
check "a Playwright naming no directory runs the row, then fails its done test" "harness cloud setup: FAILED browsers-web
vendor" "$out
$(cat "$log")"
rm -f "$pw.dry-empty"; rm -rf "$pw"; mkdir -p "$pw"; : > "$pw.cp-fail"
browser_run 'docker create'
check "a failed copy fails the setup and removes its container" "create mcr.microsoft.com/playwright:v1.2.3-noble
rm cid" "$(cat "$log")"
rm -f "$pw.cp-fail"

# The SessionStart entry setup-harness merges into .claude/settings.json: its
# command, run as a hook runs it, exits 0 outside a cloud session, because a
# non-zero SessionStart exit is shown to a local session as a hook error.
entry=skills/setup-harness/templates/settings-cloud.json
hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$entry")
s=$(hook_script hook "STEPS=''"); r=${s%/.claude/hooks/cloud-setup.sh}
out=$(cd "$r" && CLAUDE_PROJECT_DIR=$r CLAUDE_CODE_REMOTE='' LOG=$log bash -c "$hook" 2>&1); rc=$?
check_rc "the SessionStart command exits 0 outside a cloud session" 0 "$rc"
check "and prints nothing" "" "$out"
out=$(cd "$r" && CLAUDE_PROJECT_DIR=$r CLAUDE_CODE_REMOTE=true LOG=$log bash -c "$hook" 2>/dev/null)
check "in a cloud session it runs the cloud setup" "harness cloud setup: ok" "$out"
chmod -x "$s"
out=$(cd "$r" && CLAUDE_PROJECT_DIR=$r CLAUDE_CODE_REMOTE='' bash -c "$hook" 2>&1); rc=$?
check_rc "outside a cloud session it never starts the script" 0 "$rc"
check "synchronous, with an explicit timeout" "null 375" "$(jq -r '.hooks.SessionStart[0].hooks[0] | "\(.async) \(.timeout)"' "$entry")"

finish
