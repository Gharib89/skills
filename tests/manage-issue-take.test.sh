#!/usr/bin/env bash
# manage-issue take driven end to end over the Host fake (tests/host-fake.sh)
# (#636). Preflight refuses an assigned issue, but phase 0 runs between it and
# `take`, so two runs can both reach the assign: GitHub assignees are additive
# and Azure DevOps' Assigned To is last-write-wins, and either way the read-back
# shows another identity. That run answers `contested`, gives its own
# assignment back, and fails. A fresh run passes --fresh, refusing `held`: an
# issue its own identity holds was taken by another run of that identity since
# preflight read it unassigned.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/manage-issue.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run() { ( cd "$repo" && bash "$mech" "$@" 2>"$work/err" ); }
# Read 1 is the issue before the assign, read 2 the read-back after it.
reset() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"number":7,"state":"open","assignees":%s,"labels":[]}\n' "$1" > "$SHIP_FAKE/host_issue_get.1.json"
  [ -z "${2:-}" ] || printf '{"number":7,"state":"open","assignees":%s,"labels":[]}\n' "$2" > "$SHIP_FAKE/host_issue_get.2.json"
}
calls() { grep -c "^$1" "$SHIP_FAKE/calls"; }

reset '[]' '["me"]'
out=$(run 7 take); rc=$?
check_rc "an unassigned issue is taken" 0 "$rc"
check "and answers taken" taken "$(jq -r .claim <<<"$out")"

reset '[]' '["me"]'
out=$(run 7 take --fresh); rc=$?
check_rc "a fresh run takes an unassigned issue" 0 "$rc"
check "and answers taken" taken "$(jq -r .claim <<<"$out")"

reset '["me"]'
out=$(run 7 take); rc=$?
check_rc "an issue this identity holds is held" 0 "$rc"
check "and answers held" held "$(jq -r .claim <<<"$out")"

reset '["me"]'
out=$(run 7 take --fresh); rc=$?
check_rc "a fresh run refuses an issue this identity already holds" 1 "$rc"
check "and answers held, saying another run of this identity holds it" 'held held: another run of this identity holds it' \
  "$(jq -r '"\(.claim) \(.error)"' <<<"$out")"
check "and writes nothing" 0 "$(calls 'host_issue_\(assign\|unassign\|comment\)')"

# A read-back whose assignees cannot be read is no verdict on who holds it.
reset '[]' 'null'
out=$(run 7 take); rc=$?
check_rc "a read-back with unreadable assignees fails" 1 "$rc"
check "and says so" 'cannot read the assignees of issue #7 after assigning' "$(jq -r .error <<<"$out")"

# GitHub: assignees are additive, so the read-back holds both.
reset '[]' '["bob","me"]'
out=$(run 7 take); rc=$?
check_rc "a read-back holding another identity too is contested" 1 "$rc"
check "and answers contested, naming the other" 'contested bob' "$(jq -r '"\(.claim) \(.others | join(","))"' <<<"$out")"
check "and gives this run's assignment back" "host_issue_unassign${T}7${T}me" "$(grep '^host_issue_unassign' "$SHIP_FAKE/calls")"
check "and posts no claim comment" 0 "$(calls host_issue_comment)"

# Azure DevOps: the later write replaced this one, so there is nothing to give
# back, and an unassign there would clear the other run's claim.
reset '[]' '["bob"]'
out=$(run 7 take); rc=$?
check_rc "a read-back holding only another identity is contested" 1 "$rc"
check "and answers contested" contested "$(jq -r .claim <<<"$out")"
check "and unassigns nobody" 0 "$(calls host_issue_unassign)"

finish
