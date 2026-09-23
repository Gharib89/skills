#!/usr/bin/env bash
# request-review --reviewer <name> driven end to end over the Host fake (#235):
# the block's `Request:` picks the transport, so the call the host is handed is
# the subject. A throwaway checkout whose origin names GitHub carries a copy of
# this repo's own profile, whose `claude` is a comment transport and whose
# `copilot` is the host's request call.
#
# The comment transport posts a temp file it deletes on exit, so this test's
# adapter is the fake with its `host_pr_comment` keeping a copy of that file:
# the phrase posted is asserted, not just the path it sat at.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'

mech=$PWD/skills/ship/scripts/request-review.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cp docs/agents/ship.md "$repo/docs/agents/ship.md"
cat > "$work/adapter.sh" <<ADAPTER
source "$PWD/tests/host-fake.sh" || return 1
host_pr_comment() { cp "\$2" "\$SHIP_FAKE/posted"; _host_fake host_pr_comment "\$@"; }
ADAPTER
export SHIP_HOST_ADAPTER=$work/adapter.sh

run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
printf '%s\n' '{"id": 5, "url": "https://example.invalid/pull/7#issuecomment-5", "created_at": "2026-09-17T12:01:02Z"}' \
  > "$SHIP_FAKE/host_pr_comment.1.json"
out=$(run 7 --reviewer claude); rc=$?
check_rc "the comment transport exits 0" 0 "$rc"
check "the phrase posted is the block's" '@claude' "$(cat "$SHIP_FAKE/posted")"
check "one comment is the whole call list" 'host_pr_comment' "$(cut -f1 "$SHIP_FAKE/calls" | tr '\n' ' ' | sed 's/ $//')"
check "the comment's created_at is requested_at, with name and login" \
  '{"pr":7,"name":"claude","login":"claude[bot]","requested":true,"readback":["https://example.invalid/pull/7#issuecomment-5"],"requested_at":"2026-09-17T12:01:02Z"}' \
  "$(jq -c . <<<"$out")"

reset
printf '%s\n' '{"requested": true, "readback": ["copilot-pull-request-reviewer[bot]"], "requested_at": "2026-09-17T12:03:04Z"}' \
  > "$SHIP_FAKE/host_pr_request_review.1.json"
out=$(run 7 --reviewer copilot); rc=$?
check_rc "the host's request call exits 0" 0 "$rc"
check "the host is asked for the block's login, once" \
  "host_pr_request_review${T}7${T}copilot-pull-request-reviewer[bot]" "$(cat "$SHIP_FAKE/calls")"
check "and the read-back comes back with the name" \
  '{"pr":7,"name":"copilot","login":"copilot-pull-request-reviewer[bot]","requested":true,"readback":["copilot-pull-request-reviewer[bot]"],"requested_at":"2026-09-17T12:03:04Z"}' \
  "$(jq -c . <<<"$out")"

reset
out=$(run 7 --reviewer nobody 2>/dev/null); rc=$?
check_rc "a name no block carries is tooling" 2 "$rc"
check "and lists the names the profile carries" \
  'no ## Reviewers block is named nobody; the profile names: copilot, claude' "$(jq -r .error <<<"$out")"
check "and reaches no host" '' "$(cat "$SHIP_FAKE/calls" 2>/dev/null)"

finish
