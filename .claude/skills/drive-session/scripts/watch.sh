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
# unread one is reported again. A row `read` marked gone is not watched.
#
# stdout: {name, event, seq} for `idle`, `done` or `blocked`; {name, event} for
#         `gone`; {"name": null, "event": "timeout"} once --timeout passes
# exit: 0 an event or the timeout · 1 no live session in the roster, or herdr
#       refused (its code in `code`) · 2 usage, or outside Herdr
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

start=$SECONDS
while :; do
  names=$(jq -r '.sessions[] | select(.gone != true) | .name' "$roster" 2>/dev/null) \
    || ds_fail "cannot read the roster $roster"
  [ -n "$names" ] || ds_fail "no live session in the roster $roster"
  for n in $names; do
    if ! ds_herdr agent get "$n"; then
      [ "$ds_code" = agent_not_found ] || ds_fail "agent get $n: $ds_msg" "$ds_code"
      jq -cn --arg n "$n" '{name: $n, event: "gone"}'
      exit 0
    fi
    seen=$(jq -r --arg n "$n" '.sessions[] | select(.name == $n) | .seen_seq' "$roster")
    jq -ce --arg n "$n" --argjson seen "$seen" '.result.agent
      | select((.agent_status | IN("idle", "done", "blocked")) and .state_change_seq > $seen)
      | {name: $n, event: .agent_status, seq: .state_change_seq}' <<<"$ds_out"
    # jq -e: 0 an event, 4 none; anything else is an answer it could not read,
    # which would otherwise read as "no event" on every poll, forever.
    case $? in 0) exit 0 ;; 4) ;; *) ds_fail "agent get $n: unreadable answer" ;; esac
  done
  [ -n "$timeout" ] && [ $(( (SECONDS - start) * 1000 )) -ge "$timeout" ] && break
  sleep 1
done
jq -cn '{name: null, event: "timeout"}'
