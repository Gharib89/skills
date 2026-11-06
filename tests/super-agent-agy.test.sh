#!/usr/bin/env bash
# super-agent's `agy-job`, driven through its command line over a fake `agy` on
# PATH (tests/super-agent-fake.sh): a bounded text job runs from a scratch
# worktree of the repo, with a session-only allow list of harmless commands and
# JSON output, never with all permissions skipped, and the scratch worktree is
# gone afterwards.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut wc chmod diff git; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" 2>/dev/null || true
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
J() { bash "$s/agy-job.sh" "$@"; }

repo=$tmp/repo
git init -q "$repo" && git -C "$repo" -c user.email=a@b -c user.name=n commit -q --allow-empty -m init || exit 2
ok='{"conversation_id":"c","status":"SUCCESS","response":"the summary","duration_seconds":3.2,"num_turns":2}'
denied='{"conversation_id":"c","status":"SUCCESS","response":"","num_turns":1,"denied_actions":[{"action":"command","display_name":"RunCommand"}]}'
reset() { rm -f "$SA_FAKE/calls" "$SA_FAKE/agy-cwd"; sa_provider agy 0 "$ok"; }
call() { grep '^agy ' "$SA_FAKE/calls" | tail -1; }
rules() { call | sed -n "s/.*--settings \(.*\) --output-format.*/\1/p" | jq -c '.permissions.allow'; }

# --- the contract every script keeps -----------------------------------------------
out=$(bash "$s/agy-job.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: agy-job" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
usage=$(sed -n 1p <<<"$out")
reset
refused() { # <case> <args>...: a malformed call exits 2
  local c=$1; shift
  bash "$s/agy-job.sh" "$@" >/dev/null 2>&1; check_rc "$c exits 2" 2 "$?"
}
refused "an unknown flag" --bogus
refused "no repo" --task x
refused "no task" --repo "$repo"
refused "a missing repo" --repo "$tmp/none" --task x
refused "a zero timeout" --repo "$repo" --task x --timeout 0
for name in '*' 'git*' rm sudo curl 'a b'; do refused "--allow '$name'" --repo "$repo" --task x --allow "$name"; done
check "a bad call answers the usage line" "$usage" "$(bash "$s/agy-job.sh" --bogus 2>/dev/null | jq -r .error)"
check "and agy never ran" "" "$(cat "$SA_FAKE/calls" 2>/dev/null)"

# --- a job runs from a scratch worktree with an allow list and JSON output -----------------------
reset
out=$(J --repo "$repo" --task "summarise the diff"); rc=$?
check_rc "a job that answers exits 0" 0 "$rc"
check "the answer carries agy's response and status" '{"status":"SUCCESS","response":"the summary"}' "$(jq -c '{status, response}' <<<"$out")"
check "it asks for JSON output and prints the task after -p" 'agy -p summarise the diff' "$(call | sed 's/ --.*//')"
check "output is JSON" "--output-format json" "$(call | grep -o -- '--output-format json')"
check "the allow list is a session-only --settings JSON" 1 "$(call | grep -c -- ' --settings {"permissions":{"allow":\[')"
check "it never skips all permissions" 0 "$(grep -c -e '--dangerously-skip-permissions' "$SA_FAKE/calls")"
check "it never allows every command" 0 "$(call | grep -c 'command(\*)')"
check "the default list leans permissive: reads, searches and text tools" 1 \
  "$(rules | jq '[.[] | select(. == "command(ls)" or . == "command(cat)" or . == "command(grep)" or . == "command(find)" or . == "command(jq)" or . == "command(diff)" or . == "command(wc)")] | length == 7' | grep -c true)"
check "every rule names one binary, no wildcard or space" 0 "$(rules | jq -r '.[]' | grep -c -E '^command\([^)]*[ *][^)]*\)$')"
check "no default rule allows a deleting, privileged or network command" 0 \
  "$(rules | jq -r '.[]' | grep -c -E '^command\((rm|sudo|su|curl|wget|ssh|scp|nc|dd|git|chmod|chown|kill)\)$')"
cwd=$(cut -d"|" -f1 "$SA_FAKE/agy-cwd"); common=$(cut -d"|" -f2 "$SA_FAKE/agy-cwd")
check "agy ran in a scratch directory, not the repo" 1 "$([ "$cwd" != "$repo" ] && [ -n "$cwd" ] && echo 1 || echo 0)"
check "that directory is a worktree of the repo" "$repo/.git" "$common"
check "the scratch worktree is gone afterwards" 0 "$([ -e "$cwd" ] && echo 1 || echo 0)"
check "and the repo lists no extra worktree" 1 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"
check "the answer names what ran" "$(jq -c . <<<"$(rules)")" "$(jq -c .allow <<<"$out" | jq -c '[.[] | "command(\(.))"]')"

# --- the job's own needs and flags ------------------------------------------------------------------
reset
J --repo "$repo" --task t --allow git --allow make >/dev/null
check "--allow adds a binary name to the list" 2 "$(rules | jq '[.[] | select(. == "command(git)" or . == "command(make)")] | length')"
reset
J --repo "$repo" --task t --model claude-sonnet-4-6 --timeout 90 >/dev/null
check "--model is passed on" 1 "$(call | grep -c -- '--model claude-sonnet-4-6')"
check "--timeout bounds agy's own print time" 1 "$(call | grep -c -- '--print-timeout 90s')"

# --- a job that did not do its work is reported, never silent --------------------------------------
reset; sa_provider agy 0 "$denied"
out=$(J --repo "$repo" --task t 2>/dev/null); rc=$?
check_rc "a denied command exits 1" 1 "$rc"
check "the answer names the denial" '[{"action":"command","display_name":"RunCommand"}]' "$(jq -c .denied <<<"$out")"
check "the scratch worktree is still removed" 1 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"
reset; sa_provider agy 3 ""
out=$(J --repo "$repo" --task t 2>/dev/null); rc=$?
check_rc "an agy exit with no answer exits 1" 1 "$rc"
check "the answer says so" "agy exited 3 with no JSON answer" "$(jq -r .error <<<"$out")"
reset; sa_provider agy 0 '{"status":"ERROR","response":"","error":"interrupted"}'
out=$(J --repo "$repo" --task t 2>/dev/null); rc=$?
check_rc "a status that is not SUCCESS exits 1" 1 "$rc"
check "the answer carries agy's error" interrupted "$(jq -r .error <<<"$out")"
check "the worktree is removed after a failure" 1 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"

finish
