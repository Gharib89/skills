#!/usr/bin/env bash
# `host_run_denials`: the GitHub adapter's count of the tool calls a Claude
# round was refused, read from the `claude-review` warning annotation the
# scaffolded reviewer job raises (#283). The function runs with the adapter's
# `api` redefined to answer fixtures per endpoint, shaped as the probes of runs
# 36109663226 and 36106330330 answered, so no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

url=https://github.com/o/r/actions/runs/36109663226
notice='{"annotation_level":"notice","title":"","message":"The ubuntu-latest label will migrate"}'
warn() { jq -cn --arg m "$1" '{annotation_level: "warning", title: "claude-review", message: $m}'; }

# Each read answers what its own `--jq` would have printed: the jobs read one
# job id per line, the annotations read one annotation per line.
# The adapter calls `api` inside command substitutions, so the log of the
# endpoints it read is a file rather than a variable a subshell would lose.
log=$(mktemp); trap 'rm -f "$log"' EXIT
reads() { : > "$log"; host_run_denials "$1" >/dev/null 2>&1; tr '\n' ' ' < "$log"; }
JOBS='107990002620' ANN='' FAIL=''
api() {
  printf '%s\n' "$1" >> "$log"
  case $1 in
    repos/o/r/actions/runs/36109663226/jobs) [ "$FAIL" != jobs ] || return 1; printf '%s\n' "$JOBS" ;;
    repos/o/r/check-runs/*/annotations) [ "$FAIL" != annotations ] || return 1; printf '%s' "$ANN" ;;
    *) echo "unexpected api call: $*" >&2; return 1 ;;
  esac
}

ANN=$(printf '%s\n%s\n' "$(warn "2 tool call(s) denied; this step's log names each on a denied: line")" "$notice")
check "the claude-review warning's leading number is the count" '{"denied":2}' \
  "$(host_run_denials "$url" | jq -c .)"
check "the count reads the run's job, then that job's annotations" \
  "repos/o/r/actions/runs/36109663226/jobs repos/o/r/check-runs/107990002620/annotations " \
  "$(reads "$url")"

ANN=$notice
check "a run with no claude-review warning denied nothing" '{"denied":0}' \
  "$(host_run_denials "$url" | jq -c .)"

# The leading number, not the wording: the message may change around it.
ANN=$(warn "3 calls refused")
check "only the leading number is parsed" '{"denied":3}' "$(host_run_denials "$url" | jq -c .)"

# A notice titled claude-review is not the count, nor a warning with another title.
ANN=$(printf '%s\n%s\n' \
  '{"annotation_level":"notice","title":"claude-review","message":"5 things"}' \
  '{"annotation_level":"warning","title":"other","message":"7 things"}')
check "only a warning titled claude-review counts" '{"denied":0}' \
  "$(host_run_denials "$url" | jq -c .)"

# A warning whose message leads with no number is a count this read cannot
# give, which is no count rather than zero.
ANN=$(warn "tool calls denied")
host_run_denials "$url" >/dev/null 2>&1; rc=$?
check "a claude-review warning with no leading number fails the read" 1 "$([ "$rc" -ne 0 ] && echo 1)"

ANN=$(warn "1 tool call(s) denied")
FAIL=jobs
host_run_denials "$url" >/dev/null 2>&1; rc=$?
check "a failed jobs read fails the count" 1 "$([ "$rc" -ne 0 ] && echo 1)"
FAIL=annotations
host_run_denials "$url" >/dev/null 2>&1; rc=$?
check "a failed annotations read fails the count" 1 "$([ "$rc" -ne 0 ] && echo 1)"
FAIL=''

out=$(host_run_denials https://github.com/o/r/pull/7 2>/dev/null); rc=$?
check "a URL naming no run fails the count" 1 "$([ "$rc" -ne 0 ] && echo 1)"
check "and reaches no host" "" "$(reads https://github.com/o/r/pull/7)"

finish
