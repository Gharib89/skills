#!/usr/bin/env bash
# The stopped-supervisor alarm: wait the fleet file's notify delay, then run its
# notify command once unless a reconcile ran since `--since`. `watch` leaves one
# of these behind, detached, each time it exits on an event: the watcher's exit
# is what wakes the super agent, so a super agent that never reconciles after it
# is stopped, and every other alarm in the loop is the super agent's own.
#
#   notify --ledger <file> --fleet <file> --since <epoch second>
#
# The fleet file's `notify` is `{command, delay}`: `command` a shell command run
# with `bash -c`, `SA_NOTIFY_MESSAGE` set in its environment, and `delay` the
# seconds to wait (600 when unset). A reconcile stamps `<ledger>.reconciled` with
# its epoch second, so one at or after `--since` runs nothing. A fleet file with
# no `notify` runs nothing.
#
# stdout: {notified, reason} when it ran nothing, `reason` `reconciled` or
#         `no notify command`; {notified: true, exit} once the command ran, `exit`
#         its exit status
# exit: 0 an answer, the command's own failure included · 2 usage, or a fleet
#       file whose notify is malformed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: notify --ledger <file> --fleet <file> --since <epoch second>'
sa_help "$usage" "$@"
ledger='' fleet='' since=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}"; fleet=$2; shift 2 ;;
    --since) sa_flag_value "$usage" "${2:-}"; case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; since=$2; shift 2 ;;
    *) sa_tooling "$usage" ;;
  esac
done
[ -n "$ledger" ] && [ -n "$fleet" ] && [ -n "$since" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file"
sa_notify_read "$fleet"
[ -n "$notify_cmd" ] || { jq -cn '{notified: false, reason: "no notify command"}'; exit 0; }

sleep "$notify_delay"
# A missing stamp reads as 0: no reconcile is known, so the alarm may fire.
stamp=$(cat "$ledger.reconciled" 2>/dev/null)
case $stamp in ''|*[!0-9]*) stamp=0 ;; esac
if [ "$stamp" -ge "$since" ]; then jq -cn '{notified: false, reason: "reconciled"}'; exit 0; fi
rc=0
SA_NOTIFY_MESSAGE="The super agent has not reconciled in the ${notify_delay}s since the watcher woke it; it may have stopped." \
  bash -c "$notify_cmd" >/dev/null 2>&1 </dev/null || rc=$?
jq -cn --argjson e "$rc" '{notified: true, exit: $e}'
