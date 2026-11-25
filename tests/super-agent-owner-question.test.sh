#!/usr/bin/env bash
# super-agent's owner-question hooks: the question flag (a UserPromptSubmit hook)
# flags an owner-typed prompt holding a `?`, and never one T3 sent for an agent, a
# schedule or a finished background shell; the observe hook (a PreToolUse hook)
# logs each changing call made in a flagged turn, joined on the prompt's id, and
# passes it. A hook that cannot judge allows and logs. An offered fix is a need
# tied to no ledger entry.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json log=$tmp/question-flag.jsonl
F() { bash "$s/question-flag.sh" --ledger "$led" <<<"$1"; }
O() { bash "$s/observe.sh" --ledger "$led" <<<"$1"; }
prompt() { jq -cn --arg p "$1" --arg id "$2" '{hook_event_name: "UserPromptSubmit", prompt: $p, prompt_id: $id}'; }
bash_call() { jq -cn --arg c "$1" --arg id "$2" '{hook_event_name: "PreToolUse", prompt_id: $id, tool_name: "Bash", tool_input: {command: $c}}'; }
tool() { jq -cn --arg t "$1" --arg id "$2" '{hook_event_name: "PreToolUse", prompt_id: $id, tool_name: $t, tool_input: {file_path: "/x", message: "hi"}}'; }
events() { jq -r '.event' "$log" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }

# --- the question flag ----------------------------------------------------------
out=$(F "$(prompt 'why is this issue still open?' p1)"); rc=$?
check "an owner-typed prompt with a ? is flagged: the reminder line, exit 0" "0 1" "$rc $(grep -c '^Question flag:' <<<"$out")"
check "and its id is logged as a flag" '{"event":"flag","prompt_id":"p1"}' "$(jq -c '{event, prompt_id}' "$log")"
check "the reminder names the need's reason word and the reference" 2 "$(grep -o 'ask-first\|owner-question.md' <<<"$out" | wc -l)"
rm -f "$log"
out=$(F "$(prompt 'launch 1234 now' p2)"); rc=$?
check "an owner-typed prompt with no ? and no leading question word is not flagged" "0  none" "$rc $out $([ -f "$log" ] && echo logged || echo none)"
rm -f "$log"
for p in 'why is this issue still open' '  What is blocking 1234' 'how many are left' 'Which PR closed it'; do
  out=$(F "$(prompt "$p" p4)")
  check "a leading question word flags without a ? (${p:0:20})" 1 "$(grep -c '^Question flag:' <<<"$out")"
done
rm -f "$log"
out=$(F "$(prompt 'whatever, launch 1234' p5)")
check "a word that only starts with a question word is not flagged" " none" "$out $([ -f "$log" ] && echo logged || echo none)"
# T3's wording, pinned here so a change shows up as a red test (measured 2026-11-23, #1353)
agent='[T3 Code: the agent in T3 thread "mcp:launch:abc" sent this message, not the user.] why did it stall?'
sched='[T3 Code: scheduled task "scheduled-task:1" sent this prompt, not the user typing in this chat.] Backstop: what changed?'
note='<task-notification><summary>Background command "x?" completed</summary></task-notification>'
for p in "$agent" "$sched" "$note"; do
  out=$(F "$(prompt "$p" p3)")
  check "a prompt T3 sent, not the owner (${p:0:24}), is not flagged" " none" "$out $([ -f "$log" ] && echo logged || echo none)"
done

