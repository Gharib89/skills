#!/usr/bin/env bash
# The happy-path verdict of Ship's live run (scripts/live-run-ship.sh), read from
# records alone: the run's Run file and the fixture's host state. It never reads
# the model's wording and never checks the content of the change.
#
#   scripts/live-run-checks.sh <run-file> <host-json> <issue>
#   <host-json>: {"assignees": [<login>...], "open_prs": [{"number", "body"}...]}
#   PR_TEMPLATE: the fixture's PR template, which scripts/check-pr-body.sh reads
#
# stdout: one failed check per line, `<check>: <what failed>`
# exit:   0 every check passed · 1 a check failed · 2 tooling
set -uo pipefail

[ $# -eq 3 ] || { echo 'usage: scripts/live-run-checks.sh <run-file> <host-json> <issue>' >&2; exit 2; }
run=$1 host=$2 issue=$3
command -v jq >/dev/null || { echo 'jq not installed' >&2; exit 2; }
jq -e 'has("assignees") and has("open_prs")' "$host" >/dev/null 2>&1 \
  || { echo "host state unreadable: $host" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

failed=0
fail() { printf '%s\n' "$1"; failed=1; }

if [ ! -f "$run" ]; then
  fail "run file: missing"
else
  # Every phase before the merge gate is `[x]`, closed or skipped. A closed one
  # carries `(HH:MM→HH:MM)`; its start may not precede the last closed phase's
  # start, since `run-file next` opens a phase only after its predecessor.
  last=""
  for n in 0 1 2 3 4 5 6 7 8; do
    line=$(grep -m1 "^- \[[ x]\] $n · " "$run")
    case $line in "- [x] "*) ;; *) fail "phase $n: not closed"; continue ;; esac
    start=$(printf '%s' "$line" | sed -n 's/.*(\([0-9][0-9]:[0-9][0-9]\)→[0-9:]*)$/\1/p')
    [ -n "$start" ] || continue
    if [ -n "$last" ] && [[ "$start" < "$last" ]]; then fail "phase $n: closed out of order"; fi
    last=$start
  done
  grep -q -E '^- \[x\] 9 · |^- \[ \] 9 · .* in_progress \(' "$run" || fail "merge gate: not reached"
fi

[ "$(jq '.assignees | length' "$host")" -gt 0 ] || fail "issue: not claimed"

# GitHub's closing keywords, the way the host links a PR to the issue it closes.
closing=$(jq --arg n "$issue" '[.open_prs[]
  | select(.body // "" | test("\\b(close[sd]?|fix(e[sd])?|resolve[sd]?) #" + $n + "\\b"; "i"))]' "$host")
count=$(jq length <<<"$closing")
if [ "$count" -ne 1 ]; then
  fail "pr: $count open PRs close #$issue, want 1"
else
  out=$(jq -r '.[0].body' <<<"$closing" | bash "$here/check-pr-body.sh" 2>/dev/null)
  case $? in
    0) ;;
    1) while IFS= read -r l; do fail "pr body: $l"; done <<<"$out" ;;
    *) echo 'check-pr-body.sh: tooling failure' >&2; exit 2 ;;
  esac
fi

exit "$failed"
