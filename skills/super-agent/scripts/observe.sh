#!/usr/bin/env bash
# The observe hook: a PreToolUse hook that logs each changing call the super agent
# makes in a flagged turn, and passes it: nothing is refused. A turn is flagged when
# `question-flag.jsonl` holds a `flag` line for the call's `prompt_id`, which the
# hook input carries and equals the id of the prompt that started the turn (measured
# 2026-11-23, #1353), so the two hooks share no flag file and the next turn is never
# flagged. A changing call is on a named list: the T3 calls that launch, send to,
# interrupt, organize, configure, schedule, delete a schedule or link a PR; the acting
# scripts (`launch.sh`, `claim.sh`, `worktree.sh remove`, `merge.sh`,
# `cleanup.sh`, `intake.sh`, `handover.sh`) and `ledger.sh`'s write verbs
# other than `need`; the `gh` and `git` verbs that write (the patterns
# `lib/changing.sh` shares with the scorecard); Edit, Write, MultiEdit and
# NotebookEdit. A machine check is none. Each one appends `{at, event:
# "changing", prompt_id, tool, call}` to the log, `call` cut at 300 characters. A
# hook that cannot judge (no `jq`, input that is no tool call, a call it cannot
# classify) allows the call and logs `unjudged`. Written by `setup.sh --write` and every
# handover into the super agent folder's generated settings.
#
#   observe [--ledger <file>]      (the PreToolUse JSON on stdin)
#
# contract: bare-run
# stdout: nothing
# exit: 0 always but a usage error, which the generated entry swallows (`|| true`):
#       a PreToolUse hook's exit 2 refuses the call
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/lib/hook-log.sh" || exit 0
log=$(sa_hook_log_file question-flag "$@")
unjudged() { sa_hook_log "$log" unjudged "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || unjudged "no jq"
source "$here/_lib.sh" || unjudged "cannot source _lib.sh"
usage='usage: observe [--ledger <file>]'
sa_help "$usage" "$@"
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}" ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
input=$(cat)
head=$(jq -er 'if type == "object" and (.prompt_id | type) == "string" and (.tool_name | type) == "string" then "\(.prompt_id) \(.tool_name)" else error("no prompt_id and tool_name") end' <<<"$input" 2>/dev/null) \
  || unjudged "the hook input is no tool call with a prompt_id"
id=${head%% *} tool=${head#* }
# The turn is flagged only if the prompt hook logged its id; most calls end here.
[ -f "$log" ] && grep -qF -- "\"event\":\"flag\",\"prompt_id\":\"$id\"" "$log" 2>/dev/null || exit 0

line=$(jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$id" --arg tool "$tool" "$sa_jq_changing"'
  def question_bash: [ledger_write(ledger_verbs - ["need"])] + acting_scripts + host_writes | join("|");
  def question_tools: ["Edit", "Write", "MultiEdit", "NotebookEdit", "mcp__t3-code__t3_thread_launch",
    "mcp__t3-code__create_threads", "mcp__t3-code__delegate_task", "mcp__t3-code__t3_thread_send",
    "mcp__t3-code__t3_thread_send_attachments", "mcp__t3-code__t3_thread_interrupt", "mcp__t3-code__schedule_task",
    "mcp__t3-code__run_scheduled_task_now", "mcp__t3-code__t3_thread_organize", "mcp__t3-code__t3_thread_configure",
    "mcp__t3-code__delete_scheduled_task", "mcp__t3-code__link_pull_request"];
  (.tool_input // {}) as $in
  | if ($tool | IN(question_tools[])) or ($tool == "Bash" and (($in.command // "") | test(question_bash)))
    then {at: $at, event: "changing", prompt_id: $id, tool: $tool, call: (($in.command // $in.file_path // ($in | tojson)) | tostring | .[0:300])}
    else empty end' <<<"$input" 2>/dev/null) || unjudged "cannot classify the call"
[ -z "$line" ] || printf '%s\n' "$line" >> "$log" 2>/dev/null || unjudged "cannot write the log"
exit 0
