#!/usr/bin/env bash
# manage-issue's release and handback driven end to end over the Host fake
# (tests/host-fake.sh). The subject is what a failed step tells the run: a
# hand-back whose label edit missed has still released the claim, and an
# unassign that missed or went unconfirmed may not have, so each answer
# carries which one it is.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/manage-issue.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run()   { ( cd "$repo" && bash "$mech" "$@" 2>"$work/err" ); }
# An assigned issue, then the same issue unassigned for the re-read after it.
reset() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
  printf '{"number":7,"state":"open","assignees":[],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
  # The removed label reads absent, the added one present.
  : > "$SHIP_FAKE/host_issue_has_label.1.fail"
  printf '' > "$SHIP_FAKE/host_issue_has_label.2.json"
}

reset
out=$(run 7 handback "a reason"); rc=$?
check_rc "a hand-back whose writes land exits 0" 0 "$rc"
check "a hand-back whose writes land is handed back" true "$(jq -r .handed_back <<<"$out")"
check "a hand-back whose writes land says nothing on stderr" "" "$(cat "$work/err")"

reset
: > "$SHIP_FAKE/host_issue_add_label.1.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "a hand-back whose label add missed exits 1" 1 "$rc"
check "a hand-back whose label add missed has released the claim" \
  'released false' "$(jq -r '"\(.claim) \(.handed_back)"' <<<"$out")"
check "a hand-back whose label add missed says what to report" \
  'the claim is released but the hand-back is incomplete: report the labels left null under labels, not a clean stop' \
  "$(cat "$work/err")"

reset
: > "$SHIP_FAKE/host_issue_unassign.1.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "an unassign that failed exits 1" 1 "$rc"
check "an unassign that failed says the claim may still be held" \
  'unassign call failed: the claim may still be held; re-read the issue before reporting it' "$(jq -r .error <<<"$out")"

reset
: > "$SHIP_FAKE/host_issue_get.2.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "a re-read that failed after the unassign exits 1" 1 "$rc"
check "a re-read that failed after the unassign says the release is unconfirmed" \
  'cannot re-read issue #7 after unassigning: the release is unconfirmed; re-read the issue before reporting it' "$(jq -r .error <<<"$out")"

reset
printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
out=$(run 7 release); rc=$?
check_rc "an unassign that did not land exits 1" 1 "$rc"
check "an unassign that did not land says the claim is still held" \
  'unassign did not land: the claim is still held' "$(jq -r .error <<<"$out")"

finish
