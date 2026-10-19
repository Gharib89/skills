#!/usr/bin/env bash
# Wait until a supervised session needs the supervisor, then name it and exit.
# Run it as a background command: it holds no tool call open, and its exit is
# what wakes the supervisor.
#
#   watch --roster <file> [--timeout <ms>]
#
# Polls every session in the roster, in roster order, once a second. An event
# is a settled status (`idle`, `done` or `blocked`) whose `state_change_seq` is
# past the row's `seen_seq`, or `gone`: Herdr no longer knows the agent, its
# pane closed or its claude exited. The sequence number is what keeps the
# previous turn's `done`, which Herdr reports until the next turn starts, from
# reading as an event. Watch writes nothing: `read` acknowledges an event, so an
# unread one is reported again. A row `read` marked gone or, with --rest, at
# rest is not watched. The timeout answer lists what the last poll saw, so a
# session stuck in `working` or `unknown` shows as a sequence number that stood
# still, and each at-rest row as status `at-rest`, polled no further.
#
# stdout: {name, event, seq} for `idle`, `done` or `blocked`; {name, event} for
#         `gone`; {"name": null, "event": "timeout", sessions} once --timeout
#         passes, `sessions` one {name, status, seq, still_s} per live session,
#         `still_s` the seconds its seq has stood still while this watch ran,
#         then one {name, status: "at-rest", seq: null, still_s: null} per
#         at-rest row
# exit: 0 an event or the timeout · 1 no live session in the roster (every row
#       gone or at rest), or herdr
#       refused (its code in `code`) · 2 usage, outside Herdr, an unreadable
#       roster, or an answer from herdr it cannot read
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: watch --roster <file> [--timeout <ms>]'
ds_help "$usage" "$@"
roster='' timeout=''
while [ $# -gt 0 ]; do
  case $1 in
    --roster) ds_flag_value "$usage" "${2:-}"; roster=$2; shift 2 ;;
    --timeout) ds_flag_value "$usage" "${2:-}"; timeout=$2; shift 2 ;;
    *) ds_tooling "$usage" ;;
  esac
done
[ -n "$roster" ] || ds_tooling "$usage"
case $timeout in *[!0-9]*) ds_tooling "$usage" ;; esac
ds_in_herdr

# Each session watched, the sequence number it last showed, and since when:
# indexed arrays, since macOS's /bin/bash is 3.2, which has no associative ones.
watched_names=() watched_seqs=() watched_since=()
since() { # <name> <seq>: sets $still_since to the SECONDS value since which <name> shows <seq>
  local i=0
  while [ "$i" -lt "${#watched_names[@]}" ] && [ "${watched_names[i]}" != "$1" ]; do i=$((i + 1)); done
  [ "${watched_seqs[i]:-}" = "$2" ] || { watched_names[i]=$1 watched_seqs[i]=$2 watched_since[i]=$SECONDS; }
  still_since=${watched_since[i]}
}

start=$SECONDS
while :; do
  polled=''
  names=$(jq -r '.sessions[] | select(.gone != true and .at_rest != true) | .name' "$roster" 2>/dev/null) \
    || ds_tooling "cannot read the roster $roster"
  [ -n "$names" ] || ds_fail "no live session in the roster $roster"
  for n in $names; do
    seen=$(jq -er --arg n "$n" '.sessions[] | select(.name == $n) | .seen_seq | numbers' "$roster" 2>/dev/null) \
      || ds_tooling "cannot read the roster $roster"
    if ! ds_agent "$n"; then
      jq -cn --arg n "$n" '{name: $n, event: "gone"}'
      exit 0
    fi
    case $ds_status in
      idle | done | blocked)
        if [ "$ds_seq" -gt "$seen" ]; then
          jq -cn --arg n "$n" --arg e "$ds_status" --argjson q "$ds_seq" '{name: $n, event: $e, seq: $q}'
          exit 0
        fi ;;
    esac
    since "$n" "$ds_seq"
    polled+="$n $ds_status $ds_seq $((SECONDS - still_since))"$'\n'
  done
  [ -n "$timeout" ] && [ $(( (SECONDS - start) * 1000 )) -ge "$timeout" ] && break
  sleep 1
done
resting=$(jq -c '[.sessions[] | select(.gone != true and .at_rest == true)
  | {name, status: "at-rest", seq: null, still_s: null}]' "$roster") || ds_tooling "cannot read the roster $roster"
printf '%s' "$polled" | jq -cRn --argjson rest "$resting" '{name: null, event: "timeout", sessions: ([inputs | split(" ")
  | {name: .[0], status: .[1], seq: (.[2] | tonumber), still_s: (.[3] | tonumber)}] + $rest)}'
