#!/usr/bin/env bash
set -uo pipefail
src=$PWD/skills/ship-run/scripts
source "$src/_lib.sh"
source "$src/host/github.d/prs.sh"
R=repos/example/repo
api() {
  local case_json
  case $1 in
    */check-runs) case_json='{"check_runs":[{"id":1,"name":"build","check_suite":{"id":1},"conclusion":"failure","status":"completed","completed_at":"2026-11-23T12:00:00Z"}]}' ;;
    */status) case_json='{"statuses":[{"context":"build","state":"success","updated_at":"2026-11-23T12:01:00Z"}]}' ;;
    *) return 99 ;;
  esac
  jq "${@: -1}" <<< "$case_json"
}
checks=$(host_pr_checks 7 abcd)
jq -c . <<< "$checks"
echo "Unsettled checks: [$(ship_unsettled_checks "$checks" $'## CI\nLegs: build: build\nNo-checks legal: no')]"
