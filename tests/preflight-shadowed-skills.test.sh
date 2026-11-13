#!/usr/bin/env bash
# preflight's warnings[]: a personal copy under $HOME/.claude/skills that shadows
# ship or a skill it composes is reported, as identical to or different from the
# project copy, and never changes `ok` or `reasons`. A cloud sandbox reports none.
#
# Driven over the Host fake in a throwaway GitHub-origin checkout with a stub HOME.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo home=$work/home
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo/docs/agents" "$repo/.claude/skills/tdd" "$home/.claude/skills" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
printf 'copilot-pull-request-reviewer[bot]\n' > "$SHIP_FAKE/host_copilot_login.1.json"
printf '## Reviewers\n\nNone.\n\n## Coding standards\n\ndocs/x.md\n' > "$repo/docs/agents/ship.md"
echo project > "$repo/.claude/skills/tdd/SKILL.md"

preflight() { ( cd "$repo" && HOME=$home bash "$scripts/preflight.sh" none 2>/dev/null; echo "rc=$?" ); }
json() { sed '$d' <<<"$out"; }
warnings() { json | jq -c .warnings; }
verdict() { json | jq -c '[.ok, .reasons]'; }

out=$(preflight); base=$(verdict); base_rc=$(tail -n1 <<<"$out")
check "no personal copy: no warnings" '[]' "$(warnings)"

mkdir -p "$home/.claude/skills/tdd"; echo project > "$home/.claude/skills/tdd/SKILL.md"
out=$(preflight)
check "an identical copy is reported as identical" \
  '["personal skill copy shadows tdd (~/.claude/skills/tdd): identical to the project copy"]' "$(warnings)"
check "and ok and reasons are unchanged" "$base" "$(verdict)"
check "and the exit code is unchanged" "$base_rc" "$(tail -n1 <<<"$out")"

echo personal > "$home/.claude/skills/tdd/SKILL.md"
out=$(preflight)
check "a differing copy is reported as different" \
  '["personal skill copy shadows tdd (~/.claude/skills/tdd): different from the project copy"]' "$(warnings)"
check "and ok and reasons are unchanged" "$base" "$(verdict)"
check "and the exit code is unchanged" "$base_rc" "$(tail -n1 <<<"$out")"

out=$(CLAUDE_CODE_REMOTE=true preflight)
check "a cloud sandbox reports none" '[]' "$(warnings)"

finish
