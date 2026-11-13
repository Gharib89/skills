#!/usr/bin/env bash
# preflight's check of the optional `Sandbox merge:` line under `## Cloud lane`
# (#1204): `yes` and `no` are the values `merge` reads, an absent line is no, and
# any other word is a `profile invalid:` reason rather than a silent no.
#
# Driven over the Host fake inside a throwaway GitHub-origin checkout; the
# profile carries the Cloud lane section alone, so preflight's other reasons are
# present and beside the point.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"

profile() { printf '## Cloud lane\n\n%s\n\n## Coding standards\n\ndocs/x.md\n' "$1" > "$repo/docs/agents/ship.md"; }
reason() { ( cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null ) | jq -r '[.reasons[] | select(startswith("profile invalid: Sandbox merge"))] | join("; ")'; }

for v in yes no; do
  profile $'PR cap: 3\nSandbox merge: '"$v"
  check "'$v' is a value" "" "$(reason)"
done
profile $'PR cap: 3'
check "an absent line, or one with no value, is no reason" "" "$(reason)"
for v in maybe Yes true; do
  profile $'PR cap: 3\nSandbox merge: '"$v"
  check "'$v' is refused" "profile invalid: Sandbox merge: $v is not yes or no" "$(reason)"
done
printf '## Coding standards\n\nSandbox merge: maybe\n' > "$repo/docs/agents/ship.md"
check "the line under another section is not read" "" "$(reason)"

finish
