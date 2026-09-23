#!/usr/bin/env bash
# poll-pr and a reviewer that refuses the round: a quota notice posted as the
# review answers the request, and no round follows it. Copilot's quota is the
# requesting user's and monthly, and on #248 and #250 every poll spent its
# whole window on a refusal already posted, then the loop asked again.
#
# Driven end to end over the Host fake and a throwaway repo whose origin names
# GitHub, so the mechanic's own loop is the subject: no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
# The blocks `--reviewer` reads: copilot on-request, the same login on-push for
# the head rule, and a second login that has posted nothing.
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Cap: 3
Gating: no

### copilot-push

Login: copilot-pull-request-reviewer[bot]
Trigger: on-push
Request: None.
Cap: None.
Gating: no

### other

Login: claude[bot]
Trigger: on-request
Request: None.
Cap: 2
Gating: no

## Coding standards
EOF

login='copilot-pull-request-reviewer[bot]'
notice_text='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'
row() { # <id> <submitted_at> <substantive> <body>
  jq -cn --arg i "$1" --arg at "$2" --argjson s "$3" --arg b "$4" --arg l "$login" \
    '{id: $i, login: $l, state: "comment", substantive: $s, submitted_at: $at, body: $b}'
}
notice=$(row 1 2026-09-23T14:23:19Z false "$notice_text")
round=$(row 2 2026-09-23T14:40:00Z true '- a finding')

reset() {
  rm -f "$SHIP_FAKE"/*
  jq -cn '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  # Earlier than every --since below, so the review-row cases are decided by
  # the review rows alone; the comment cases at the end set their own time.
  blocked_at 2026-09-23T14:00:00Z
  printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
}
# The adapter's blocked lookup: the latest notice line and when it was posted.
blocked_at() { # <at>
  jq -cn --arg n "$notice_text" --arg at "$1" '{line: $n, at: $at}' \
    > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
reviews() { # <on_head-json> <all-json>
  jq -cn --argjson h "$1" --argjson a "$2" '{on_head: $h, all: $a, total: ($a | length)}' \
    > "$SHIP_FAKE/host_pr_reviews.1.json"
}
poll() { ( cd "$repo" && bash "$mech" 7 --reviewer copilot "$@" ); }
calls() { cat "$SHIP_FAKE/host_$1.n" 2>/dev/null || echo 0; }

# The free-round poll #250 made: the notice landed after the PR opened, and the
# minutes left on --timeout were spent waiting on nothing.
reset
reviews "[$notice]" "[$notice]"
out=$(poll --since 2026-09-23T14:22:34Z --timeout 600 --interval 30); rc=$?
check_rc "a refusal closes the window" 1 "$rc"
check "the refusal names the rule that admitted it" 'since false' \
  "$(jq -r '[.refused_by, (.done|tostring)] | join(" ")' <<<"$out")"
check "and the notice is quoted" "$notice_text" "$(jq -r .reviewer_blocked <<<"$out")"
check "the refusal costs one read" 1 "$(calls pr_reviews)"
check "and none of the window" true "$(jq -r '.waited_s < 30' <<<"$out")"

# A notice older than the request answered an earlier one: this request can
# still be served, so the window runs as it always did.
reset
reviews "[$notice]" "[$notice]"
out=$(poll --since 2026-09-23T14:30:00Z --timeout 0 --interval 1)
check "a notice before --since refuses nothing" null "$(jq -r '.refused_by' <<<"$out")"

# A round that follows a notice is the round: the refusal is read only while
# nothing has landed.
reset
reviews "[$notice, $round]" "[$notice, $round]"
out=$(poll --since 2026-09-23T14:22:34Z --timeout 0 --interval 1); rc=$?
check_rc "a round after a notice lands" 0 "$rc"
check "and nothing reads as refused" 'since null' \
  "$(jq -r '[.landed_by, (.refused_by|tostring)] | join(" ")' <<<"$out")"

# The head rule: a notice on the current head refuses that push's round.
reset
reviews "[$notice]" "[$notice]"
out=$( ( cd "$repo" && bash "$mech" 7 --reviewer copilot-push --timeout 600 --interval 30 ) ); rc=$?
check_rc "a notice on the head closes the window" 1 "$rc"
check "under the head rule" head "$(jq -r '.refused_by' <<<"$out")"

# Another login's notice is not this reviewer's refusal. The adapter's blocked
# lookup filters by login, so for claude[bot] it answers null.
reset
reviews "[$notice]" "[$notice]"
echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
out=$( ( cd "$repo" && bash "$mech" 7 --reviewer other --since 2026-09-23T14:22:34Z \
  --timeout 0 --interval 1 ) )
check "another reviewer's notice refuses nothing" null "$(jq -r '.refused_by' <<<"$out")"

# --brief is what the loop reads, so the refusal travels in it.
reset
reviews "[$notice]" "[$notice]"
out=$(poll --brief --since 2026-09-23T14:22:34Z --timeout 600 --interval 30)
check "--brief carries the refusal and the notice" "since $notice_text" \
  "$(jq -r '[.refused_by, .reviewer_blocked] | join(" ")' <<<"$out")"

# A reviewer that posts its notice as a PR comment leaves no review row: the
# blocked lookup's own timestamp is what the since rule reads (#256).
reset
reviews '[]' '[]'
blocked_at 2026-09-23T14:30:00Z
out=$(poll --since 2026-09-23T14:22:34Z --timeout 600 --interval 30); rc=$?
check_rc "a comment-only notice after --since closes the window" 1 "$rc"
check "under the since rule, with done false" 'since false' \
  "$(jq -r '[.refused_by, (.done|tostring)] | join(" ")' <<<"$out")"
check "and the notice line is quoted" "$notice_text" "$(jq -r .reviewer_blocked <<<"$out")"
check "and none of the window is spent" true "$(jq -r '.waited_s < 30' <<<"$out")"
out=$(poll --brief --since 2026-09-23T14:22:34Z --timeout 600 --interval 30)
check "--brief quotes the comment notice's line" "since $notice_text" \
  "$(jq -r '[.refused_by, .reviewer_blocked] | join(" ")' <<<"$out")"

reset
reviews '[]' '[]'
blocked_at 2026-09-23T14:20:00Z
out=$(poll --since 2026-09-23T14:22:34Z --timeout 0 --interval 1)
check "a comment notice before --since refuses nothing" null "$(jq -r '.refused_by' <<<"$out")"

# A comment is tied to no commit, so the head rule leaves it to review rows.
reset
reviews '[]' '[]'
blocked_at 2026-09-23T14:30:00Z
out=$( ( cd "$repo" && bash "$mech" 7 --reviewer copilot-push --timeout 0 --interval 1 ) )
check "under the head rule a comment-only notice refuses nothing" null "$(jq -r '.refused_by' <<<"$out")"

finish
