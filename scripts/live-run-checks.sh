#!/usr/bin/env bash
# The verdict of one Ship live run (scripts/live-run-ship.sh), read from records
# alone: the run's Run file and the fixture's host state. It never reads the
# model's wording and never checks the content of the change.
#
#   scripts/live-run-checks.sh [--ambiguous] <run-file> <host-json> <issue>
#   <host-json>: {"assignees": [<login>...], "open_prs": [{"number", "body"}...]},
#                plus "branches": [<the run's branch>...] with --ambiguous
#   PR_TEMPLATE: the fixture's PR template, which scripts/check-pr-body.sh reads
#
# Without a flag it judges the happy path: the run reached the merge gate with
# one PR. --ambiguous judges the early stop on a vague issue: the run stopped in
# phase 1 with no claim, no PR closing the issue and no branch.
#
# stdout: one failed check per line, `<check>: <what failed>`
# exit:   0 every check passed · 1 a check failed · 2 tooling
set -uo pipefail

ambiguous=false
[ "${1:-}" = --ambiguous ] && { ambiguous=true; shift; }
[ $# -eq 3 ] || { echo 'usage: scripts/live-run-checks.sh [--ambiguous] <run-file> <host-json> <issue>' >&2; exit 2; }
run=$1 host=$2 issue=$3
command -v jq >/dev/null || { echo 'jq not installed' >&2; exit 2; }
jq -e --argjson amb "$ambiguous" '(.assignees | type == "array") and (.open_prs | type == "array")
  and (($amb | not) or (.branches | type == "array"))' "$host" >/dev/null 2>&1 \
  || { echo "host state unreadable: $host" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# ship_body_closes: whether a PR closes the issue is read the way Ship reads it.
# shellcheck source=../skills/ship/scripts/_lib.sh
source "$here/../skills/ship/scripts/_lib.sh"

failed=0
fail() { printf '%s\n' "$1"; failed=1; }

# A phase is opened once its line is `[x]` or ends in a time range.
opened() { grep -qE "^- \[x\] $1 · |^- \[ \] $1 · .* \([0-9]{2}:[0-9]{2}→[^)]*\)\$" "$run"; }

if [ ! -f "$run" ]; then
  fail "run file: missing"
elif [ "$ambiguous" = true ]; then
  grep -q '^- \[x\] 0 · ' "$run" || fail "phase 0: not closed"
  grep -q '^- \[x\] 1 · ' "$run" && fail "phase 1: closed"
  for n in 2 3 4 5 6 7 8 9; do opened "$n" && fail "phase $n: opened"; done
else
  # Every phase before the merge gate is `[x]`, closed or skipped. A closed one
  # carries `(HH:MM→HH:MM)`, the end `+1d` past midnight, and a re-open appends
  # a range after it; its first start may not precede the last closed phase's,
  # since `run-file next` opens a phase only after its predecessor. A drop of
  # 12 hours or more is the clock wrapping at midnight, not an earlier start.
  # Only the trailing run of ranges is time, as run-file reads it: a range
  # inside the item text or a skip reason is wording.
  last=""
  for n in 0 1 2 3 4 5 6 7 8; do
    line=$(grep -m1 "^- \[[ x]\] $n · " "$run")
    case $line in "- [x] "*) ;; *) fail "phase $n: not closed"; continue ;; esac
    start=$(grep -oE '( \([0-9]{2}:[0-9]{2}→[0-9]{2}:[0-9]{2}(\+1d)?\))+$' <<<"$line" \
      | grep -oE '\([0-9]{2}:[0-9]{2}→' | head -n 1)
    [ -n "$start" ] || continue
    m=$(( 10#${start:1:2} * 60 + 10#${start:4:2} ))
    if [ -n "$last" ] && [ "$m" -lt "$last" ] && [ $(( last - m )) -lt 720 ]; then
      fail "phase $n: closed out of order"
    fi
    last=$m
  done
  grep -q -E '^- \[x\] 9 · |^- \[ \] 9 · .* in_progress \(' "$run" || fail "merge gate: not reached"
fi

claimed=$(jq '.assignees | length > 0' "$host")
if [ "$ambiguous" = true ]; then
  [ "$claimed" = false ] || fail "issue: claimed"
else
  [ "$claimed" = true ] || fail "issue: not claimed"
fi

bodies=() i=0
while [ "$i" -lt "$(jq '.open_prs | length' "$host")" ]; do
  body=$(jq -r --argjson i "$i" '.open_prs[$i].body // ""' "$host")
  ship_body_closes "$body" "$issue"
  case $? in
    0) bodies+=("$body") ;;
    1) ;;
    *) echo 'ship_body_closes: tooling failure' >&2; exit 2 ;;
  esac
  i=$(( i + 1 ))
done
if [ "$ambiguous" = true ]; then
  [ "${#bodies[@]}" -eq 0 ] || fail "pr: ${#bodies[@]} open PRs close #$issue, want 0"
  while IFS= read -r b; do [ -z "$b" ] || fail "branch: $b pushed"; done < <(jq -r '.branches[]' "$host")
elif [ "${#bodies[@]}" -ne 1 ]; then
  fail "pr: ${#bodies[@]} open PRs close #$issue, want 1"
else
  out=$(printf '%s\n' "${bodies[0]}" | bash "$here/check-pr-body.sh" 2>/dev/null)
  case $? in
    0) ;;
    1) while IFS= read -r l; do fail "pr body: $l"; done <<<"$out" ;;
    *) echo 'check-pr-body.sh: tooling failure' >&2; exit 2 ;;
  esac
fi

exit "$failed"
