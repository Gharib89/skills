#!/usr/bin/env bash
# The question flag: a UserPromptSubmit hook that marks an owner turn which may be
# an owner question (reference/owner-question.md). A prompt holding a `?` and
# carrying no T3 sender prefix is flagged: one `{at, event: "flag", prompt_id}`
# line goes to `question-flag.jsonl` beside the ledger, where the observe hook
# joins on the id, and one reminder line goes to the turn on stdout. A prompt T3
# sent for an agent, a scheduled task or a finished background shell starts with
# `[T3 Code:` or `<task-notification>`, so the loop's own prompts are never
# flagged (measured 2026-11-23, #1353). The super agent still judges question or
# request, so a misfire costs one ignored line. A hook that cannot judge (no `jq`,
# input that is no prompt) flags nothing and logs `unjudged`. Written by
# `setup.sh --write` and every handover into the super agent folder's generated
# settings.
#
#   question-flag [--ledger <file>]      (the UserPromptSubmit JSON on stdin)
#
# contract: bare-run
# stdout: a flagged prompt prints the reminder line; anything else prints nothing
# exit: 0 always but a usage error, which the generated entry swallows (`|| true`):
#       a UserPromptSubmit hook's exit 2 erases the prompt
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/lib/hook-log.sh" || exit 0
log=$(sa_hook_log_file question-flag "$@")
unjudged() { sa_hook_log "$log" unjudged "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || unjudged "no jq"
source "$here/_lib.sh" || unjudged "cannot source _lib.sh"
usage='usage: question-flag [--ledger <file>]'
sa_help "$usage" "$@"
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}" ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
input=$(cat)
id=$(jq -er '.prompt_id | strings | select(length > 0)' <<<"$input" 2>/dev/null) || unjudged "the hook input has no prompt_id"
prompt=$(jq -er '.prompt | strings' <<<"$input" 2>/dev/null) || unjudged "the hook input has no prompt"

case $prompt in '[T3 Code:'* | '<task-notification>'*) exit 0 ;; esac
case $prompt in *\?*) ;; *) exit 0 ;; esac
jq -cn --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$id" '{at: $at, event: "flag", prompt_id: $id}' >> "$log" 2>/dev/null || unjudged "cannot write the log"
printf '%s\n' "Question flag: this prompt holds a ? and no sender prefix, so it may be an owner question. If it asks and tells nothing, open with the answer from the record re-read now, offer the fix as a numbered option recorded as a need (--reason ask-first), and change nothing (reference/owner-question.md)."
