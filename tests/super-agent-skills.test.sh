#!/usr/bin/env bash
# super-agent's `skills`: the skill names a task launch can name, with their
# one-line descriptions, though the super agent folder switches them off. Setup
# saves the listing it read, and a later setup whose listing holds only the
# skills left on (the pinned thread's own, after the cut) keeps the rest off
# and listed.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/super-agent-setup-lib.sh
sa_machine laptop 12 32768 ""
sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
sa_environments '[]'; sa_github alice
hc=$XDG_STATE_HOME/super-agent/home/.claude/settings.json
K() { bash "$s/skills.sh"; }

check_rc "with no listing saved yet it exits 2" 2 "$(K >/dev/null 2>&1; echo $?)"
check "and names the setup line that saves one" "1" "$(K 2>/dev/null | jq -r .error | grep -c 'setup.sh --write')"

sa_pinned_transcript "$HOME/.claude/projects/p/pinned.jsonl" '["code-review", "eli5:eli5", "super-agent"]'
S --write --name laptop >/dev/null
check "it prints each skill a task can name with its one-line description" \
  '[{"name":"code-review","description":"code-review does a thing."},{"name":"eli5:eli5","description":"eli5:eli5 does a thing."}]' \
  "$(K | jq -c .skills)"

sa_pinned_transcript "$HOME/.claude/projects/p/pinned.jsonl" '["super-agent", "new-skill"]'
S --write --name laptop >/dev/null
check "a listing after the cut keeps the skills already off, and adds a new one" \
  '{"code-review":"off","eli5:eli5":"off","new-skill":"off"}' "$(jq -c .skillOverrides "$hc")"
check "and the names script still lists them all" "code-review eli5:eli5 new-skill" "$(K | jq -r '[.skills[].name] | join(" ")')"

finish
