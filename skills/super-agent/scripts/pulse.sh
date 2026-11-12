#!/usr/bin/env bash
# The backstop turn in one call: is the watcher alive, and did anything change?
# It runs `reconcile` with the flags it is given (so the ledger is brought up to
# date, as on any wake) and reads the watcher's lock, `<ledger>.watch`: the watcher
# is alive when the pid the lock holds is a live `watch.sh`.
#
#   pulse --ledger <file> [--fleet <file>] [--stall-window <s>] [--remote <environment id>=<dir>]...
#
# A backstop turn that finds `alive` true and `changed` false ends there: no
# transcript read, no status block, no further call. `changed` is true when the
# reconcile answer holds anything to act on: any of its lists but `entries` and
# `at_rest` is not empty (a new list counts by default), or an entry's stage
# moved. A thread at rest that is only waiting for the owner's answer
# (`at_rest`) is not a change, and nor is an error of an entry that the
# ledger holds: its `escalate` row carries it until a need silences it. A dead
# watcher is `alive` false whatever else holds.
#
# stdout: {alive, changed, summary}: `summary` is reconcile's whole answer when
#         `changed`, null when not
# exit: 0 an answer · 2 usage, or reconcile's own exit 2 (its answer, not a pulse's,
#       is printed)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: pulse --ledger <file> [--fleet <file>] [--stall-window <s>] [--remote <environment id>=<dir>]...'
sa_help "$usage" "$@"
ledger='' pass=()
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --fleet) sa_flag_value "$usage" "${2:-}" ;;
    --remote) sa_flag_value "$usage" "${2:-}"; sa_remote_flag "$usage" "$2" ;;
    --stall-window) sa_flag_value "$usage" "${2:-}"; sa_window_flag "$usage" "$2" ;;
    *) sa_tooling "$usage" ;;
  esac
  pass+=("$1" "$2"); shift 2
done
[ -n "$ledger" ] || sa_tooling "$usage"

summary=$(bash "$(dirname "${BASH_SOURCE[0]}")/reconcile.sh" "${pass[@]}"); rc=$?
if [ "$rc" -ne 0 ]; then printf '%s\n' "$summary"; exit "$rc"; fi

pid=$(cat "$ledger.watch" 2>/dev/null) args=''
# /bin/ps by its full path, as `watch` reads the same lock, past the tests' fake.
[ -z "$pid" ] || args=$(/bin/ps -p "$pid" -o args= 2>/dev/null)
alive=false
[[ $args == *watch.sh* ]] && alive=true

held=$(jq -c '(.entries // {}) | keys' "$ledger" 2>/dev/null) || held='[]'
jq -cn --argjson s "$summary" --argjson a "$alive" --argjson held "$held" "$sa_jq_norm"'
  ($s | .errors |= map(select(.key as $k | $held | map(norm_repo) | index($k | norm_repo) | not))
     | [to_entries[] | select(.key | IN("ledger", "checked", "entries", "at_rest") | not) | .value
        | select(type == "array" and length > 0)] | length > 0) as $lists
  | ($lists or ([$s.entries[] | select(.from != .stage)] | length > 0)) as $c
  | {alive: $a, changed: $c, summary: (if $c then $s else null end)}'
