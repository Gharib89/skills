#!/usr/bin/env bash
# The fallback reviewer over the Host fake. The review loop (review-loop.md)
# requests a fallback exactly when its primary exits `not reviewed`, and a
# primary's exit is `not reviewed: <cause>` where no round of it landed, the
# cause being poll-pr's `not_reviewed` or request-review's exit 1
# (never-queued). That branch is prose; `loop` below transcribes it over the
# real mechanics, so each case holds the signals it reads end to end and the
# fallback's request to the transport its own block names.
#
# Driven inside a throwaway checkout whose origin names GitHub, with
# SHIP_HOST_ADAPTER on tests/host-fake.sh: no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 3
Gating: no
Fallback-for: None.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 3
Gating: no
Fallback-for: copilot

## Coding standards
PROFILE

at=2026-09-25T10:00:00Z
row() { # <login> <id>
  jq -cn --arg l "$1" --arg i "$2" \
    '{id: $i, login: $l, state: "comment", submitted_at: "2026-09-25T10:05:00Z", body: "- a finding"}'
}
reset() {
  rm -f "$SHIP_FAKE"/*
  jq -cn '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
  printf '{"on_head":[],"all":[],"total":0}\n' > "$SHIP_FAKE/host_pr_reviews.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
  jq -cn --arg a "$at" '{requested: true, readback: ["Copilot"], requested_at: $a}' \
    > "$SHIP_FAKE/host_pr_request_review.1.json"
  jq -cn --arg a "$at" '{id: 1, url: "https://example.invalid/c/1", created_at: $a}' \
    > "$SHIP_FAKE/host_pr_comment.1.json"
}
run() { ( cd "$repo" && bash "$scripts/$1.sh" 7 "${@:2}" ); }
poll() { run poll-pr --reviewer "$1" --since "$at" --timeout 0 --interval 1; }
calls() { cat "$SHIP_FAKE/calls" 2>/dev/null | grep -c "^host_$1" || true; }
# The loop's primary step: request, poll, and the primary's exit.
primary_exit() {
  local out
  out=$(run request-review --reviewer copilot) || { echo "not reviewed: never-queued"; return; }
  out=$(poll copilot)
  if [ "$(jq -r .not_reviewed <<<"$out")" = null ]; then echo reviewed
  else echo "not reviewed: $(jq -r .not_reviewed <<<"$out")"; fi
}
# review-loop.md's Fallbacks: request the fallback on a `not reviewed` primary,
# report it `not invoked` on a reviewed one. Prints both exits, one per line.
loop() {
  local p; p=$(primary_exit); echo "$p"
  case $p in
    "not reviewed"*) run request-review --reviewer claude > "$work/fallback" && echo requested ;;
    *) echo "not invoked: copilot reviewed" ;;
  esac
}

# A primary that answers nothing inside its bound: not reviewed, and the
# fallback is requested through its own transport, a PR comment of its phrase.
reset
check "a silent primary is not reviewed, and the fallback requested" \
  "$(printf 'not reviewed: silent\nrequested')" "$(loop)"
check "as a comment of its phrase" 1 "$(calls pr_comment)"
check "the fallback is on its own block's login" 'claude claude[bot]' \
  "$(jq -r '[.name, .login] | join(" ")' "$work/fallback")"

# A quota-out Copilot: the request never reads back, request-review exits 1,
# and the fallback is due without a poll of the primary.
reset
jq -cn --arg a "$at" '{requested: false, readback: [], requested_at: $a}' \
  > "$SHIP_FAKE/host_pr_request_review.1.json"
check "a request never read back is never-queued, and the fallback requested" \
  "$(printf 'not reviewed: never-queued\nrequested')" "$(loop)"
check "and no poll of the primary was spent" 0 "$(calls pr_reviews)"

# A primary that reviews: reviewed, and nothing requests the fallback, which
# reports `not invoked: copilot reviewed`.
reset
jq -cn --argjson r "$(row 'copilot-pull-request-reviewer[bot]' 2)" '{on_head: [$r], all: [$r], total: 1}' \
  > "$SHIP_FAKE/host_pr_reviews.1.json"
check "a primary whose round landed is reviewed, the fallback not invoked" \
  "$(printf 'reviewed\nnot invoked: copilot reviewed')" "$(loop)"
check "and no fallback request was posted" 0 "$(calls pr_comment)"

finish
