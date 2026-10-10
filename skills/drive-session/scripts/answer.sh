#!/usr/bin/env bash
# Answer a supervised session: text as a prompt, or key presses into a dialog.
#
#   answer <name> --roster <file> ( --text <t> | --keys <k>... )
#
# The row's `seen_seq` becomes the session's current sequence number before
# anything is sent, so the next `watch` reports the turn the answer starts and
# not the state it answered. Text goes through `agent prompt`, without waiting,
# and is refused to a `blocked` session, which Herdr would refuse with
# `agent_blocked`: a dialog is answered with keys (`1`, `Enter`, `esc`), sent
# through `agent send-keys` whatever the status.
#
# stdout: {name, sent, seen_seq}, `sent` being `text` or `keys`
# exit: 0 sent · 1 the name is not in the roster, the session is gone, or herdr
#       refused (its code in `code`) · 2 usage, text to a blocked session, or
#       outside Herdr
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: answer <name> --roster <file> ( --text <t> | --keys <k>... )'
ds_help "$usage" "$@"
[ -n "${1:-}" ] || ds_tooling "$usage"
name=$1; shift
case $name in -*) ds_tooling "$usage" ;; esac
roster='' text='' keys=() sent=''
while [ $# -gt 0 ]; do
  case $1 in
    --roster) ds_flag_value "$usage" "${2:-}"; roster=$2; shift 2 ;;
    --text) [ -z "$sent" ] || ds_tooling "$usage"; ds_flag_value "$usage" "${2:-}"; text=$2; sent=text; shift 2 ;;
    --keys)
      [ -z "$sent" ] || ds_tooling "$usage"; sent=keys; shift
      while [ $# -gt 0 ]; do case $1 in --*) break ;; esac; keys+=("$1"); shift; done
      [ "${#keys[@]}" -gt 0 ] || ds_tooling "$usage" ;;
    *) ds_tooling "$usage" ;;
  esac
done
[ -n "$roster" ] && [ -n "$sent" ] || ds_tooling "$usage"
ds_in_herdr
ds_row "$roster" "$name" >/dev/null

ds_herdr agent get "$name" || ds_fail "agent get $name: $ds_msg" "$ds_code"
status=$(jq -r .result.agent.agent_status <<<"$ds_out")
seq=$(jq -r .result.agent.state_change_seq <<<"$ds_out")
[ "$sent" = text ] && [ "$status" = blocked ] && ds_tooling "answer: $name is blocked on a dialog; answer it with --keys"
ds_set "$roster" "$name" seen_seq "$seq"
if [ "$sent" = text ]; then
  ds_herdr agent prompt "$name" "$text" || ds_fail "agent prompt $name: $ds_msg" "$ds_code"
else
  ds_herdr agent send-keys "$name" "${keys[@]}" || ds_fail "agent send-keys $name: $ds_msg" "$ds_code"
fi
jq -cn --arg n "$name" --arg s "$sent" --argjson q "$seq" '{name: $n, sent: $s, seen_seq: $q}'
