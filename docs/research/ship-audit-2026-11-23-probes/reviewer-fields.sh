#!/usr/bin/env bash
# The reviewer validation preflight runs, on a profile whose two blocks are each
# other's fallback, whose first block has a negative Cap: and a mistyped
# `Gatng:` line. Prints the parsed rows and the refusal reasons (none). Run from
# the repo root.
set -uo pipefail
src=$PWD/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/ship.md" <<'PROFILE'
## Reviewers

### first

Login: first[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: -2
Resolve: resolve-thread
Gatng: yes
Fallback-for: second

### second

Login: second[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 1
Resolve: resolve-thread
Gating: no
Fallback-for: first

## Coding standards
PROFILE
# shellcheck source=/dev/null
source "$src/_lib.sh"
rows=$(ship_reviewers "$(cat "$work/ship.md")")
echo 'Parsed rows:'
jq -c '.[] | {name, cap, gating, fallback_for}' <<<"$rows"
echo 'Refusal reasons:'
reasons=$(ship_reviewer_reasons "$rows" "$work")
printf '%s\n' "${reasons:-(none)}"
