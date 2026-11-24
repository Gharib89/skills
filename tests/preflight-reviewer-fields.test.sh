#!/usr/bin/env bash
# preflight refuses reviewer blocks whose fields no phase could act on: fallbacks
# that name each other in a cycle (no block is the primary), a `Cap:` that is
# negative or not a whole number, and a `Gating:` other than yes or no (a typo
# would read as "not gating" and let a declined finding through the merge gate).
# A valid profile is admitted as before (#1346).
#
# Driven end to end over the Host fake inside a throwaway GitHub-origin checkout;
# the profile carries the Reviewers section alone, so preflight's other reasons
# are present and beside the point: each case reads only the `profile invalid`
# lines about the reviewer fields.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"

# block <name> <cap> <gating> <fallback-for>
block() {
  printf '### %s\n\nLogin: %s[bot]\nTrigger: on-request\nRequest: None.\nWorkflow: None.\nCap: %s\nResolve: resolve-thread\nGating: %s\nFallback-for: %s\n\n' \
    "$1" "$1" "$2" "$3" "$4"
}
out=
run() { # <block>...: runs preflight over those blocks, leaves its stdout in $out
  { printf '## Reviewers\n\n'; printf '%s\n\n' "$@"; printf '## Coding standards\n'; } > "$repo/docs/agents/ship.md"
  out=$( cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null )
}
reasons() { jq -r '[.reasons[] | select(test("cycle|Cap:|Gating:"))] | join("; ")' <<<"$out"; }

run "$(block first 2 no second)" "$(block second 1 no first)"
check "two fallbacks naming each other are refused once" \
  'profile invalid: reviewers name each other as fallbacks in a cycle: first -> second -> first' "$(reasons)"

run "$(block solo 2 no solo)"
check "a block that is its own fallback is a cycle" \
  'profile invalid: reviewers name each other as fallbacks in a cycle: solo -> solo' "$(reasons)"

run "$(block a 1 no c)" "$(block b 1 no a)" "$(block c 1 no b)"
check "a three-block cycle is named in profile order" \
  'profile invalid: reviewers name each other as fallbacks in a cycle: a -> c -> b -> a' "$(reasons)"

run "$(block a 1 no b)" "$(block b 1 no a)" "$(block c 1 no None.)" "$(block c 1 no None.)"
check "a cycle is still refused beside two blocks sharing an unrelated name" \
  'profile invalid: reviewers name each other as fallbacks in a cycle: a -> b -> a' "$(reasons)"

run "$(block primary 2 no None.)" "$(block spare 1 no primary)"
check "a fallback with a primary is admitted" '' "$(reasons)"

run "$(block neg -2 no None.)"
check "a negative Cap: is refused" \
  'profile invalid: neg has Cap: -2, which is not a whole number of rounds, 0 or more' "$(reasons)"

run "$(block frac 1.5 no None.)"
check "a fractional Cap: is refused" \
  'profile invalid: frac has Cap: 1.5, which is not a whole number of rounds, 0 or more' "$(reasons)"

run "$(block zero 0 no None.)" "$(block three 3 no None.)"
check "Cap: 0 and a whole Cap: are admitted" '' "$(reasons)"

run "$(block loud 2 Yes None.)"
check "a Gating: other than yes or no is refused" \
  'profile invalid: loud has Gating: Yes, which is neither yes nor no' "$(reasons)"

run "$(block gate 2 yes None.)" "$(block calm 2 no None.)"
check "Gating: yes and no are admitted" '' "$(reasons)"

finish
