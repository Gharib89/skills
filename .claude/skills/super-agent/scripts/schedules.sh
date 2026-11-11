#!/usr/bin/env bash
# Propose the recurring schedules the owner may say yes to, one JSON answer: a
# morning ledger report and a weekly retro-run per active repo. It only
# proposes, creates nothing and reads nothing off GitHub or T3; the super agent
# makes each with `schedule_task` after the owner's yes.
#
#   schedules --fleet <file> [--morning <HH:MM>] [--retro-day <0-6>]
#
# The morning report runs in the super agent's own thread at `--morning`
# (default 08:00) on the fleet file's `work_week` (weekday numbers, 0 is
# Sunday, in week order; default Monday to Friday); each retro-run runs weekly
# on `--retro-day` (default the work week's last day) at 09:00 in that repo's
# own T3 project. The prompts
# carry no path or host: the thread already knows its ledger.
#
# stdout: {morning: {title, bind, schedule, prompt}, retro: [{repo, title,
#         bind, schedule, prompt}]}: `bind` `this-thread` or `repo-project`,
#         `schedule` the `schedule_task` trigger object; `retro` is empty when
#         the fleet file has no active repos
# exit: 0 a proposal · 2 usage, or a fleet file that is unreadable or whose
#       `work_week` is not a non-empty list of distinct days 0 to 6
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: schedules --fleet <file> [--morning <HH:MM>] [--retro-day <0-6>]'
sa_help "$usage" "$@"
fleet='' morning='08:00' day=''
while [ $# -gt 0 ]; do
  case $1 in
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2 ;;
    --morning) sa_flag_value "$usage" "${2:-}"; case $2 in [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) morning=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    --retro-day) sa_flag_value "$usage" "${2:-}"; case $2 in [0-6]) day=$2 ;; *) sa_tooling "$usage" ;; esac ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$fleet" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file, run setup"
jq -e '((.active_repos // []) | type) == "array"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a fleet file (active_repos must be an array)"

jq -e '(if .work_week == null then [1,2,3,4,5] else .work_week end) | type == "array" and length > 0 and length == (unique | length) and all(type == "number" and . >= 0 and . <= 6 and . == floor)' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: work_week must be a non-empty list of distinct weekday numbers 0 to 6"

jq -cn --slurpfile f "$fleet" --arg m "$morning" --arg d "$day" '
  ($f[0].work_week // [1,2,3,4,5]) as $week
  | (if $d == "" then $week[-1] else ($d | tonumber) end) as $d
  | {morning: {title: "Super agent morning report", bind: "this-thread",
     schedule: {type: "fixed_time", timeOfDay: $m, weekdays: $week},
     prompt: "Morning report: run reconcile.sh, then status.sh --digest, and post its block as printed. Start the watcher only if none runs."},
   retro: [($f[0].active_repos // [])[] | {repo: ., title: "Retro run \(.)", bind: "repo-project",
     schedule: {type: "fixed_time", timeOfDay: "09:00", weekdays: [$d]},
     prompt: "/retro-run"}]}'
