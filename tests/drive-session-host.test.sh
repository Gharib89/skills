#!/usr/bin/env bash
# drive-session on a host that is not a Herdr pane (a T3 Code thread): no
# HERDR_ENV and no HERDR_WORKSPACE_ID, yet `herdr` answers. The guard admits it
# when `herdr workspace list` answers, and `spawn` opens its tab in the
# workspace labelled with the repo's name, creating it when none is. Over the
# same fake `herdr` as tests/drive-session.test.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/herdr-fake.sh

s=skills/drive-session/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/plain"
herdr_fake_install "$tmp/bin"
export PATH="$tmp/bin:$PATH" HERDR_FAKE=$tmp/fake
unset HERDR_ENV HERDR_WORKSPACE_ID
calls() { cat "$HERDR_FAKE/calls" 2>/dev/null; : > "$HERDR_FAKE/calls"; }
quiet_git() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
quiet_git init "$tmp/proj"; quiet_git -C "$tmp/proj" commit --allow-empty -m x
quiet_git -C "$tmp/proj" worktree add "$tmp/wt" -b side

# --- the guard ---------------------------------------------------------------
# No server answers: every roster script still refuses, after asking once.
out=$(bash "$s/watch.sh" --roster "$tmp/r.json" 2>/dev/null); rc=$?
check_rc "with no HERDR_ENV and no herdr server, watch exits 2" 2 "$rc"
check "the refusal says what it looked for" \
  "drive-session needs Herdr: HERDR_ENV=1 is not set and herdr workspace list does not answer" "$(jq -r .error <<<"$out")"
check "the guard asked the server once and went no further" "workspace list" "$(calls)"

# A server answers: the guard admits the host.
printf '[{"label":"other","workspace_id":"w9"},{"label":"proj","workspace_id":"w7"}]\n' > "$HERDR_FAKE/workspaces"
printf '{"sessions":[]}\n' > "$tmp/r.json"
out=$(bash "$s/watch.sh" --roster "$tmp/r.json" 2>/dev/null); rc=$?
check_rc "with a herdr server answering, watch passes the guard (no live session: exit 1)" 1 "$rc"
check "and answers past it" "no live session in the roster $tmp/r.json" "$(jq -r .error <<<"$out")"
calls >/dev/null

# --- spawn's workspace ---------------------------------------------------------
printf 'idle 3\n' > "$HERDR_FAKE/s1.states"
bash "$s/spawn.sh" s1 --roster "$tmp/s1.json" --cwd "$tmp/proj" --prompt x >/dev/null; rc=$?
check_rc "spawn with no HERDR_WORKSPACE_ID exits 0" 0 "$rc"
check "spawn opens the tab in the workspace labelled with the repo's name" \
  "tab create --workspace w7 --label s1 --cwd $tmp/proj --no-focus" "$(calls | grep '^tab create')"

printf 'idle 3\n' > "$HERDR_FAKE/s2.states"
bash "$s/spawn.sh" s2 --roster "$tmp/s2.json" --cwd "$tmp/wt" --prompt x >/dev/null; rc=$?
check_rc "spawn from a worktree exits 0" 0 "$rc"
check "a worktree's repo name is its main checkout's, not the worktree folder's" \
  "tab create --workspace w7 --label s2 --cwd $tmp/wt --no-focus" "$(calls | grep '^tab create')"

printf 'idle 3\n' > "$HERDR_FAKE/s3.states"
bash "$s/spawn.sh" s3 --roster "$tmp/s3.json" --cwd "$tmp/plain" --prompt x >/dev/null; rc=$?
check_rc "spawn with no workspace for the repo exits 0" 0 "$rc"
check "spawn creates the repo's workspace, unfocused, and names its first tab, opening no second" \
  "workspace create --cwd $tmp/plain --label plain --no-focus
tab rename w-plain:t1 s3" "$(calls | grep -E '^(workspace create|tab create|tab rename)')"
check "the roster records the workspace's first tab" "w-plain:t1" "$(jq -r '.sessions[0].tab' "$tmp/s3.json")"

# HERDR_WORKSPACE_ID still wins: only the guard's own question, no lookup.
printf 'idle 3\n' > "$HERDR_FAKE/s4.states"
HERDR_WORKSPACE_ID=w1 bash "$s/spawn.sh" s4 --roster "$tmp/s4.json" --cwd "$tmp/proj" --prompt x >/dev/null
check "HERDR_WORKSPACE_ID names the workspace when set" \
  "workspace list
tab create --workspace w1 --label s4 --cwd $tmp/proj --no-focus" "$(calls | grep -E '^(workspace|tab create)')"

# A workspace list it cannot read is a refusal, never "no such workspace": no
# list at all, or the repo's label with no string id.
for case in 'no-list={}' 'numeric-id=[{"label":"proj","workspace_id":7}]' 'missing-id=[{"label":"proj"}]'; do
  bad=${case%%=*}
  printf '%s\n' "${case#*=}" > "$HERDR_FAKE/workspaces"
  out=$(bash "$s/spawn.sh" s5 --roster "$tmp/s5.json" --cwd "$tmp/proj" --prompt x 2>/dev/null); rc=$?
  check_rc "spawn on a $bad workspace list exits 2" 2 "$rc"
  check "it says the list is unreadable ($bad)" "workspace list: unreadable answer from herdr" "$(jq -r .error <<<"$out")"
  check "and creates no workspace and no tab ($bad)" "" "$(calls | grep -E '^(workspace create|tab create)')"
done

finish
