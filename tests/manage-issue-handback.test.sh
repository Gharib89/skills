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
# The order a hand-back writes in: the agent label comes off and is read back
# gone before the unassign, so an unattended selection never finds the issue
# unassigned and still ready-for-agent. Reads: 1 the opening, 2 the removal's
# read-back, 3 the unassign's, 4 the human label's.
reset() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"number":7,"state":"open","assignees":["me"],"labels":["ready-for-agent"]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
  printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
  printf '{"number":7,"state":"open","assignees":[],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.3.json"
  printf '{"number":7,"state":"open","assignees":[],"labels":["ready-for-human"]}\n' > "$SHIP_FAKE/host_issue_get.4.json"
}
# The host calls made, in order, as one line.
calls() { cut -f1 "$SHIP_FAKE/calls" | tr '\n' ' '; }

reset
out=$(run 7 handback "a reason"); rc=$?
check_rc "a hand-back whose writes land exits 0" 0 "$rc"
check "a hand-back whose writes land is handed back" true "$(jq -r .handed_back <<<"$out")"
check "a hand-back whose writes land says nothing on stderr" "" "$(cat "$work/err")"
check "a hand-back removes the agent label and reads it back before the unassign" \
  'host_identity host_issue_get host_issue_remove_label host_issue_get host_issue_unassign host_issue_get host_issue_add_label host_issue_get host_issue_comment ' "$(calls)"
check "a hand-back that lands ends released, human-marked and commented" \
  'released ready-for-human true' "$(jq -r '"\(.claim) \(.labels.added) \(.commented)"' <<<"$out")"

# A removal that failed, went unconfirmed or did not land keeps the claim: the
# issue is still ready-for-agent, so unassigning it would hand it to a selection.
kept() { # <case> : the answer, exit and calls of a hand-back that kept the claim
  check_rc "$1 exits 1" 1 "$rc"
  check "$1 says the claim was kept" 'held' "$(jq -r .claim <<<"$out")"
  check "$1 names the kept claim in its error" true "$(jq -r '.error | test("the claim was kept")' <<<"$out")"
  check "$1 never unassigns" 0 "$(calls | grep -c host_issue_unassign)"
  check "$1 writes no human label or comment" 0 "$(calls | grep -c 'host_issue_add_label\|host_issue_comment')"
}
reset
: > "$SHIP_FAKE/host_issue_remove_label.1.fail"
out=$(run 7 handback "a reason"); rc=$?
kept "a removal call that failed"

reset
: > "$SHIP_FAKE/host_issue_get.2.fail"
out=$(run 7 handback "a reason"); rc=$?
kept "a removal read-back that failed"

# An issue this run no longer holds has no claim to keep: the answer must not say one was.
reset
printf '{"number":7,"state":"open","assignees":[],"labels":["ready-for-agent"]}\n' > "$SHIP_FAKE/host_issue_get.1.json"
: > "$SHIP_FAKE/host_issue_remove_label.1.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "a removal that failed on an unassigned issue exits 1" 1 "$rc"
check "a removal that failed on an unassigned issue claims no kept claim" \
  'released false' "$(jq -r '"\(.claim) \(.error | test("claim was kept"))"' <<<"$out")"

reset
printf '{"number":7,"state":"open","assignees":["me"],"labels":["ready-for-agent"]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
out=$(run 7 handback "a reason"); rc=$?
kept "a removal that did not land"

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
: > "$SHIP_FAKE/host_issue_get.3.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "a re-read that failed after the unassign exits 1" 1 "$rc"
check "a re-read that failed after the unassign says the release is unconfirmed" \
  'cannot re-read issue #7 after unassigning: the release is unconfirmed; re-read the issue before reporting it' "$(jq -r .error <<<"$out")"

# release on its own touches no label: the claim comes off and nothing else.
reset
printf '{"number":7,"state":"open","assignees":[],"labels":["ready-for-agent"]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
out=$(run 7 release); rc=$?
check_rc "a release exits 0" 0 "$rc"
check "a release answers released" true "$(jq -r '.claim == "released"' <<<"$out")"
check "a release makes no label call" 'host_identity host_issue_get host_issue_unassign host_issue_get ' "$(calls)"

reset
printf '{"number":7,"state":"open","assignees":["me"],"labels":[]}\n' > "$SHIP_FAKE/host_issue_get.2.json"
out=$(run 7 release); rc=$?
check_rc "an unassign that did not land exits 1" 1 "$rc"
check "an unassign that did not land says the claim is still held" \
  'unassign did not land: the claim is still held' "$(jq -r .error <<<"$out")"

# The reads before any write fail as tooling, and nothing was written, so the
# claim is as the run left it: the answer says so rather than leaving it to prose.
reset
: > "$SHIP_FAKE/host_identity.1.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "an identity read that failed is tooling" 2 "$rc"
check "an identity read that failed says the claim is unchanged" \
  'cannot read the signed-in identity: nothing was written, so the claim is as it was' "$(jq -r .error <<<"$out")"

reset
: > "$SHIP_FAKE/host_issue_get.1.fail"
out=$(run 7 handback "a reason"); rc=$?
check_rc "an issue read that failed is tooling" 2 "$rc"
check "an issue read that failed says the claim is unchanged" \
  'cannot read issue #7: nothing was written, so the claim is as it was' "$(jq -r .error <<<"$out")"

finish
