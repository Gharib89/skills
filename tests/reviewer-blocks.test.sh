#!/usr/bin/env bash
# The pure reviewer-block parser and the profile-invalid reasons it feeds
# preflight. Every case is a profile body in, a string out; no host is reached.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

# `ship_reviewer_reasons` stats the file a `Workflow:` line names, so the cases
# need a checkout root to stat against. A fixture tree, not this repo: a case
# that passed because the real `.github/workflows/` happened to carry the name
# would stop proving the check the day that file is renamed.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/.github/workflows"
: >"$root/.github/workflows/claude-review.yml"

# A two-reviewer profile in the shape `docs/agents/ship.md` carries: field lines
# first, then the prose paragraph that explains the block.
profile=$(cat <<'EOF'
# Ship profile

Schema: 3

## Host

Host: github

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-push
Request: None.
Workflow: None.
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
Workflow: .github/workflows/claude-review.yml
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

check "reads Workflow: as the file the reviewer's round comes from" \
  '.github/workflows/claude-review.yml' \
  "$(jq -r '.[1].workflow' <<<"$rows")"

check "turns Workflow: None. into null, like every other field" \
  'null' "$(jq -r '.[0].workflow | tostring' <<<"$rows")"

nowf=$(printf '## Reviewers\n\n### copilot\n\nLogin: bot\nTrigger: on-push\nCap: None.\nGating: no\n\n## Coding standards\n')
check "a block with no Workflow: line reads as null, not absent from the row" \
  'null' "$(ship_reviewers "$nowf" | jq -r '.[0].workflow | tostring')"

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

# ---- the refusals preflight makes -------------------------------------

reasons() { ship_reviewer_reasons "$(ship_reviewers "$1")" "$root"; }

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

# The `Workflow:`/`Request:` pair. A comment transport's round comes from a
# workflow run, so a block that asks for one and names no file leaves the run
# polling on a constant; a file named on a block no comment drives is a value
# nothing reads. The third is the one stat: a path that names no file is the
# same silence as no path at all, and it is spelt wrong far more often.

check "refuses a comment transport whose Workflow: is None." \
  'profile invalid: claude has Request: comment @claude with no Workflow: naming the workflow file its round comes from' \
  "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: None.|' <<<"$profile")")"

check "refuses a comment transport with no Workflow: line at all" \
  'profile invalid: claude has Request: comment @claude with no Workflow: naming the workflow file its round comes from' \
  "$(reasons "$(sed '/^Workflow: .github\/workflows\/claude-review.yml$/d' <<<"$profile")")"

check "refuses a Workflow: on a block whose Request: is not a comment transport" \
  'profile invalid: copilot has Workflow: .github/workflows/claude-review.yml but its Request: is None., not comment <phrase>' \
  "$(reasons "$(sed '0,/^Workflow: None.$/s||Workflow: .github/workflows/claude-review.yml|' <<<"$profile")")"

check "refuses a Workflow: naming a file the checkout does not carry" \
  'profile invalid: claude has Workflow: .github/workflows/gone.yml, which is not in the checkout' \
  "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: .github/workflows/gone.yml|' <<<"$profile")")"

# The template reads `comment <phrase>`, so the phrase left off is the likely
# typo, and it is the one an anchor on the trailing space would read as no
# comment transport at all: the block would then owe no `Workflow:` and phase 7
# would poll on the constant, which is the silence this field exists to remove.
bare_comment=$(sed 's|^Request: comment @claude$|Request: comment|;/^Workflow: .github\/workflows\/claude-review.yml$/d' <<<"$profile")
check "reads a Request: comment with the phrase left off as a comment transport" \
  'profile invalid: claude has Request: comment with no Workflow: naming the workflow file its round comes from' \
  "$(reasons "$bare_comment")"

check "a Request: whose value merely starts with the letters of comment is not one" \
  '' \
  "$(reasons "$(sed 's|^Request: comment @claude$|Request: commentary-bot|;s|^Workflow: .github/workflows/claude-review.yml$|Workflow: None.|' <<<"$profile")")"

# Keyed by path, not by name: two blocks under one name would otherwise answer
# for each other's file.
twin=$(sed 's|^### claude$|### copilot|;s|^Workflow: None.$|Workflow: .github/workflows/claude-review.yml|;s|^Request: None.$|Request: comment @copilot|' <<<"$profile")
check "two blocks sharing a name are stated against their own files" \
  '' "$(reasons "$twin")"

# ---- adversarial: the ways a parser answers wrong rather than failing --------

check "a parse that produced nothing refuses, rather than reading as no faults" \
  'profile invalid: the ## Reviewers blocks could not be parsed' \
  "$(ship_reviewer_reasons '' "$root")"

check "so does output that is not an array" \
  'profile invalid: the ## Reviewers blocks could not be parsed' \
  "$(ship_reviewer_reasons '{"name": "copilot"}' "$root")"

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
  "$(ship_reviewer_reasons "$(ship_reviewers "$bare")" "$root")"

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

# --- ship_copilot_row: which block the host check is about ---------------------
#
# The selection preflight makes before it asks the host anything. An empty
# trigger out of here is what makes the check skip itself, so the three ways it
# comes back empty are the three ways preflight declines to ask.

rows=$(ship_reviewers "$profile")

check "the block posting under the login is found, name and trigger together" \
  $'copilot\ton-push' "$(ship_copilot_row 'copilot-pull-request-reviewer[bot]' "$rows")"

check "the login match ignores case, the host spelling one way and the profile another" \
  $'copilot\ton-push' "$(ship_copilot_row 'Copilot-Pull-Request-Reviewer[BOT]' "$rows")"

check "a login no block posts under selects nothing, so nothing is asked of the host" \
  '' "$(ship_copilot_row 'nobody[bot]' "$rows")"

check "an adapter with no Copilot prints no login, and an empty login selects nothing" \
  '' "$(ship_copilot_row '' "$rows")"

# A block whose own Trigger: is missing is a fault `ship_reviewer_reasons` owns;
# the host check declines it rather than refusing it twice under two messages.
notrig=$(printf '## Reviewers\n\n### copilot\n\nLogin: copilot-pull-request-reviewer[bot]\nCap: 3\nGating: no\n\n## Coding standards\n')
check "a block with no Trigger: comes back named but triggerless" \
  $'copilot\t' "$(ship_copilot_row 'copilot-pull-request-reviewer[bot]' "$(ship_reviewers "$notrig")")"

finish