#!/usr/bin/env bash
# Answer a supervised session: text as a prompt, or key presses into a dialog.
#
#   answer <name> --roster <file> ( --text <t> | --keys <k>... )
#
# Once the send succeeds, the row's `seen_seq` becomes the session's sequence
# number from before it, so the next `watch` reports the turn the answer starts
# and not the state it answered; a send Herdr refuses acknowledges nothing.
# Text goes through `agent prompt`, waiting only until the turn starts or opens
# a dialog: text that starts no turn (a local slash command) is a not-ok answer
# saying it reached the pane, since `watch` would never report it. Text is
# refused to a `blocked` session, which Herdr would refuse with
# `agent_blocked`: a dialog is answered with keys (`1`, `Enter`, `esc`), sent
# through `agent send-keys` whatever the status. Text opening with `-` goes as
# `--text=<t>`, since `--text <t>` refuses a dash-led value as a missing one.
#
# stdout: {name, sent, seen_seq}, `sent` being `text` or `keys`
# exit: 0 sent · 1 the name is not in the roster, the session is gone, the
#       roster cannot be written or locked, the text started no turn (`code`
#       `agent_prompt_stalled` or `timeout`), or herdr refused (its code in
#       `code`) · 2
#       usage, text to a blocked session, outside Herdr, an unreadable roster,
#       or an answer from herdr it cannot read
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
    --text=*)
      [ -z "$sent" ] || ds_tooling "$usage"; text=${1#--text=}; sent=text; shift
      [ -n "$text" ] || ds_tooling "$usage" ;;
    --keys)
      [ -z "$sent" ] || ds_tooling "$usage"; sent=keys; shift
      while [ $# -gt 0 ]; do case $1 in --*) break ;; esac; keys+=("$1"); shift; done
      [ "${#keys[@]}" -gt 0 ] || ds_tooling "$usage" ;;
    *) ds_tooling "$usage" ;;
  esac
done
[ -n "$roster" ] && [ -n "$sent" ] || ds_tooling "$usage"
ds_in_herdr
ds_held "$roster" "$name"

ds_agent "$name" || ds_fail "$name is gone: Herdr no longer knows it" agent_not_found
seq=$ds_seq
[ "$sent" = text ] && [ "$ds_status" = blocked ] && ds_tooling "answer: $name is blocked on a dialog; answer it with --keys"
if [ "$sent" = text ]; then
  ds_prompt "$name" "$text"
  case $? in
    2) ds_fail "agent prompt $name: the text reached the pane but started no turn ($ds_code): read $name before sending anything" "$ds_code" ;;
    1) ds_fail "agent prompt $name: $ds_msg" "$ds_code" ;;
  esac
else
  ds_herdr agent send-keys "$name" "${keys[@]}" || ds_fail "agent send-keys $name: $ds_msg" "$ds_code"
fi
ds_set "$roster" "$name" seen_seq "$seq"
jq -cn --arg n "$name" --arg s "$sent" --argjson q "$seq" '{name: $n, sent: $s, seen_seq: $q}'
