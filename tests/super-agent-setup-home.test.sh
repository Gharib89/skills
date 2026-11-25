#!/usr/bin/env bash
# super-agent's `setup` and the super agent folder: a proposal writes nothing and
# names the missing state guard and watch guard as Needs you lines, and --write
# rewrites the folder's generated local settings, whose hooks are the state guard
# (PreToolUse) and the watch guard (Stop), to the same content on every run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/super-agent-setup-lib.sh
reset() {
  rm -f "$fleet" "$SA_FAKE/calls" "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
  sa_machine laptop 12 32768 ""
  sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
  sa_environments '[]'; sa_github alice
}
# --- the super agent folder: its generated local settings hold the state guard ----
export XDG_STATE_HOME=$tmp/state HOME=$tmp/home
hc=$XDG_STATE_HOME/super-agent/home/.claude/settings.local.json
reset
out=$(P --name laptop)
check "a proposal writes no folder, and the missing guard is one Needs you row" "absent false 1" \
  "$([ -e "$hc" ] && echo present || echo absent) $(jq .home.written <<<"$out") $(jq '[.home.needs[] | select(test("state guard"))] | length' <<<"$out")"
out=$(S --write --name laptop)
check "--write writes the folder's local settings, its first PreToolUse hook the state guard" "true true 3 1 []" \
  "$(jq .home.written <<<"$out") $(jq .home.guard <<<"$out") $(jq '.hooks.PreToolUse | length' "$hc") \
$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$hc" | grep -c "super-agent/scripts/guard.sh'$") $(jq -c .home.needs <<<"$out")"
check "the proposal's missing watch guard is its own Needs you row" 1 \
  "$(jq '[.home.needs[] | select(test("watch guard"))] | length' <<<"$(rm -rf "$XDG_STATE_HOME/super-agent/home"; P --name laptop)")"
: > "$SA_FAKE/timer-inactive"
check "a missing wake timer is one Needs you row" 1 \
  "$(S --write --name laptop | jq '[.home.needs[] | select(test("^Wake timer: "))] | length')"
rm -f "$SA_FAKE/timer-inactive"
: > "$SA_FAKE/timer-unreadable"
check "a systemctl that cannot be read is one row saying so, never not running" "1 0" \
  "$(S --write --name laptop | jq -r '[.home.needs[] | select(test("^Wake timer: "))] | "\(length) \(map(select(test("not running"))) | length)"')"
rm -f "$SA_FAKE/timer-unreadable"
S --write --name laptop >/dev/null
check "it answers where the folder is" "$XDG_STATE_HOME/super-agent/home" "$(jq -r .home.folder <<<"$out")"
check "and its Stop hook is the watch guard" "1 1 true" \
  "$(jq '.hooks.Stop | length' "$hc") $(jq -r '.hooks.Stop[0].hooks[0].command' "$hc" | grep -c "super-agent/scripts/watch-guard.sh' || true$") $(jq .home.watch_guard <<<"$out")"
check "its other PreToolUse entry is the observe hook and its UserPromptSubmit hook the question flag" "1 1 true true" \
  "$(jq -r '.hooks.PreToolUse[1].hooks[0].command' "$hc" | grep -c "super-agent/scripts/observe.sh' || true$") \
$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$hc" | grep -c "super-agent/scripts/question-flag.sh' || true$") $(jq .home.observe <<<"$out") $(jq .home.question_flag <<<"$out")"
prop=$(rm -rf "$XDG_STATE_HOME/super-agent/home"; P --name laptop)
check "the proposal's missing question flag and observe hook are one Needs you row each" "1 1" \
  "$(jq '[.home.needs[] | select(test("question flag"))] | length' <<<"$prop") $(jq '[.home.needs[] | select(test("observe hook"))] | length' <<<"$prop")"
S --write --name laptop >/dev/null
out=$(S --write --name laptop)
check "its third PreToolUse entry is the call guard, which refuses with exit 2 and so ends no || true" "1 1 true" \
  "$(jq -r '.hooks.PreToolUse[2].hooks[0].command' "$hc" | grep -c "super-agent/scripts/call-guard.sh'$") \
$(jq -r '.hooks.PreToolUse[2].matcher' "$hc" | grep -c 't3_thread_send_attachments|Bash$') $(jq .home.call_guard <<<"$out")"
check "the proposal's missing call guard is one Needs you row" 1 "$(jq '[.home.needs[] | select(test("call guard"))] | length' <<<"$prop")"
cp "$hc" "$tmp/first.json"; printf '{"x":1}\n' > "$hc"
S --write --name laptop >/dev/null
check "a second run rewrites it to the same content" same "$(cmp -s "$hc" "$tmp/first.json" && echo same || echo differs)"

finish
