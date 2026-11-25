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

# --- a ledger a 0.45.0 super agent wrote: `paused` is owner-run (#1381 review) ----------------------
L add --repo $repo --number 5 --thread th-5 --worktree /wt/5 --branch b5 >/dev/null
L set $repo#5 paused true >/dev/null
check "an entry a 0.45.0 super agent paused is owner-run to the guard" "2 owner-run" "$(verdict "$(tool_call th-5)")"

# --- every send in a command, whatever path and flags it carries ----------------------------------------
check "an absolute path to t3 is judged" "2 owner-run" "$(verdict "$(bash_call '/home/x/.local/bin/t3 thread send th-2 hi')")"
# shellcheck disable=SC2088  # the literal `~` is the case: the guard accepts a home-relative path
check "so is a home-relative one" "2 owner-run" "$(verdict "$(bash_call '~/.local/bin/t3 thread send th-2 hi')")"
for sep in ';' '&&' '||' '|' $'\n'; do
  check "a refused send behind an allowed one after '${sep//$'\n'/newline}' is refused" "2 owner-run" \
    "$(verdict "$(bash_call "t3 thread send th-1 a $sep t3 thread send th-2 b")")"
done
for flag in '--base-dir /x' '--output-schema s.json' '--log-level debug'; do
  check "the value of $flag is no thread" "0 " "$(verdict "$(bash_call "t3 thread send $flag th-1 hi")")"
done
check "a quoted argument spelling out a send is judged as one (a known false positive)" "2 owner-run" \
  "$(verdict "$(bash_call 'git commit -m "docs: t3 thread send th-2 example"')")"
n=$(jq -s '[.[] | select(.event == "unjudged")] | length' "$log")
for id in '"$T"' '$T' '`id`' '\'; do
  check "a thread id of $id is not judged" "0 " "$(verdict "$(bash_call "t3 thread send $id hi")")"
done
check "each is logged unjudged" "$((n + 4))" "$(jq -s '[.[] | select(.event == "unjudged")] | length' "$log")"

# --- a tell is not revived by a log the guard cannot read, and lapses in an hour ---------------------------
L tell th-7 >/dev/null
mv "$log" "$log.keep"; mkdir "$log"
check "a log that exists but cannot be read spends every tell" "2 not-held" "$(verdict "$(tool_call th-7)")"
rmdir "$log"; mv "$log.keep" "$log"
check "read again, the tell is live and spent by one send" "0  2 not-held" "$(verdict "$(tool_call th-7)") $(verdict "$(tool_call th-7)")"
jq -c '.tells += [{thread: "th-8", at: "2026-01-01T00:00:00Z"}]' "$led" > "$led.n" && mv "$led.n" "$led"
check "a tell older than an hour has lapsed" "2 not-held" "$(verdict "$(tool_call th-8)")"
L tell th-8 >/dev/null
rm -f "$log"
check "a deleted log revives a tell inside the hour only: the fresh one passes, the lapsed one does not" "0  2 not-held" \
  "$(verdict "$(tool_call th-8)") $(verdict "$(tool_call th-8)")"

# --- round 2: a refused command spends no tell, and the command word is judged however it is written ---------
root=$PWD
L add --repo $repo --number 6 --thread th-o --worktree /wt/6 --branch b6 >/dev/null
L take $repo#6 >/dev/null
L tell th-q >/dev/null
check "a tell is not spent by a command the guard refuses (th-q told, th-o owner-run)" "2 owner-run" \
  "$(verdict "$(bash_call 't3 thread send th-q a; t3 thread send th-o b')")"
check "so the same send alone still has its tell" "0 " "$(verdict "$(bash_call 't3 thread send th-q a')")"
L tell th-r >/dev/null
check "one tell covers one send in a command: the second is refused, and the refusal spends nothing" "2 not-held" \
  "$(verdict "$(bash_call 't3 thread send th-r a && t3 thread send th-r b')")"
check "so one send alone has the tell" "0 " "$(verdict "$(bash_call 't3 thread send th-r a')")"
for cmd in '\t3 thread send th-o hi' '"t3" thread send th-o hi' "'t3' thread send th-o hi" $'t3 thread send \\\nth-o hi'; do
  check "a command word written as ${cmd//$'\n'/<newline>} is judged" "2 owner-run" "$(verdict "$(bash_call "$cmd")")"
done
mkdir "$tmp/glob" && : > "$tmp/glob/th-o"
check "a send's arguments are split, never glob-expanded against the hook's directory" "2 not-held" \
  "$(cd "$tmp/glob" && s=$root/$s verdict "$(bash_call 't3 thread send * hi')")"
check "a redirect glued to the id is no part of it: a held thread passes" "0 " "$(verdict "$(bash_call 't3 thread send th-1>/dev/null')")"
check "and an owner-run one is refused for the right reason" "2 owner-run" "$(verdict "$(bash_call 't3 thread send th-o>/dev/null')")"
for cmd in 't3 thread send >/dev/null th-o hi' 't3 thread send > out th-o hi' 't3 thread send <msg.txt th-o' 't3 thread send 2>/dev/null th-o hi' 't3 thread send 2>&1 th-o' 't3 thread send &> out th-o'; do
  check "a redirect before the id ($cmd) is no id: the send is judged on th-o" "2 owner-run" "$(verdict "$(bash_call "$cmd")")"
done
check "a backtick glued to the id is no part of it: a held thread passes" "0 " "$(verdict "$(bash_call 'echo `t3 thread send th-1`')")"
n=$(jq -s '[.[] | select(.event == "unjudged")] | length' "$log")
check "a command that matches a send but yields no id is allowed" "0 " "$(verdict "$(bash_call 'echo th-o | xargs t3 thread send')")"
check "and logged unjudged" "$((n + 1))" "$(jq -s '[.[] | select(.event == "unjudged")] | length' "$log")"
check "an MCP send with an empty threadId is allowed and logged unjudged too" "0  $((n + 2))" \
  "$(verdict "$(tool_call '')") $(jq -s '[.[] | select(.event == "unjudged")] | length' "$log")"
check "an MCP id is always literal: one that begins with a dollar sign is judged" "2 not-held" "$(verdict "$(tool_call '$X')")"
jq -c '.tells += [{thread: "th-\"x\\y", at: "not a time"}]' "$led" > "$led.n" && mv "$led.n" "$led"
check "a send the guard cannot judge, into a quoted id, is allowed" "0 " "$(verdict "$(tool_call 'th-"x\y')")"
check "and its unjudged line is still JSON, so the scorecard reads the log" "0" "$(jq -s . "$log" >/dev/null 2>&1; echo $?)"

# --- a tell drops the tells that lapsed, so the list holds the last hour's alone (#1381 review) --------
later=$(jq '[.tells[].at | try fromdateiso8601 catch empty] | max + 7200' "$led")  # two hours past the newest tell
SA_NOW=$later L tell th-8 >/dev/null
check "a tell two hours on leaves only itself in the ledger's tells, the unparseable one dropped too" \
  "th-8 $(jq -rn --argjson s "$later" '$s | todate')" "$(jq -r '.tells | map("\(.thread) \(.at)") | join(",")' "$led")"

finish
