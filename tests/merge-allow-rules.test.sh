#!/usr/bin/env bash
# ship_merge_allow_warnings, preflight's warning: a Claude Code settings layer
# must allow the `merge.sh` and `run-file.sh gate admit` paths ship runs from,
# or every merge call falls to the auto-mode classifier. The ship to ship-run
# rename left the owner's rule on the old path, unnoticed (#1419).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship-run/scripts/lib/skills.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
root=$work/repo config=$work/config scripts=$work/install/ship-run/scripts
mkdir -p "$root/.claude/skills/ship-run/scripts" "$config" "$scripts"
touch "$root/.claude/skills/ship-run/scripts/merge.sh"
P=.claude/skills/ship-run/scripts
warn() { ship_merge_allow_warnings "$root" "$scripts" "$config"; }
allow() { # <file> <rule>...
  local f=$1; shift
  jq -n '{permissions: {allow: $ARGS.positional}}' --args "$@" > "$f"
}

out=$(warn); rc=$?
check "no settings at all warns for both calls" \
"no Claude Code allow rule matches $P/merge.sh: merge calls fall to the auto-mode classifier; add Bash($P/merge.sh:*) to your settings
no Claude Code allow rule matches $P/run-file.sh gate admit: merge calls fall to the auto-mode classifier; add Bash($P/run-file.sh gate admit:*) to your settings" "$out"
check_rc "a warning, never a failure" 0 "$rc"

allow "$config/settings.json" "Bash($P/merge.sh:*)" "Bash($P/run-file.sh gate admit:*)"
check "both rules in the user settings warn nothing" '' "$(warn)"

allow "$config/settings.json" "Bash(.claude/skills/ship/scripts/merge.sh:*)" "Bash($P/run-file.sh gate admit:*)"
check "a rule left on the pre-rename path warns for merge.sh" \
"no Claude Code allow rule matches $P/merge.sh: merge calls fall to the auto-mode classifier; add Bash($P/merge.sh:*) to your settings" "$(warn)"

rm "$config/settings.json"
allow "$root/.claude/settings.json" "Bash($P/merge.sh *)"
allow "$root/.claude/settings.local.json" "Bash($P/run-file.sh:*)"
check "project and local layers count, in either wildcard form" '' "$(warn)"

rm "$root/.claude/settings.json" "$root/.claude/settings.local.json"
echo '{not json' > "$config/settings.json"
check "an unreadable settings file counts as no rule" 2 "$(warn | grep -c 'no Claude Code allow rule')"

# With no project copy the skill runs from its own absolute base directory.
rm -rf "$root/.claude/skills"
allow "$config/settings.json" "Bash($scripts/merge.sh:*)" "Bash($scripts/run-file.sh gate admit:*)"
check "an install with no project copy is checked at its absolute path" '' "$(warn)"
allow "$config/settings.json" "Bash($P/merge.sh:*)" "Bash($P/run-file.sh gate admit:*)"
check "where a relative rule does not cover it" 2 "$(warn | grep -c "matches $scripts/")"

finish
