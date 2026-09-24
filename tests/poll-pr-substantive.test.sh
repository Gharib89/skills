#!/usr/bin/env bash
# poll-pr grades review rows itself, over whatever `host_pr_reviews` answers, so
# the landing and refusal rules read the same grade on every host (#268). The
# Azure DevOps adapter still sends `substantive: true` on every row, a notice
# thread included; the rows below carry what each adapter sends, and poll-pr's
# grade is what decides.
#
# Driven end to end over the Host fake inside a throwaway checkout whose origin
# names GitHub, so the mechanic's own loop is the subject: no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### voter

Login: voter@example.com
Trigger: on-push
Request: None.
Cap: None.
Gating: no

### voter-request

Login: voter@example.com
Trigger: on-request
Request: None.
Cap: 3
Gating: no

## Coding standards
EOF

since=2026-09-24T09:00:00Z
notice_text='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'
reset() { # <row>: the one review row the host answers with, on the head and in all[]
  rm -f "$SHIP_FAKE"/*
  jq -cn --argjson r "$1" '{on_head: [$r], all: [$r], total: 1}' > "$SHIP_FAKE/host_pr_reviews.1.json"
  printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
poll() { ( cd "$repo" && bash "$mech" 7 --interval 1 --timeout 0 "$@" ); }
graded() { jq -r '[.reviews.on_head[0].substantive, .reviews.all[0].substantive] | map(tostring) | unique | join(" ")'; }
rules() { jq -r '[.landed_by, .refused_by] | map(tostring) | join(" ")'; }

# The Azure DevOps vote row: state alone, no id, no time, no body.
vote='{"id": null, "login": "voter@example.com", "state": "approved", "substantive": true, "submitted_at": null, "body": ""}'
reset "$vote"
out=$(poll --reviewer voter); rc=$?
check_rc "an Azure DevOps vote lands under the head rule" 0 "$rc"
check "as head" head "$(jq -r .landed_by <<<"$out")"
out=$(poll --reviewer voter-request --since "$since")
check "and not under the since rule, which cannot time it" 'null null' \
  "$(rules <<<"$out")"

# The Azure DevOps notice-only thread: the adapter still calls it substantive.
thread=$(jq -cn --arg b "$notice_text" \
  '{id: "41", login: "voter@example.com", state: "comment", substantive: true, submitted_at: "2026-09-24T09:05:00Z", body: $b}')
reset "$thread"
out=$(poll --reviewer voter-request --since "$since"); rc=$?
check_rc "an Azure DevOps notice thread lands nothing" 1 "$rc"
check "it refuses the round instead" 'null since' \
  "$(rules <<<"$out")"
check "because poll-pr's grade overwrote the adapter's" false "$(graded <<<"$out")"
out=$(poll --reviewer voter)
check "and under the head rule too" head "$(jq -r .refused_by <<<"$out")"

# The GitHub bodiless approval: the adapter sends no grade at all.
approval='{"id": "9", "login": "voter@example.com", "state": "approved", "submitted_at": "2026-09-24T09:05:00Z", "body": ""}'
reset "$approval"
out=$(poll --reviewer voter-request --since "$since"); rc=$?
check_rc "a GitHub bodiless approval lands" 0 "$rc"
check "under the since rule" since "$(jq -r .landed_by <<<"$out")"
check "graded substantive" true "$(graded <<<"$out")"

# A bodiless comment row: a reviewer's reply to one thread, not a round.
reply='{"id": "10", "login": "voter@example.com", "state": "comment", "submitted_at": "2026-09-24T09:05:00Z", "body": ""}'
reset "$reply"
out=$(poll --reviewer voter-request --since "$since"); rc=$?
check_rc "a bodiless comment row lands nothing" 1 "$rc"
check "and refuses nothing" 'null null' \
  "$(rules <<<"$out")"
check "graded not substantive" false "$(graded <<<"$out")"

# --brief reads the same graded rows.
reset "$approval"; printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
check "--brief carries poll-pr's grade" true \
  "$(poll --reviewer voter-request --since "$since" --brief | jq -r '.rounds[0].substantive')"

finish
