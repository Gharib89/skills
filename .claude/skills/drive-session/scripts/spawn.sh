#!/usr/bin/env bash
# Start one supervised session: a Herdr tab beside the supervisor's, in its
# workspace and without focus, a claude agent in the tab's root pane, the task
# sent as its first prompt, and a roster row recording it.
#
#   spawn <name> --roster <file> --cwd <dir> --prompt <text> [--model <m>]
#         [-- <agent-arg>...]
#
# <name> is the agent's name and the tab's label, so it follows Herdr's name
# rule. The roster is created on the first spawn. The prompt is sent without
# waiting, so one `watch` can cover every session; the row's `seen_seq` is the
# agent's `state_change_seq` from before the prompt, which is what keeps the
# previous turn's `done` from reading as this one's. An agent that stops on a
# startup dialog (an untrusted folder) is no failure: its row is written one
# short of the dialog's sequence number, so `watch` reports the dialog as the
# row's `blocked` event, the prompt is held back, and the answer says `blocked`.
# Spawn one session at a time: each spawn rewrites the whole roster. A task
# opening with `-` goes as `--prompt=<text>`, since `--prompt <text>` refuses a
# dash-led value as a missing one.
#
# stdout: {roster, name, tab, pane, status, prompted}, `status` the agent's at
#         start (`blocked` on a startup dialog), `prompted` whether the task went
# exit: 0 the session runs, or waits on a startup dialog · 1 the name is
#       already in the roster, no such --cwd, the roster cannot be created or
#       written, or herdr refused (its code in `code`; the error names a tab
#       left open) · 2 usage, outside Herdr, an unreadable roster, or an answer
#       from herdr it cannot read
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: spawn <name> --roster <file> --cwd <dir> --prompt <text> [--model <m>] [-- <agent-arg>...]'
ds_help "$usage" "$@"
[ -n "${1:-}" ] || ds_tooling "$usage"
name=$1; shift
case $name in -*) ds_tooling "$usage" ;; esac
roster='' cwd='' prompt='' args=()
while [ $# -gt 0 ]; do
  case $1 in
    --roster) ds_flag_value "$usage" "${2:-}"; roster=$2; shift 2 ;;
    --cwd) ds_flag_value "$usage" "${2:-}"; cwd=$2; shift 2 ;;
    --prompt) ds_flag_value "$usage" "${2:-}"; prompt=$2; shift 2 ;;
    --prompt=*) prompt=${1#--prompt=}; [ -n "$prompt" ] || ds_tooling "$usage"; shift ;;
    --model) ds_flag_value "$usage" "${2:-}"; args+=(--model "$2"); shift 2 ;;
    --) shift; args+=("$@"); break ;;
    *) ds_tooling "$usage" ;;
  esac
done
[ -n "$roster" ] && [ -n "$cwd" ] && [ -n "$prompt" ] || ds_tooling "$usage"
[[ $name =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || ds_tooling "spawn: $name is no Herdr agent name; use [a-z][a-z0-9_-]{0,31}"
ds_in_herdr
[ -n "${HERDR_WORKSPACE_ID:-}" ] || ds_tooling "HERDR_WORKSPACE_ID is not set"
[ -d "$cwd" ] || ds_fail "no such directory: $cwd"

if [ -f "$roster" ]; then
  ds_readable "$roster"
  jq -e --arg n "$name" 'any(.sessions[]; .name == $n)' "$roster" >/dev/null \
    && ds_fail "$name is already in the roster $roster"
else
  mkdir -p "$(dirname "$roster")" && printf '{"sessions":[]}\n' > "$roster" || ds_fail "cannot create the roster $roster"
fi

ds_herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label "$name" --cwd "$cwd" --no-focus \
  || ds_fail "tab create: $ds_msg" "$ds_code"
ids=$(jq -er '"\(.result.tab.tab_id | strings) \(.result.root_pane.pane_id | strings)"' <<<"$ds_out" 2>/dev/null) \
  || ds_tooling "tab create: unreadable answer from herdr"
tab=${ids% *} pane=${ids#* }

if ds_herdr agent start "$name" --kind claude --pane "$pane" -- ${args[@]+"${args[@]}"}; then
  ds_agent_fields "agent start $name"
elif [ "$ds_code" = agent_not_ready ]; then
  ds_agent "$name" || ds_fail "agent get after a startup dialog: $name is gone; tab $tab left open" agent_not_found
else
  ds_fail "agent start: $ds_msg; tab $tab left open" "$ds_code"
fi
seen=$ds_seq
[ "$ds_status" = blocked ] && seen=$((ds_seq - 1))
ds_write "$roster" --arg n "$name" --arg p "$pane" --arg t "$tab" --arg c "$cwd" --arg k "$prompt" --argjson s "$seen" \
  '.sessions += [{name: $n, pane: $p, tab: $t, cwd: $c, task: $k, seen_seq: $s}]'

prompted=false
if [ "$ds_status" != blocked ]; then
  ds_herdr agent prompt "$name" "$prompt" \
    || ds_fail "agent prompt: $ds_msg; $name stays in the roster with tab $tab open: send the task with answer --text" "$ds_code"
  prompted=true
fi
jq -cn --arg r "$roster" --arg n "$name" --arg t "$tab" --arg p "$pane" --arg s "$ds_status" --argjson d "$prompted" \
  '{roster: $r, name: $n, tab: $t, pane: $p, status: $s, prompted: $d}'
