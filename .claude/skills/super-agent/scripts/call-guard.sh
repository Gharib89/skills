#!/usr/bin/env bash
# The call guard: a PreToolUse hook that refuses a send into a thread the super
# agent has no business in. It judges `mcp__t3-code__t3_thread_send` and
# `mcp__t3-code__t3_thread_send_attachments` (their `threadId`) and a Bash command
# running `t3 thread send <id> ...` (the first one in the command). A send is allowed
# to the ledger's `own_thread`, to the thread of an open entry that is neither
# `owner_run` nor `steered`, and to a thread holding an unspent `tell` (`ledger.sh
# tell`, the owner's "Tell <thread> X"). Any other is refused, the reason one of
# `not-held` (no open entry holds the thread), `owner-run` (the owner took it) or
# `owner-steered` (the owner's message is the newest one from outside it). A refusal
# exits 2 with the reason and the `tell` override on stderr, and appends `{at,
# event: "refused", reason, thread, tool}` to `call-guard.jsonl` beside the ledger,
# which the scorecard counts. A told send is allowed and appends `{at, event: "told",
# thread, tell_at}`: a tell is spent when the log holds as many `told` lines for its
# thread as the ledger holds tells, so the hook never writes the ledger. A call it
# cannot judge (no `jq`, input that is no tool call, a call naming no thread, an
# unreadable ledger) is allowed and logged `unjudged`. A guard rail, not a sandbox:
# it reads the call's text, so a command that builds the send at run time gets past
# it. Written by `setup.sh --write` and every handover into the super agent folder's
# generated settings.
#
#   call-guard [--ledger <file>]      (the PreToolUse JSON on stdin)
#
# contract: bare-run
# stdout: nothing
# exit: 0 allowed (told and unjudged included) · 2 a send refused (the message on
#       stderr), or a usage error: the generated entry does not swallow it, since a
#       PreToolUse hook's exit 2 is what refuses the call
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/lib/hook-log.sh" || exit 0
log=$(sa_hook_log_file call-guard "$@")
unjudged() { sa_hook_log "$log" unjudged "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || unjudged "no jq"
source "$here/_lib.sh" || unjudged "cannot source _lib.sh"
usage='usage: call-guard [--ledger <file>]'
sa_help "$usage" "$@"
ledger=${XDG_STATE_HOME:-$HOME/.local/state}/super-agent/ledger.json
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done

input=$(cat)
tool=$(jq -er '.tool_name | strings' <<<"$input" 2>/dev/null) || unjudged "the hook input is no tool call"
case $tool in
  mcp__t3-code__t3_thread_send|mcp__t3-code__t3_thread_send_attachments)
    thread=$(jq -r '.tool_input.threadId | strings' <<<"$input" 2>/dev/null) ;;
  Bash)
    cmd=$(jq -r '.tool_input.command | strings' <<<"$input" 2>/dev/null)
    [[ $cmd =~ (^|[^[:alnum:]_./-])t3[[:space:]]+thread[[:space:]]+send[[:space:]]+(-[^[:space:]]*[[:space:]]+)*[\"\']?([^[:space:]\"\']+) ]] || exit 0
    thread=${BASH_REMATCH[3]} ;;
  *) exit 0 ;;
esac
[ -n "${thread:-}" ] || unjudged "the call names no thread"

if [ -f "$ledger" ]; then
  doc=$(jq -c 'select(type == "object" and (.entries | type) == "object")' "$ledger" 2>/dev/null)
  [ -n "$doc" ] || unjudged "the ledger is unreadable"
else doc='{"entries":{}}'; fi
told=0
[ ! -f "$log" ] || told=$(jq -Rn --arg t "$thread" '[inputs | fromjson? | select(.event == "told" and .thread == $t)] | length' "$log" 2>/dev/null) || told=0
verdict=$(jq -r --arg t "$thread" --argjson told "$told" "$sa_jq_open"'
  [(.tells // [])[] | select(.thread == $t)] as $tells
  | ([.entries[] | select(.thread == $t and is_open)] | first) as $e
  | if .own_thread == $t then "allow"
    elif ($tells | length) > $told then "told \($tells[$told].at)"
    elif $e == null then "refuse not-held"
    elif $e.owner_run == true then "refuse owner-run"
    elif $e.steered == true then "refuse owner-steered"
    else "allow" end' <<<"$doc" 2>/dev/null) || unjudged "cannot judge the call"

at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
case $verdict in
  allow) exit 0 ;;
  told*)
    jq -cn --arg at "$at" --arg t "$thread" --arg ta "${verdict#told }" '{at: $at, event: "told", thread: $t, tell_at: $ta}' >> "$log" 2>/dev/null
    exit 0 ;;
  refuse*)
    reason=${verdict#refuse }
    jq -cn --arg at "$at" --arg r "$reason" --arg t "$thread" --arg tool "$tool" '{at: $at, event: "refused", reason: $r, thread: $t, tool: $tool}' >> "$log" 2>/dev/null
    case $reason in
      not-held) why="no open ledger entry holds thread $thread" ;;
      owner-run) why="thread $thread is owner-run: the owner took it" ;;
      *) why="thread $thread is owner-steered: the owner's message is the newest one in it" ;;
    esac
    printf 'Refused (%s): %s. Send nothing into it. If the owner wants this one send anyway ("Tell <thread> X"), run scripts/ledger.sh --ledger <ledger> tell <key or thread id>, then send once.\n' "$reason" "$why" >&2
    exit 2 ;;
esac
unjudged "cannot judge the call"
