#!/usr/bin/env bash
# preflight's self_review_cap: the number of phase-4 self-review rounds the
# profile's optional `Self-review cap:` line under `## Reviewers` allows, 3 when
# the line is absent, and a `profile invalid:` reason with a null cap when its
# value is not a whole number of at least 1.
#
# Driven over the Host fake inside a throwaway GitHub-origin checkout; the
# profile carries the Reviewers section alone, so preflight's other reasons are
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
printf 'copilot-pull-request-reviewer[bot]\n' > "$SHIP_FAKE/host_copilot_login.1.json"

# profile <reviewers-section-body>: a profile whose Reviewers section holds it.
profile() { printf '## Reviewers\n\n%s\n\n## Coding standards\n\ndocs/x.md\n' "$1" > "$repo/docs/agents/ship.md"; }
preflight() { ( cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null ); }
cap() { jq -c .self_review_cap <<<"$out"; }
reason() { jq -r '[.reasons[] | select(startswith("profile invalid: Self-review cap"))] | join("; ")' <<<"$out"; }

profile 'None.'; out=$(preflight)
check "no line: the cap is 3" 3 "$(cap)"
check "no line: no reason" "" "$(reason)"

profile $'Self-review cap: 1\n\nNone.'; out=$(preflight)
check "a cap of 1 is today's single round" 1 "$(cap)"
check "a cap of 1 is no reason" "" "$(reason)"

profile $'Self-review cap: 5\n\n### copilot\n\nLogin: x\nTrigger: auto-once'; out=$(preflight)
check "the line above reviewer blocks is read" 5 "$(cap)"
check "and the blocks parse around it" '["copilot"]' "$(jq -c '[.reviewers[].name]' <<<"$out")"

profile $'Self-review cap: 2  \r'; out=$(preflight)
check "trailing blanks and a CR are not part of the value" 2 "$(cap)"

for v in three 3x 0 -1 '1.5' '' '3 rounds'; do
  profile "Self-review cap: $v"; out=$(preflight)
  check "'$v' is refused" "profile invalid: Self-review cap: $v is not a whole number of rounds, 1 or more" "$(reason)"
  check "'$v' leaves the cap null" null "$(cap)"
done

# Only a column-0 line in the Reviewers section, outside a fence, is the line.
profile $'  Self-review cap: x\n\nNone.'; out=$(preflight)
check "an indented line is no label" 3 "$(cap)"
profile $'```\nSelf-review cap: x\n```\n\nNone.'; out=$(preflight)
check "a fenced line is an example" 3 "$(cap)"
check "and no reason" "" "$(reason)"
profile $'Self-review caps: x\n\nNone.'; out=$(preflight)
check "a longer label is another label" 3 "$(cap)"
printf '## Coding standards\n\nSelf-review cap: x\n' > "$repo/docs/agents/ship.md"; out=$(preflight)
check "the line under another section is not read" 3 "$(cap)"

profile $'### copilot\n\nLogin: x\nTrigger: auto-once\nSelf-review cap: 7'; out=$(preflight)
check "a line inside a reviewer block is not the line" 3 "$(cap)"

profile $'Self-review cap: 2\nSelf-review cap: x'; out=$(preflight)
check "the first line decides" 2 "$(cap)"

rm -f "$repo/docs/agents/ship.md"; out=$(preflight)
check "no profile: no cap" null "$(cap)"

finish