# --- the observe hook: each class of changing call is logged and passed ---------
rm -f "$log"; F "$(prompt 'why?' p1)" >/dev/null
changing=(
  "Bash|gh issue close 7|gh"
  "Bash|gh api repos/a/b/issues/7 -X PATCH -f state=closed|gh api"
  "Bash|git push origin main|git"
  "Bash|bash $s/launch.sh acme/w#7 --fleet f|launch.sh"
  "Bash|bash $s/claim.sh --repo a/b --number 7|claim.sh"
  "Bash|bash $s/worktree.sh remove --ledger l k|worktree.sh"
  "Bash|bash $s/ledger.sh --ledger l unneed k|ledger write verb"
  "Bash|bash $s/ledger.sh --ledger l drop k|ledger drop"
  "Bash|bash $s/ledger.sh --ledger '/tmp/a b/l.json' drop k|ledger drop, single-quoted path with a space"
  "Bash|bash $s/ledger.sh --ledger /tmp/a\\ b/l.json drop k|ledger drop, escaped path with a space"
  "Bash|cd x && $s/launch.sh acme/w#7|launch.sh run after a &&"
  "Bash|bash $s/merge.sh --pr 7|merge.sh"
  "Bash|bash $s/cleanup.sh --ledger l|cleanup.sh"
  "Bash|bash $s/intake.sh --fleet f --ledger l|intake.sh"
  "Bash|bash $s/handover.sh --ledger l|handover.sh"
  "mcp__t3-code__t3_thread_organize||T3 organize"
  "mcp__t3-code__delete_scheduled_task||T3 delete schedule"
  "Bash|bash $s/ledger.sh --ledger l self t-1|ledger self"
  "mcp__t3-code__link_pull_request||T3 link a PR"
  "Bash|t3 thread send t-1 hello|t3 CLI send"
  "Edit||Edit"
  "Write||Write"
  "mcp__t3-code__t3_thread_launch||T3 launch"
  "mcp__t3-code__t3_thread_send||T3 send"
  "mcp__t3-code__t3_thread_interrupt||T3 interrupt"
  "mcp__t3-code__schedule_task||T3 schedule"
)
for row in "${changing[@]}"; do
  IFS='|' read -r t cmd label <<<"$row"
  rm -f "$log"; F "$(prompt 'why?' p1)" >/dev/null
  if [ "$t" = Bash ]; then out=$(O "$(bash_call "$cmd" p1)"); else out=$(O "$(tool "$t" p1)"); fi; rc=$?
  check "a $label call in a flagged turn passes, printing nothing" "0 " "$rc $out"
  check "and is logged against the prompt's id" "flag changing p1 $t" "$(events) $(jq -r 'select(.event == "changing") | "\(.prompt_id) \(.tool)"' "$log")"
done
rm -f "$log"; F "$(prompt 'why?' p1)" >/dev/null
for cmd in "bash $s/ledger.sh --ledger l need k --action 'Close 7, or wait for the PR, add a note, set it, drop it?' --reason ask-first" "bash $s/ledger.sh --ledger l need k --action a --reason ask-first" "bash $s/ledger.sh --ledger l list --open" \
  "bash $s/ledger.sh --ledger l get k" "bash $s/launch-check.sh acme/w#7" "bash scripts/check.sh full" "shellcheck $s/observe.sh" \
  "bash $s/worktree.sh list" "cat $s/launch.sh" "bash $s/launch.sh --help" "grep -n merge.sh $s/_lib.sh" "git status" "git log --oneline" "gh issue view 7" "gh api repos/a/b/issues/7" "jq . $led" "bash $s/status.sh --ledger l"; do
  O "$(bash_call "$cmd" p1)" >/dev/null
done
for t in Read Grep mcp__t3-code__t3_thread_read mcp__t3-code__t3_thread_list; do O "$(tool "$t" p1)" >/dev/null; done
check "a read, a machine check and recording a need are not logged" flag "$(events)"
O "$(bash_call 'gh issue close 7' p-next)" >/dev/null
check "a changing call in the next turn (another prompt id) is not logged" flag "$(events)"
rm -f "$log"
out=$(O "$(bash_call 'gh issue close 7' p1)"); rc=$?
check "with no flag log at all a changing call passes and writes none" "0  none" "$rc $out $([ -f "$log" ] && echo logged || echo none)"
rm -f "$log"; F "$(prompt 'why?' p1)" >/dev/null
O "$(jq -cn '{prompt_id: "p1", tool_name: "Bash", tool_input: {command: ("gh issue close 7 " + ("x" * 400))}}')" >/dev/null
check "a long call is cut at 300 characters" 300 "$(jq -r 'select(.event == "changing") | .call | length' "$log")"

