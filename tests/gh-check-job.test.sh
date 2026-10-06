#!/usr/bin/env bash
# `host_check_job` and `host_check_rerun`: the GitHub adapter's read of the
# re-runnable job behind a check and its one write, which `ci-wait
# --rerun-failed` drives (#487). The adapter's `api` is redefined to answer per
# endpoint and log the request, so no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

reqs=$(mktemp); trap 'rm -f "$reqs"' EXIT
APP=github-actions LOGFAIL='' RUN='' LOGBODY=''
# The check-runs read answers what its own `--jq` would print: the latest run's
# id and whether Actions wrote it, or nothing where no run carries the name.
api() {
  local a p
  printf '%s\n' "$*" >> "$reqs"
  for a; do case $a in repos/*) p=$a ;; esac; done
  case $p in
    repos/o/r/commits/abc/check-runs) [ -z "$RUN" ] || jq -cn --arg a "$APP" '{id: 55, actions: ($a == "github-actions")}' ;;
    repos/o/r/actions/jobs/55) echo 2 ;;
    repos/o/r/actions/jobs/55/logs)
      [ -z "$LOGFAIL" ] || return 1
      # The real endpoint refuses a log carrying escape sequences unless told.
      case " $* " in *' --allow-escape-sequences '*) ;; *) echo 'the response contains terminal escape sequences; pass --allow-escape-sequences' >&2; return 1 ;; esac
      if [ -n "$LOGBODY" ]; then printf '%b\n' "$LOGBODY"; else seq 1 100; fi ;;
    repos/o/r/actions/jobs/55/rerun) ;;
    *) echo "unexpected api call: $*" >&2; return 1 ;;
  esac
}

RUN=1
out=$(host_check_job 7 abc 'test (ubuntu-22.04)')
check "an Actions check answers its job, attempt and the log's last 40 lines" '55 2 40 100' \
  "$(jq -r '[.job_id, .attempt, (.log_tail | split("\n") | length), (.log_tail | split("\n") | last)] | join(" ")' <<<"$out")"
check "the check is looked up by name on the head" \
  'repos/o/r/commits/abc/check-runs -X GET -f check_name=test (ubuntu-22.04) -f per_page=100' \
  "$(grep check-runs "$reqs" | sed 's/ --jq.*//')"
check "the job and its log are read by the check run's id" 'repos/o/r/actions/jobs/55 repos/o/r/actions/jobs/55/logs' \
  "$(grep -o 'repos/o/r/actions/jobs/55[/a-z]*' "$reqs" | paste -sd' ' -)"

check "the log read passes --allow-escape-sequences" 1 "$(grep -c 'jobs/55/logs --allow-escape-sequences' "$reqs")"
LOGBODY='\033[31mred\033[0m\n\033[1;32mgreen\033[K ok\033[0m\n\033]0;title\007plain'
check "escape sequences (CSI and OSC) are stripped from the log tail" 'red|green ok|plain' \
  "$(host_check_job 7 abc test | jq -r '.log_tail | split("\n") | join("|")')"
LOGBODY=''

LOGFAIL=1
check "a log that cannot be read is a null tail, not a failed call" '55 null' \
  "$(host_check_job 7 abc test | jq -r '[.job_id, .log_tail] | map(tostring) | join(" ")')"

APP=some-ci; : > "$reqs"
check "a check no Actions job wrote answers nulls" '{"job_id":null,"attempt":null,"log_tail":null}' "$(host_check_job 7 abc test | jq -c .)"
check "and reads no job" 1 "$(wc -l < "$reqs")"

RUN=''
host_check_job 7 abc test >/dev/null; check_rc "a name no check run carries is no job" 1 $?

: > "$reqs"; host_check_rerun 55; check_rc "the re-run writes" 0 $?
check "as a POST to that one job's rerun" '-X POST repos/o/r/actions/jobs/55/rerun' "$(cat "$reqs")"

finish
