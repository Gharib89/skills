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

check "refuses a Cap: that is not a number" \
  'profile invalid: copilot has Cap: three, which is neither a number nor None.' \
  "$(reasons "$(sed 's|^Cap: 3$|Cap: three|' <<<"$profile")")"

# ---- adversarial: the ways a parser answers wrong rather than failing --------

check "a parse that produced nothing refuses, rather than reading as no faults" \
  'profile invalid: the ## Reviewers blocks could not be parsed' \
  "$(ship_reviewer_reasons '')"

check "so does output that is not an array" \
  'profile invalid: the ## Reviewers blocks could not be parsed' \
  "$(ship_reviewer_reasons '{"name": "copilot"}')"

tabbed=$(printf '## Reviewers\n\n### copilot\n\nLogin: a\tb\nTrigger: on-push\nCap: None.\nGating: no\n\n## Coding standards\n')
check "a tab inside a value is flattened, not truncated at" \
  'a b' "$(ship_reviewers "$tabbed" | jq -r '.[0].login')"

dup=$(sed 's|^### claude$|### copilot|' <<<"$profile")
check "a repeated ### name keeps its own fields instead of a row of nulls" \
  'on-push on-request' "$(ship_reviewers "$dup" | jq -r '[.[].trigger] | join(" ")')"

tilde=$(printf '## Reviewers\n\n### copilot\n\nLogin: bot\nTrigger: on-push\nCap: None.\nGating: no\n\n~~~\n### not-a-reviewer\n\nLogin: nope\n~~~\n\n## Coding standards\n')
check "a ### heading inside a tilde fence is not a reviewer" \
  'copilot' "$(ship_reviewers "$tilde" | jq -r '[.[].name] | join(" ")')"

bare=$(printf '## Reviewers\n\n### claude\n\nLogin: bot\nTrigger: on-request\nCap:\nGating: no\n\n## Coding standards\n')
check "a Cap: with no value reads as absent, and on-request still refuses" \
  'profile invalid: claude is on-request with no Cap:' \
  "$(ship_reviewer_reasons "$(ship_reviewers "$bare")")"

check "Gating: is a boolean whatever it reads, never null" \
  'false' "$(ship_reviewers "$(sed 's|^Gating: no$|Gating: None.|' <<<"$profile")" | jq -r '.[0].gating')"

# --- ship_copilot_trigger_reason: the profile's Copilot block against the host --
#
# The ruleset is what actually decides whether Copilot re-reviews a push, so a
# `Trigger:` that contradicts it is a profile that lies about its own loop. The
# function is pure: preflight reads `review_on_push` off the host and passes it
# in, so the contradiction is decided here and tested with no host.

check "on-push agrees with review_on_push: true" \
  '' "$(ship_copilot_trigger_reason copilot on-push true)"

check "on-push contradicts review_on_push: false" \
  'profile invalid: copilot is Trigger: on-push, but the copilot_code_review ruleset has review_on_push: false' \
  "$(ship_copilot_trigger_reason copilot on-push false)"

check "on-request agrees with review_on_push: false" \
  '' "$(ship_copilot_trigger_reason copilot on-request false)"

check "auto-once agrees with review_on_push: false" \
  '' "$(ship_copilot_trigger_reason copilot auto-once false)"

check "on-request contradicts review_on_push: true" \
  'profile invalid: copilot is Trigger: on-request, but the copilot_code_review ruleset has review_on_push: true' \
  "$(ship_copilot_trigger_reason copilot on-request true)"

check "auto-once contradicts review_on_push: true" \
  'profile invalid: copilot is Trigger: auto-once, but the copilot_code_review ruleset has review_on_push: true' \
  "$(ship_copilot_trigger_reason copilot auto-once true)"

# A check that could not run is not a verdict: preflight warns and continues, so
# the function must stay silent rather than invent an agreement or a fault.
check "an unreadable ruleset yields no reason" \
  '' "$(ship_copilot_trigger_reason copilot on-push '')"

check "a reviewer with no Trigger: at all yields no reason, the null Trigger being its own fault elsewhere" \
  '' "$(ship_copilot_trigger_reason copilot '' true)"

finish
