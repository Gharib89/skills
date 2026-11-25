#!/usr/bin/env bash
# Replay: the super agent answered inside a thread the owner was running (9 Nov,
# issue #1381; decision #1319). Nothing but the skill's prose stopped a send into a
# thread the ledger did not hold, held as the owner's, or last spoken in by the
# owner. The incident version is the scripts at 3ee029c8, which have no call guard.
# The fixture is hand-built through `ledger set` (a verb the incident version has):
# one held thread, one marked `owner_run`, one marked `steered`, and one the ledger
# does not hold, each on the fake `t3` (tests/super-agent-fake.sh), which records every
# send. Only an exit 2 blocks a PreToolUse call in Claude Code, so the send runs unless
# the hook exited 2: a missing script (exit 127) lets it through, which is what makes
# this case red on the incident version. Fixed: the three refused sends reach nothing,
# and a send to the held, unmarked thread still goes.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=acme/widgets
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
for n in 1 2 3; do
  L add --repo $repo --number $n --thread "th-$n" --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
done
L set $repo#2 owner_run true >/dev/null
L set $repo#3 steered true >/dev/null
for t in th-1 th-2 th-3 th-9; do sa_thread $t idle 1 0 "/wt/$t" "feat/$t"; done

# hook <form> <thread>: the PreToolUse input of a send, as the T3 tool or as the CLI
hook() {
  case $1 in
    tool) jq -cn --arg t "$2" '{hook_event_name: "PreToolUse", tool_name: "mcp__t3-code__t3_thread_send", tool_input: {threadId: $t, message: "ping"}}' ;;
    bash) jq -cn --arg t "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: ("t3 thread send " + $t + " ping")}}' ;;
  esac
}
# attempt <form> <thread>: run the hook, and the send unless the hook exited 2
attempt() {
  : > "$SA_FAKE/calls"
  bash "$s/call-guard.sh" --ledger "$led" <<<"$(hook "$1" "$2")" >/dev/null 2>&1
  [ $? -eq 2 ] || t3 thread send "$2" ping >/dev/null 2>&1
}
sent() { grep -c "^t3 thread send $1 " "$SA_FAKE/calls"; }

for form in tool bash; do
  for case in "th-9 a thread the ledger does not hold" "th-2 a thread held as owner-run" "th-3 a thread held as owner-steered"; do
    t=${case%% *} what=${case#* }
    attempt "$form" "$t"
    check "$form: a send to $what reaches nothing" 0 "$(sent "$t")"
  done
  attempt "$form" th-1
  check "$form: a send to a held thread no mark touches still reaches it" 1 "$(sent th-1)"
done

finish
