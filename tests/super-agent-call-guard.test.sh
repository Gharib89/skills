#!/usr/bin/env bash
# super-agent's call guard (#1381): the PreToolUse hook `call-guard.sh` that refuses a
# send into a thread the ledger does not hold, holds as owner-run or marks
# owner-steered, the owner's `tell` that lets exactly one send through and records a
# dated ruling, and the log lines it writes. The hook is driven with hand-built
# PreToolUse inputs over a hand-built ledger; no fake `t3` is needed, since the hook
# judges the call and never makes it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json log=$tmp/call-guard.jsonl
repo=acme/widgets
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
G() { bash "$s/call-guard.sh" --ledger "$led"; }
tool_call() { jq -cn --arg n "${2:-mcp__t3-code__t3_thread_send}" --arg t "$1" '{hook_event_name: "PreToolUse", tool_name: $n, tool_input: {threadId: $t, message: "x"}}'; }
bash_call() { jq -cn --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}'; }
# verdict <input>: the hook's exit code, and its stderr's first word after "Refused ("
verdict() { local err rc; err=$(G <<<"$1" 2>&1 >/dev/null); rc=$?; printf '%s %s' "$rc" "$(sed -n 's/^Refused (\([a-z-]*\)).*/\1/p' <<<"$err")"; }

L add --repo $repo --number 1 --thread th-1 --worktree /wt/1 --branch b1 >/dev/null
L add --repo $repo --number 2 --thread th-2 --worktree /wt/2 --branch b2 >/dev/null
L add --repo $repo --number 3 --thread th-3 --worktree /wt/3 --branch b3 >/dev/null
L add --repo $repo --number 4 --thread th-4 --worktree /wt/4 --branch b4 >/dev/null
L self th-super >/dev/null
L take $repo#2 >/dev/null
L set $repo#3 steered true >/dev/null
jq -c '.entries["acme/widgets#4"].stage = "closed"' "$led" > "$led.n" && mv "$led.n" "$led"

check "a thread an open, unmarked entry holds is allowed" "0 " "$(verdict "$(tool_call th-1)")"
check "so is the same thread's attachment send" "0 " "$(verdict "$(tool_call th-1 mcp__t3-code__t3_thread_send_attachments)")"
check "and a Bash t3 thread send to it" "0 " "$(verdict "$(bash_call 't3 thread send th-1 "hello there"')")"
check "the super agent's own thread is allowed" "0 " "$(verdict "$(tool_call th-super)")"
check "a thread the ledger does not hold is refused, not-held" "2 not-held" "$(verdict "$(tool_call th-9)")"
check "an owner-run entry's thread is refused, owner-run" "2 owner-run" "$(verdict "$(tool_call th-2)")"
check "an owner-steered entry's thread is refused, owner-steered" "2 owner-steered" "$(verdict "$(tool_call th-3)")"
check "a closed entry's thread is no longer held" "2 not-held" "$(verdict "$(tool_call th-4)")"
check "a Bash send is judged by the id after t3 thread send, in a chain, past a flag" "2 owner-run" \
  "$(verdict "$(bash_call 'cd /x && t3 thread send --json th-2 "msg"')")"
check "a Bash command that sends nothing is none of the guard's business" "0 " "$(verdict "$(bash_call 't3 thread show th-2 --json')")"
check "nor is another tool" "0 " "$(verdict "$(jq -cn '{tool_name: "Read", tool_input: {file_path: "/x"}}')")"

# --- the refusal says why and names the override ------------------------------------
err=$(G <<<"$(tool_call th-2)" 2>&1 >/dev/null)
check "the refusal on stderr names the reason and the tell override" "1 1" \
  "$(grep -c 'owner-run' <<<"$err") $(grep -c 'ledger.sh --ledger <ledger> tell' <<<"$err")"

# --- each refusal is one JSON line with its reason ----------------------------------------
check "the log holds one refused line per refusal, each a JSON object with its reason, thread and tool (the last from the stderr check)" \
  "not-held th-9 mcp__t3-code__t3_thread_send|owner-run th-2 mcp__t3-code__t3_thread_send|owner-steered th-3 mcp__t3-code__t3_thread_send|not-held th-4 mcp__t3-code__t3_thread_send|owner-run th-2 Bash|owner-run th-2 mcp__t3-code__t3_thread_send" \
  "$(jq -r 'select(.event == "refused") | "\(.reason) \(.thread) \(.tool)"' "$log" | paste -sd'|')"
check "each line is stamped" 6 "$(jq -s '[.[] | select(.event == "refused" and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")))] | length' "$log")"

# --- the tell lets exactly one send through and records a dated ruling ------------------
out=$(L tell $repo#2); rc=$?
check_rc "tell exits 0" 0 "$rc"
check "it answers the thread and the ruling" "th-2 1" "$(jq -r '[.thread, (.ruling.text | contains("Owner tell") and contains("th-2") | if . then 1 else 0 end)] | map(tostring) | join(" ")' <<<"$out")"
check "the ruling is dated" 1 "$(L list | jq '[.rulings[] | select((.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.text | contains("Owner tell: one send into acme/widgets#2")))] | length')"
check "the told send passes" "0 " "$(verdict "$(tool_call th-2)")"
check "and is logged told, naming its tell" "th-2" "$(jq -r 'select(.event == "told") | .thread' "$log")"
check "the second send is refused again" "2 owner-run" "$(verdict "$(tool_call th-2)")"
L tell th-9 >/dev/null
check "a tell by thread id lets a thread the ledger does not hold have one send" "0  2 not-held" "$(verdict "$(tool_call th-9)") $(verdict "$(tool_call th-9)")"
check "a tell by a key the ledger lacks is refused" 1 "$(L tell $repo#99 >/dev/null 2>&1; echo $?)"
L tell $repo#2 >/dev/null; L tell $repo#2 >/dev/null
check "two tells let two sends through" "0  0  2 owner-run" "$(verdict "$(tool_call th-2)") $(verdict "$(tool_call th-2)") $(verdict "$(tool_call th-2)")"

# --- a call it cannot judge is allowed and logged ---------------------------------------
check "input that is no JSON is allowed" "0 " "$(verdict 'not json')"
check "a send naming no thread is allowed" "0 " "$(verdict "$(jq -cn '{tool_name: "mcp__t3-code__t3_thread_send", tool_input: {message: "x"}}')")"
check "both are logged unjudged, with why" "2" "$(jq -s '[.[] | select(.event == "unjudged" and (.why | length > 0))] | length' "$log")"
printf 'not json\n' > "$tmp/bad.json"
err=$(bash "$s/call-guard.sh" --ledger "$tmp/bad.json" <<<"$(tool_call th-2)" 2>&1); rc=$?
check "a ledger that is not JSON is allowed too" "0 " "$rc $err"
check "a hook usage error is exit 2, not a swallowed one" 2 "$(bash "$s/call-guard.sh" --bogus </dev/null >/dev/null 2>&1; echo $?)"

finish
