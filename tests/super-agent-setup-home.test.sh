#!/usr/bin/env bash
# super-agent's `setup` and the super agent folder: a proposal writes nothing and
# names the missing state guard as a Needs you line, and --write rewrites the
# folder's generated local settings, whose one hook is the state guard, to the
# same content on every run.
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
check "--write writes the folder's local settings, its one hook the state guard" "true true 1 1 []" \
  "$(jq .home.written <<<"$out") $(jq .home.guard <<<"$out") $(jq '.hooks.PreToolUse | length' "$hc") \
$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$hc" | grep -c "super-agent/scripts/guard.sh'$") $(jq -c .home.needs <<<"$out")"
check "it answers where the folder is" "$XDG_STATE_HOME/super-agent/home" "$(jq -r .home.folder <<<"$out")"
cp "$hc" "$tmp/first.json"; printf '{"x":1}\n' > "$hc"
S --write --name laptop >/dev/null
check "a second run rewrites it to the same content" same "$(cmp -s "$hc" "$tmp/first.json" && echo same || echo differs)"

finish
