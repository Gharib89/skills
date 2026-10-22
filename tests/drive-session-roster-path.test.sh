#!/usr/bin/env bash
# drive-session keeps its roster and batch log under the state directory, which
# survives a reboot, never the session scratchpad (tmpfs). SKILL.md says where,
# and the scripts take that path unchanged: `spawn` makes the directories, and
# `watch`, `read` and `answer` work on the roster it wrote. Driven over the fake
# `herdr` (tests/herdr-fake.sh).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/herdr-fake.sh

skill=skills/drive-session/SKILL.md
s=skills/drive-session/scripts
flat() { awk "$1" "$skill" | tr '\n' ' ' | tr -s ' '; }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

roster_step=$(flat '/^1\. \*\*Roster\.\*\*/{f=1; print; next} /^2\. /{f=0} f')
check "the roster step names the state directory" yes \
  "$(has "$roster_step" '${XDG_STATE_HOME:-$HOME/.local/state}/drive-session/<run>/roster.json')"
check "the roster step says the scratchpad is wrong" yes "$(has "$roster_step" 'Never the session scratchpad')"
check "no step puts anything under <scratchpad>" "" "$(grep -n '<scratchpad>' "$skill")"
check "the batch log sits beside the roster" yes \
  "$(has "$(flat '/^4\. \*\*Batch log\.\*\*/{f=1; print; next} /^5\. /{f=0} f')" "in the roster's directory")"

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/cwd"
herdr_fake_install "$tmp/bin"
export PATH="$tmp/bin:$PATH" HERDR_FAKE=$tmp/fake HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 XDG_STATE_HOME=$tmp/state
roster=${XDG_STATE_HOME:-$HOME/.local/state}/drive-session/spec-932/roster.json
printf 'idle 10\n' > "$HERDR_FAKE/s1.states"
out=$(bash "$s/spawn.sh" s1 --roster "$roster" --cwd "$tmp/cwd" --prompt "task one" 2>/dev/null); rc=$?
check_rc "spawn makes the state directory and the roster in it" 0 "$rc"
check "the roster is where the step says" s1 "$(jq -r '.sessions[0].name' "$roster" 2>/dev/null)"
printf 'done 11\n' > "$HERDR_FAKE/s1.states"
out=$(bash "$s/watch.sh" --roster "$roster" --timeout 3000 2>/dev/null)
check "watch reads it" '{"name":"s1","event":"done","seq":11}' "$out"
out=$(bash "$s/read.sh" s1 --roster "$roster" 2>/dev/null)
check "read acknowledges the event in it" 11 "$(jq -r '.sessions[0].seen_seq' "$roster")"
bash "$s/answer.sh" s1 --roster "$roster" --text next >/dev/null 2>&1
check "answer writes to it" 11 "$(jq -r '.sessions[0].seen_seq' "$roster")"

finish
