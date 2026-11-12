#!/usr/bin/env bash
# Edit the fleet file's placement settings: pin a repo to one machine, free it, or set
# a machine's slots. Everything else in the file keeps its value, and a write is a temp
# file then a rename.
#
#   fleet --fleet <file> pin <owner/name> <machine>
#   fleet --fleet <file> unpin <owner/name>
#   fleet --fleet <file> slots <machine> <n>
#
# `pin` writes `repos.<owner/name>.machine`, which `place` honours: the repo's tickets
# run only on that machine and wait while it is down or full. Run a readiness check on
# the machine first (a probe thread, setup.md step 2), since a pin never falls back to
# another one. `unpin` removes it, and drops a repo entry left with no other key.
# `slots` sets `machines.<machine>.slots`, a whole number of 1 or more that stays above
# the machine's `reserve`, since a ceiling of none launches nothing. A repo name is
# compared without regard to case, as GitHub does; a pin or a count already as given,
# or an unpin of a free repo, changes nothing and says so. The machine must already be
# in the file: machines are setup's to propose.
#
# stdout: {fleet_file, action, changed, ...}: `pin` adds `repo` and `machine`, `unpin`
#         `repo`, `slots` `machine` and `slots`
# exit: 0 done, `changed` false when the file already said so · 2 usage, a machine
#       the file lacks, a count that is not allowed, a fleet file that is missing,
#       not JSON or whose `machines` or `repos` is no object, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: fleet --fleet <file> (pin <owner/name> <machine> | unpin <owner/name> | slots <machine> <n>)'
sa_help "$usage" "$@"
[ "${1:-}" = --fleet ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"
fleet=$2; shift 2
action=${1:-}; [ $# -gt 0 ] && shift
case $action in
  pin) [ $# -eq 2 ] || sa_tooling "$usage" ;;
  unpin) [ $# -eq 1 ] || sa_tooling "$usage" ;;
  slots) [ $# -eq 2 ] || sa_tooling "$usage" ;;
  *) sa_tooling "$usage" ;;
esac
repo='' machine='' count=''
case $action in
  pin) repo=$1 machine=$2 ;;
  unpin) repo=$1 ;;
  slots) machine=$1 count=$2; case $count in ''|0|*[!0-9]*) sa_tooling "$usage" ;; esac ;;
esac
if [ -n "$repo" ]; then case $repo in */*/*|*/|/*|*[!A-Za-z0-9._/-]*) sa_tooling "$usage" ;; */*) ;; *) sa_tooling "$usage" ;; esac; fi
[ -f "$fleet" ] || sa_tooling "$fleet: no such file (run setup first)"
jq -e 'type == "object" and ((.machines // {}) | type == "object") and ((.repos // {}) | type == "object")' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: not a fleet file (an object whose machines and repos are objects)"
if [ -n "$machine" ]; then
  jq -e --arg m "$machine" '(.machines // {}) | has($m)' "$fleet" >/dev/null || sa_tooling "$fleet: $machine is not in machines"
fi
if [ "$action" = slots ]; then
  jq -e --arg m "$machine" --argjson n "$count" '$n > (.machines[$m].reserve // 0)' "$fleet" >/dev/null \
    || sa_tooling "$machine keeps $(jq -r --arg m "$machine" '.machines[$m].reserve // 0' "$fleet") slot(s) in reserve: slots must be more than that"
fi

new=$(jq -c --arg a "$action" --arg r "$repo" --arg m "$machine" --argjson n "${count:-null}" "$sa_jq_norm"'
  ((.repos // {}) | keys | map(select(norm_repo == ($r | norm_repo))) | first // $r) as $k
  | if $a == "pin" then .repos[$k].machine = $m
    elif $a == "unpin" then
      (if (.repos // {}) | has($k) then .repos[$k] |= del(.machine) | (if .repos[$k] == {} then del(.repos[$k]) else . end) else . end)
    else .machines[$m].slots = $n end' "$fleet")
changed=$(jq -n --slurpfile o "$fleet" --argjson n "$new" '$o[0] != $n')
[ "$changed" = false ] || sa_write "$fleet" "$new"
case $action in
  pin) jq -cn --arg f "$fleet" --arg r "$repo" --arg m "$machine" --argjson c "$changed" '{fleet_file: $f, action: "pin", repo: $r, machine: $m, changed: $c}' ;;
  unpin) jq -cn --arg f "$fleet" --arg r "$repo" --argjson c "$changed" '{fleet_file: $f, action: "unpin", repo: $r, changed: $c}' ;;
  slots) jq -cn --arg f "$fleet" --arg m "$machine" --argjson n "$count" --argjson c "$changed" '{fleet_file: $f, action: "slots", machine: $m, slots: $n, changed: $c}' ;;
esac
