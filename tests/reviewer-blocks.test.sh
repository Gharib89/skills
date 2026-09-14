#!/usr/bin/env bash
# The pure reviewer-block parser and the profile-invalid reasons it feeds
# preflight. Every case is a profile body in, a string out; no host is reached.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

# A two-reviewer profile in the shape `docs/agents/ship.md` carries: field lines
# first, then the prose paragraph that explains the block.
profile=$(cat <<'EOF'
# Ship profile

Schema: 2

## Host

Host: github

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-push
Request: None.
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: .github/copilot-instructions.md

Enabled by a ruleset. Trigger: this sentence is prose, not a field.

### claude

Login: github-actions[bot]
Trigger: on-request
Request: comment @claude
Cap: 2
Resolve: None.
Gating: no
Fallback-for: copilot
Instructions: .github/copilot-instructions.md

## Coding standards

docs/contributing/coding-standards.md
EOF
)

rows=$(ship_reviewers "$profile")

check "reads one row per reviewer, in profile order" \
  'copilot claude' \
  "$(jq -r '[.[].name] | join(" ")' <<<"$rows")"

check "reads a login carrying a bracketed bot suffix" \
  'copilot-pull-request-reviewer[bot]' \
  "$(jq -r '.[0].login' <<<"$rows")"

check "reads the trigger" \
  'on-push on-request' \
  "$(jq -r '[.[].trigger] | join(" ")' <<<"$rows")"

check "reads a Request: value carrying a space" \
  'comment @claude' \
  "$(jq -r '.[1].request' <<<"$rows")"

check "turns None. into null, everywhere it appears" \
  'null null null' \
  "$(jq -r '[.[0].request, .[0].fallback_for, .[1].resolve] | map(tostring) | join(" ")' <<<"$rows")"

check "reads Cap: as a number" \
  '3 2' \
  "$(jq -r '[.[].cap] | join(" ")' <<<"$rows")"

check "reads Gating: as a boolean" \
  'false false' \
  "$(jq -r '[.[].gating] | join(" ")' <<<"$rows")"

check "reads Fallback-for: as the primary's name" \
  'copilot' \
  "$(jq -r '.[1].fallback_for' <<<"$rows")"

check "reads Resolve: and Instructions:" \
  'resolve-thread .github/copilot-instructions.md' \
  "$(jq -r '[.[0].resolve, .[0].instructions] | join(" ")' <<<"$rows")"

# Adversarial: a field name inside the explaining prose is not a field, and a
# `### ` heading in a later section is not a reviewer.
check "ignores a field name inside the block's prose" \
  'on-push' \
  "$(jq -r '.[0].trigger' <<<"$rows")"

check "stops at the next ## heading" 2 "$(jq 'length' <<<"$rows")"

none=$(printf '## Reviewers\n\nNone.\n\n## Coding standards\n')
check "a None. reviewers section is an empty list" '[]' "$(ship_reviewers "$none" | jq -c .)"

absent=$(printf '## Host\n\nHost: github\n')
check "a profile with no Reviewers section is an empty list" \
  '[]' "$(ship_reviewers "$absent" | jq -c .)"

fenced=$(cat <<'EOF'
## Reviewers

### copilot

Login: bot
Trigger: on-push
Request: None.
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: None.

An example block, not a reviewer:

```
### not-a-reviewer

Login: nope
Trigger: on-push
```

## Coding standards
EOF
)
check "a ### heading inside a fence is not a reviewer" \
  'copilot' "$(ship_reviewers "$fenced" | jq -r '[.[].name] | join(" ")')"

# ---- the three refusals preflight makes -------------------------------------

reasons() { ship_reviewer_reasons "$(ship_reviewers "$1")"; }

check "a valid pair yields no reason" '' "$(reasons "$profile")"

bad_trigger=$(sed 's|^Fallback-for: None.$|Fallback-for: claude|' <<<"$profile")
check "refuses Fallback-for: on a reviewer that is not on-request" \
  'profile invalid: copilot is Fallback-for: claude but its Trigger is on-push, not on-request' \
  "$(reasons "$bad_trigger")"

unknown=$(sed 's|^Fallback-for: copilot$|Fallback-for: coderabbit|' <<<"$profile")
check "refuses Fallback-for: naming a reviewer the profile does not list" \
  'profile invalid: claude is Fallback-for: coderabbit, which ## Reviewers does not list' \
  "$(reasons "$unknown")"

nocap=$(sed 's|^Cap: 2$|Cap: None.|' <<<"$profile")
check "refuses an on-request reviewer with no Cap:" \
  'profile invalid: claude is on-request with no Cap:' \
  "$(reasons "$nocap")"

check "an on-push reviewer with no Cap: is allowed" \
  '' "$(reasons "$(sed 's|^Cap: 3$|Cap: None.|' <<<"$profile")")"

finish
