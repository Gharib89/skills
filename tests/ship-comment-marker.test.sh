#!/usr/bin/env bash
# Ship's own comments carry one hidden marker line, so a read can tell a claim or
# a hand-back from a human's comment without reading its wording: every
# mechanic that posts an issue or PR comment appends the marker to the body, and
# read-issue marks a comment `ship: true` where the marker is present. Driven
# over the Host fake, whose calls log shows the body each mechanic handed the
# host (a newline inside it written as `\n`) and whose host_pr_comment and
# host_pr_reply_thread here also keep a copy of the body file they were given.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

scripts=$PWD/skills/ship/scripts
M='<!-- ship -->'
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cat > "$work/adapter.sh" <<ADAPTER
source "$PWD/tests/host-fake.sh" || return 1
host_pr_comment() { cp "\$2" "\$SHIP_FAKE/posted"; _host_fake host_pr_comment "\$@"; }
host_pr_reply_thread() { cp "\$3" "\$SHIP_FAKE/posted"; _host_fake host_pr_reply_thread "\$@"; }
ADAPTER
export SHIP_HOST_ADAPTER=$work/adapter.sh

mech() { local m=$1; shift; ( cd "$repo" && bash "$scripts/$m.sh" "$@" 2>/dev/null ); }
reset() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '[]\n' > "$SHIP_FAKE/host_issue_blockers_open.1.json"
}
last_body() { grep "^$1${T}" "$SHIP_FAKE/calls" | tail -1 | cut -f"$2"; }

# read-issue: the marker, wherever it sits in the body, is what makes `ship` true.
reset
printf '{"number":7,"title":"t","body":"","state":"open","is_pr":false,"labels":[],"assignees":[]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
printf '[{"author":"me","body":"claimed\\n%s","created_at":"2026-10-01T00:00:00Z"},{"author":"a-human","body":"I will take this","created_at":"2026-10-02T00:00:00Z"},{"author":"a-human","body":"quoting a claim: 🤖 Claimed by a ship run","created_at":"2026-10-03T00:00:00Z"}]\n' "$M" \
  > "$SHIP_FAKE/host_issue_comments.1.json"
check "a comment carrying the marker is ship's, one without is not" '[true,false,false]' \
  "$(mech read-issue 7 | jq -c '[.comments[].ship]')"
reset
printf '{"number":7,"state":"open","is_pr":false,"labels":[],"assignees":[]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
printf '[]\n' > "$SHIP_FAKE/host_issue_comments.1.json"
check "an issue with no comments reads an empty list" '[]' "$(mech read-issue 7 | jq -c '.comments')"

# manage-issue: the claim and the hand-back.
reset
printf '{"number":7,"state":"open","assignees":[],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
mech manage-issue 7 take >/dev/null
check "the claim comment carries the marker on its own line" "🤖 Claimed by a ship run: implementation in progress.\\n$M" \
  "$(last_body host_issue_comment 3)"

reset
printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
printf '{"number":7,"state":"open","assignees":[],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
printf '{"number":7,"state":"open","assignees":[],"labels":["ready-for-human"]}\n' > "$SHIP_FAKE/host_issue_get.4.json"
mech manage-issue 7 handback "a reason" >/dev/null
check "the hand-back comment carries the marker" "🤖 Handed back by a ship run: a reason\\n$M" \
  "$(last_body host_issue_comment 3)"

# reflect: the PR line is marked, and an issue already carrying the line, marked
# or not, is not commented twice.
reset
printf '{"url":"https://example.invalid/pull/8"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
printf '[]\n' > "$SHIP_FAKE/host_issue_comments.1.json"
mech reflect 7 8 >/dev/null
check "the reflected PR line carries the marker" "PR: https://example.invalid/pull/8\\n$M" \
  "$(last_body host_issue_comment 3)"
reset
printf '{"url":"https://example.invalid/pull/8"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
printf '[{"author":"me","body":"PR: https://example.invalid/pull/8\\n%s","created_at":"2026-10-01T00:00:00Z"}]\n' "$M" > "$SHIP_FAKE/host_issue_comments.1.json"
check "a marked PR line already there is not posted again" false "$(mech reflect 7 8 | jq -r .posted)"
printf '[{"author":"me","body":"PR: https://example.invalid/pull/8","created_at":"2026-10-01T00:00:00Z"}]\n' > "$SHIP_FAKE/host_issue_comments.1.json"
check "nor is an unmarked one from before the marker" false "$(mech reflect 7 8 | jq -r .posted)"

# The body-file mechanics: the file the host receives is the caller's file with
# the marker appended, and the caller's own file is left as it was.
printf 'round summary\n' > "$work/body.md"
reset
mech comment-issue 7 --body-file "$work/body.md" >/dev/null
check "comment-issue posts the file's bytes then the marker" "round summary\\n$M\\n" "$(last_body host_issue_comment 3)"
reset
mech comment-pr 7 --body-file "$work/body.md" >/dev/null
check "comment-pr hands the host the file then the marker" "round summary
$M" "$(cat "$SHIP_FAKE/posted")"
check "and leaves the caller's file alone" 'round summary' "$(cat "$work/body.md")"
reset
mech reply-thread 7 t1 --body-file "$work/body.md" >/dev/null
check "reply-thread hands the host the file then the marker" "round summary
$M" "$(cat "$SHIP_FAKE/posted")"

# request-review's comment transport: the request phrase still opens the body,
# which is where a comment-triggered workflow looks for it.
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## Reviewers

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Gating: no
Fallback-for: None.

## Coding standards
PROFILE
reset
mech request-review 7 --reviewer claude >/dev/null
check "the request comment opens with the phrase and ends with the marker" "@claude
$M" "$(cat "$SHIP_FAKE/posted")"

finish
