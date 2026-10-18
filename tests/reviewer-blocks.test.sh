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
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root=$tmp/checkout
mkdir -p "$root/.github/workflows"
: >"$root/.github/workflows/claude-review.yml"
# The traversal case needs a file that really exists above the root. It sits
# inside the trapped tree, one level up from the checkout, so the one `rm -rf`
# covers it: a fixed name in the system temp directory would outlive an
# interrupted run and collide between two concurrent suites.
: >"$tmp/reviewer-blocks-outside.yml"

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

# Phase 4 writes `Round: self-review <n>:` and `Stop: self-review:` into the Run
# file, so a reviewer by that name would close phase 7 on phase 4's record.
check "refuses a reviewer named self-review" \
  "profile invalid: self-review is a reviewer name the Run file reserves for phase 4's self-review lines" \
  "$(reasons "$(sed 's|^### claude$|### self-review|' <<<"$profile")")"
check "refuses a reviewer name starting self-review and a space" \
  "profile invalid: self-review bot is a reviewer name the Run file reserves for phase 4's self-review lines" \
  "$(reasons "$(sed 's|^### claude$|### self-review bot|' <<<"$profile")")"
check "a longer word is another name" \
  '' "$(reasons "$(sed 's|^### claude$|### self-reviewer|' <<<"$profile")")"

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

# A path the stat resolves outside the checkout is not in it, and the fixture
# above it really exists, so this is the case a plain `-f` passes.
check "refuses a Workflow: that climbs out of the checkout with .." \
  'profile invalid: claude has Workflow: ../reviewer-blocks-outside.yml, which is not in the checkout' \
  "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: ../reviewer-blocks-outside.yml|' <<<"$profile")")"

check "refuses an absolute Workflow:, whatever it names" \
  'profile invalid: claude has Workflow: /etc/hostname, which is not in the checkout' \
  "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: /etc/hostname|' <<<"$profile")")"

# `Workflow: native <integration>` names a status source that is no file: the
# integration posts the round itself, so nothing is statted, and only an
# integration ship reads is admitted.
check "admits Workflow: native codex on a comment transport, with no file to stat" \
  '' "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: native codex|' <<<"$profile")")"
check "refuses a native integration ship does not read" \
  'profile invalid: claude has Workflow: native gemini, which names no native integration ship reads (codex)' \
  "$(reasons "$(sed 's|^Workflow: .github/workflows/claude-review.yml$|Workflow: native gemini|' <<<"$profile")")"
check "refuses Workflow: native codex on a block whose Request: is not a comment transport" \
  'profile invalid: copilot has Workflow: native codex but its Request: is None., not comment <phrase>' \
  "$(reasons "$(sed '0,/^Workflow: None.$/s||Workflow: native codex|' <<<"$profile")")"

# The comment transport has no phrase to post, so a block whose Request: is
# the bare word cannot be asked for a round at all. It is refused on its own,
# whether or not a Workflow: sits beside it: read as a transport owing one, the
# block that carries one would pass.
bare_comment=$(sed 's|^Request: comment @claude$|Request: comment|;/^Workflow: .github\/workflows\/claude-review.yml$/d' <<<"$profile")
check "refuses a Request: comment with the phrase left off" \
  'profile invalid: claude has Request: comment with no phrase for the transport to post' \
  "$(reasons "$bare_comment")"

check "refuses it just the same where a Workflow: sits beside it" \
  'profile invalid: claude has Request: comment with no phrase for the transport to post' \
  "$(reasons "$(sed 's|^Request: comment @claude$|Request: comment|' <<<"$profile")")"

check "a Request: whose value merely starts with the letters of comment is not one" \
  '' \
  "$(reasons "$(sed 's|^Request: comment @claude$|Request: commentary-bot|;s|^Workflow: .github/workflows/claude-review.yml$|Workflow: None.|' <<<"$profile")")"

# The other thing a `Request:` holds is a mechanic name, and one of them starts
# with the word: a separator that admitted `comment-pr` would read the host's
# own request transport as the comment one.
check "the mechanic comment-pr is a mechanic name, not a comment transport" \
  '' \
  "$(reasons "$(sed 's|^Request: comment @claude$|Request: comment-pr|;s|^Workflow: .github/workflows/claude-review.yml$|Workflow: None.|' <<<"$profile")")"

# Keyed by path, not by name: two blocks under one name would otherwise answer
# for each other's file.
twin=$(sed 's|^### claude$|### copilot|;s|^Workflow: None.$|Workflow: .github/workflows/claude-review.yml|;s|^Request: None.$|Request: comment @copilot|' <<<"$profile")
check "two blocks sharing a name are stated against their own files" \
  '' "$(reasons "$twin")"


finish
