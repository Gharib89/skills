#!/usr/bin/env bash
# The call guard: a PreToolUse hook that refuses a send into a thread the super
# agent has no business in, and a direct `ssh`, `scp` or `rsync` call. The second
# refusal reads a Bash command for one of the three as a command word (at the start,
# after `;`, `&`, `|`, `(`, a backtick or a newline, past variable assignments and
# `env`, `command`, `exec`, `nohup`, `time` or `timeout <n>`; a path, a leading
# backslash or quotes around the word are allowed), refuses it with reason
# `direct-ssh` and logs `{at, event: "refused", reason, command, tool}`: a machine is
# read only through `machine-check.sh`. It judges `mcp__t3-code__t3_thread_send` and
# `mcp__t3-code__t3_thread_send_attachments` (their `threadId`) and every `t3 thread
# send <id>` in a Bash command (chained with `;`, `&&`, `||`, `|` or a newline; the word
# `t3` may carry a path, `~/.local/bin/t3`, and a leading backslash or be quoted whole,
# `\t3` or `"t3"`; a backslash before a newline joins the lines), past the flags:
# `--base-dir`, `--output-schema` and `--log-level` take a value; a redirect word
# (`>/dev/null`, `2>&1`, `<msg.txt`, and with a space after the operator, the word after it)
# is no id, and a redirect or a backtick glued to the id is no part of it. A send is allowed to the
# ledger's `own_thread`, to the thread of an open entry that is neither `owner_run`
# nor `steered`, and to a thread holding an unspent `tell` (`ledger.sh tell`, the
# owner's "Tell <thread> X"). Any other is refused, the reason one of `not-held` (no
# open entry holds the thread), `owner-run` (the owner took it) or `owner-steered`
# (the owner's message is the newest one from outside it). Every send in a
# command is judged before any is let through; one refused refuses the command (exit 2,
# the reason on stderr), and appends `{at, event: "refused", reason, thread, tool}` to
# `call-guard.jsonl` beside the ledger, which the scorecard counts. A command whose sends
# are all allowed appends `{at, event: "told", thread, tell_at}` per told send: a tell
# is spent when the log holds a `told` line for it, so the hook never writes the ledger,
# and a refused command spends none. One tell covers one send, in a command or across
# them; two sends whose hooks run at the same time can share it, since the log is not
# locked. A tell lapses an hour after it was recorded (one whose time does not parse has
# lapsed: `tell_live` in _lib.sh, the rule `ledger tell` prunes by), so a deleted log revives one only inside that hour, and a
# log that exists but cannot be read spends every tell (the send is judged without it).
# A call it cannot judge (no `jq`, input that is no tool call, a send naming no thread
# (an MCP call with an empty `threadId`, a Bash send with no word after its flags and
# redirects), a Bash id that is a variable, a substitution or begins with a backslash, an
# unreadable ledger) is allowed and logged
# `unjudged`, its `why` fixed text. A guard rail, not a sandbox: it reads the call's text, so a command
# that builds the send at run time gets past it, as does one with a backslash or quotes
# inside the words (`t\3`, `t''3`, `t3 "thread" send`), and a quoted argument that spells out
# `t3 thread send <id>` (a commit message, a search pattern) is judged as a send, a
# known false positive. Written by `setup.sh --write` and every handover into the super
# agent folder's generated settings.
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
threads=()
case $tool in
  mcp__t3-code__t3_thread_send|mcp__t3-code__t3_thread_send_attachments)
    id=$(jq -r '.tool_input.threadId | strings' <<<"$input" 2>/dev/null)
    [ -z "$id" ] || threads=("$id") ;;
  Bash)
    cmd=$(jq -r '.tool_input.command | strings' <<<"$input" 2>/dev/null)
    cmd=${cmd//\\$'\n'/ }
    # ssh, scp or rsync as a command word, past variable assignments, env, timeout and the like
    ssh_re='(^|[;&|(`'$'\n'']'')[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|command|exec|nohup|time|timeout[[:space:]]+[^[:space:]]+)[[:space:]]+)*([^[:space:];&|()`"'"'"']*/)?\\?["'"'"']?(ssh|scp|rsync)["'"'"']?([[:space:];&|)]|$)'
    if [[ $cmd =~ $ssh_re ]]; then
      word=${BASH_REMATCH[5]}
      jq -cn --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg w "$word" '{at: $at, event: "refused", reason: "direct-ssh", command: $w, tool: "Bash"}' >> "$log" 2>/dev/null
      printf 'Refused (direct-ssh): a direct %s call. Reach a machine only through scripts/machine-check.sh <machine> <check>, its fixed read-only checks; launching, steering and anything that writes go through the machine'"'"'s T3 environment.\n' "$word" >&2
      exit 2
    fi
    send_re='(^|[[:space:];&|(`"'"'"'])([^[:space:];&|()`"'"'"']*/)?\\?["'"'"']?t3["'"'"']?[[:space:]]+thread[[:space:]]+send([[:space:]]+|$)'
    set -f # the words below are split, never expanded against the hook's directory
    while [[ $cmd =~ $send_re ]]; do
      cmd=${cmd#*"${BASH_REMATCH[0]}"}
      id='' skip=false
      for w in $cmd; do
        $skip && { skip=false; continue; }
        case $w in
          --base-dir|--output-schema|--log-level) skip=true ;;
          -*) ;;
          *) if [[ $w =~ ^([0-9]*|&)(>>?|<)$ ]]; then skip=true # an operator alone takes the next word
             elif [[ $w =~ ^([0-9]*[\<\>]|\&\>) ]]; then : # a redirect word
             else id=$w; break; fi ;;
        esac
      done
      id=${id#[\"\']} id=${id%%[\"\';&|)<>\`]*}
      if [ -n "$id" ]; then threads+=("$id"); else sa_hook_log "$log" unjudged "a send names no thread"; fi
    done
    set +f ;;
  *) exit 0 ;;
