#!/usr/bin/env bash
# preflight's reviewers[]: one {name, review_on_push} row per reviewer block,
# `review_on_push` being the copilot_code_review ruleset's answer for the block
# posting under the Copilot login and null for every other block, or where the
# host could not answer. The review loop reads it at phase 7: a free-round poll
# closing on `never_queued: true` is `degraded: never-queued` with no request
# only where this row read `false`, because only then did the host promise the
# free round it did not queue.
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

reset() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
  printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
  printf 'copilot-pull-request-reviewer[bot]\n' > "$SHIP_FAKE/host_copilot_login.1.json"
}
preflight() { ( cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null ); }

# No profile: no blocks, so no rows.
reset
check "no profile leaves reviewers empty" '[]' "$(preflight | jq -c .reviewers)"

cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: None.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: copilot

## Coding standards
EOF

reset; printf 'false\n' > "$SHIP_FAKE/host_copilot_review_on_push.1.json"
check "the Copilot row carries the ruleset's false, the other row null" \
  '[{"name":"copilot","review_on_push":false},{"name":"claude","review_on_push":null}]' \
  "$(preflight | jq -c .reviewers)"

reset; printf 'true\n' > "$SHIP_FAKE/host_copilot_review_on_push.1.json"
check "and its true" true "$(preflight | jq -c '.reviewers[0].review_on_push')"

reset; touch "$SHIP_FAKE/host_copilot_review_on_push.1.fail"
check "an unreadable ruleset is null, not false" null "$(preflight | jq -c '.reviewers[0].review_on_push')"

finish
