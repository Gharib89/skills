#!/usr/bin/env bash
# Read a supervised session's recent output and acknowledge its event.
#
#   read <name> --roster <file> [--lines <n>] [--rest]
#
# The row's `seen_seq` becomes the sequence number read here, taken before the
# output, so the next `watch` reports this session again only once it changes.
# A session Herdr no longer knows is answered `gone` and its row marked so,
# which takes it off `watch`. A `blocked` session is read from its visible
# screen, where the dialog is: herdr 0.9.3 refuses a blocked agent's scrollback
# past the viewport with `agent_not_idle`. With --rest the row is also marked at
# rest (`at_rest`), for a run whose summary reports its PR merged or its task
# otherwise done: `watch` stops waking on it, since idle compaction on a
# finished tab fires `done` events with nothing left to answer, but still lists
# it in a timeout answer.
#
# stdout: {name, status, seq, output}, `output` the last --lines lines (default
#         40), or the visible screen when blocked, whatever --lines says;
#         status `gone` with seq and output null; `rest` true after --rest
# exit: 0 read · 1 the name is not in the roster, the roster cannot be written
#       or locked, or herdr refused (its code in `code`) · 2 usage, outside
#       Herdr, an unreadable roster, or an answer from herdr it cannot read
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: read <name> --roster <file> [--lines <n>] [--rest]'
ds_help "$usage" "$@"
[ -n "${1:-}" ] || ds_tooling "$usage"
name=$1; shift
case $name in -*) ds_tooling "$usage" ;; esac
roster='' lines=40 rest=false
while [ $# -gt 0 ]; do
  case $1 in
    --roster) ds_flag_value "$usage" "${2:-}"; roster=$2; shift 2 ;;
    --lines) ds_flag_value "$usage" "${2:-}"; lines=$2; shift 2 ;;
    --rest) rest=true; shift ;;
    *) ds_tooling "$usage" ;;
  esac
done
[ -n "$roster" ] || ds_tooling "$usage"
[[ $lines =~ ^[1-9][0-9]*$ ]] || ds_tooling "$usage"
ds_in_herdr
ds_held "$roster" "$name"

if ! ds_agent "$name"; then
  ds_set "$roster" "$name" gone true
  jq -cn --arg n "$name" '{name: $n, status: "gone", seq: null, output: null}'
  exit 0
fi
status=$ds_status seq=$ds_seq
source=(--source recent-unwrapped --lines "$lines")
[ "$status" = blocked ] && source=(--source visible)
ds_herdr agent read "$name" "${source[@]}" || ds_fail "agent read $name: $ds_msg" "$ds_code"
ds_set "$roster" "$name" seen_seq "$seq"
[ "$rest" = true ] && ds_set "$roster" "$name" at_rest true
jq -cn --arg n "$name" --arg s "$status" --argjson q "$seq" --arg o "$ds_out" --argjson r "$rest" \
  '{name: $n, status: $s, seq: $q, output: $o} + (if $r then {rest: true} else {} end)'