# --- a hook that cannot judge allows and logs ------------------------------------
rm -f "$log"
for input in 'not json' '' '{"tool_name":"Bash"}' '{"prompt_id":"p1"}'; do
  out=$(O "$input"); rc=$?
  check "observe: an input with no prompt_id and tool_name ($input) allows" "0 " "$rc $out"
done
check "and logs each as unjudged" "unjudged unjudged unjudged unjudged" "$(events)"
rm -f "$log"
for input in 'not json' '' '{"prompt":"why?"}' '{"prompt_id":"p1"}'; do
  out=$(F "$input"); rc=$?
  check "question flag: an input with no prompt and prompt_id ($input) flags nothing" "0 " "$rc $out"
done
check "and logs each as unjudged" "unjudged unjudged unjudged unjudged" "$(events)"
mkdir -p "$tmp/nojq"
for t in bash date dirname cat mkdir grep; do ln -s "$(command -v $t)" "$tmp/nojq/$t"; done
for h in question-flag observe; do
  rm -f "$log"
  out=$(PATH=$tmp/nojq bash "$s/$h.sh" --ledger "$led" <<<"$(prompt 'why?' p1)"); rc=$?
  check "$h: a missing jq allows" "0 " "$rc $out"
  check "and leaves a line written without jq" "unjudged true" "$(grep -o '"event":"unjudged"' "$log" | head -1 | cut -d'"' -f4) $(jq -s 'all(.[]; (.at | type) == "string")' "$log")"
done
for h in question-flag observe; do
  out=$(bash "$s/$h.sh" --bogus 2>/dev/null); rc=$?
  check_rc "$h: a usage error exits 2, which the generated entry swallows" 2 "$rc"
  check "the generated $h entry ends || true" 1 \
    "$(bash -c 'source "$1/_lib.sh"; "$2"' _ "$PWD/$s" "$([ "$h" = observe ] && echo sa_observe_entry || echo sa_question_flag_entry)" | jq -r '.hooks[0].command' | grep -c ' || true$')"
done

# --- an offer is a need tied to no ledger entry ----------------------------------
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
key=task:ask-first-close-7
out=$(L need "$key" --action 'Close acme/widgets#7 as a duplicate?' --reason ask-first)
check "an offer is recorded with no ledger entry, its reason ask-first" "$key ask-first" "$(jq -r '"\(.need.key) \(.need.reason)"' <<<"$out")"
check "the ledger holds no entry for it" '[]' "$(L list | jq -c .entries)"
fleet=$tmp/fleet.json; printf '{"machines":{}}\n' > "$fleet"
check "it shows under Needs you in the status block" 1 \
  "$(bash "$s/status.sh" --ledger "$led" 2>/dev/null | jq -r '.block // .status.block // empty' | grep -c "Needs you.*$key")"
check "it survives a second record with the same action (one row)" 1 \
  "$(L need "$key" --action 'Close acme/widgets#7 as a duplicate?' --reason ask-first >/dev/null; L list | jq '.needs | length')"
check "the owner's reply clears it" '{"key":"task:ask-first-close-7","removed":true}' "$(L unneed "$key" | jq -c .)"
check "and the ledger holds none" 0 "$(L list | jq '.needs | length')"

# --- the scorecard counts them: the target is live, at 0 ---------------------------
check "the scorecard's target for question turns holding a changing call is live, at 0" '{"max":0}' \
  "$(jq -c '."questions.with_write"' skills/super-agent/scorecard/targets.json)"

# --- the release rule is written down in the reference page ----------------
check "the reference page holds the refusing-version and four-weeks rule" "1 1" \
  "$(tr '\n' ' ' < skills/super-agent/reference/owner-question.md | grep -c 'puts a refusing version to the owner') $(tr '\n' ' ' < skills/super-agent/reference/owner-question.md | grep -c 'four weeks puts the observe hook up for deletion')"

finish