esac
[ ${#threads[@]} -gt 0 ] || { [ "$tool" = Bash ] && exit 0; unjudged "the call names no thread"; }

if [ -f "$ledger" ]; then
  doc=$(jq -c "select(type == \"object\" and (.entries | type) == \"object\") | $sa_jq_migrate" "$ledger" 2>/dev/null)
  [ -n "$doc" ] || unjudged "the ledger is unreadable"
else doc='{"entries":{}}'; fi

# Each told send of this command, as {thread, tell_at}: held back until the whole command is
# allowed, and counted as spent against the later sends of the command.
pending='[]'
# judge <thread>: exit 0 allowed, 2 refused (its message on stderr)
judge() {
  local thread=$1 told verdict at reason why
  # the told lines of the thread: none for no log, null (every tell spent) for one that cannot be read
  if [ ! -e "$log" ]; then told='[]'
  else told=$(jq -Rsc --arg t "$thread" '[split("\n")[] | fromjson? | select(.event == "told" and .thread == $t) | .tell_at]' "$log" 2>/dev/null) || told=null; fi
  verdict=$(jq -r --arg t "$thread" --argjson told "$told" --argjson pend "$pending" --argjson now "$(sa_now_s)" "$sa_jq_open$sa_jq_tell"'
    (if $told == null then null else $told + [$pend[] | select(.thread == $t) | .tell_at] end) as $spent
    # the tells of this thread not yet spent by a told line, recorded in the last hour
    | ([(.tells // [])[] | select(.thread == $t) | .at] | group_by(.)
      | map(.[0] as $a | length - ([$spent[]? | select(. == $a)] | length) | select(. > 0) | [range(.) | $a]) | add // []) as $open
    | (if $spent == null then [] else [$open[] | select(tell_live($now))] end) as $live
    | ([.entries[] | select(.thread == $t and is_open)] | first) as $e
    | if .own_thread == $t then "allow"
      elif ($live | length) > 0 then "told \($live[0])"
      elif $e == null then "refuse not-held"
      elif $e.owner_run == true then "refuse owner-run"
      elif $e.steered == true then "refuse owner-steered"
      else "allow" end' <<<"$doc" 2>/dev/null) || { sa_hook_log "$log" unjudged "cannot judge a send"; return 0; }
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case $verdict in
    allow) return 0 ;;
    told*)
      pending=$(jq -c --arg t "$thread" --arg ta "${verdict#told }" '. + [{thread: $t, tell_at: $ta}]' <<<"$pending")
      return 0 ;;
    refuse*)
      reason=${verdict#refuse }
      jq -cn --arg at "$at" --arg r "$reason" --arg t "$thread" --arg tool "$tool" '{at: $at, event: "refused", reason: $r, thread: $t, tool: $tool}' >> "$log" 2>/dev/null
      case $reason in
        not-held) why="no open ledger entry holds thread $thread" ;;
        owner-run) why="thread $thread is owner-run: the owner took it" ;;
        *) why="thread $thread is owner-steered: the owner's message is the newest one in it" ;;
      esac
      printf 'Refused (%s): %s. Send nothing into it. Only the owner can allow one send, with "Tell <thread> X" (then run scripts/ledger.sh --ledger <ledger> tell <key or thread id> and send once); never allow it yourself.\n' "$reason" "$why" >&2
      return 2 ;;
  esac
  sa_hook_log "$log" unjudged "cannot judge a send"
}

refused=0
for thread in "${threads[@]}"; do
  # a Bash id spelled as a variable, substitution or escape is no literal; an MCP id always is
  if [ "$tool" = Bash ] && [[ $thread == [\$\`\\]* ]]; then sa_hook_log "$log" unjudged "a thread id that is no literal, so not judged"
  else judge "$thread" || refused=2; fi
done
if [ "$refused" = 0 ] && [ "$pending" != "[]" ]; then
  jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.[] | {at: $at, event: "told", thread, tell_at}' <<<"$pending" >> "$log" 2>/dev/null
fi
exit $refused
