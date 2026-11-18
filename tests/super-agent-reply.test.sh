#!/usr/bin/env bash
# `reply.sh` turns a saved `t3_thread_read` result into the reply file `--remote`
# reads, and reconcile reads that file with the verdict it gives the same thread
# on this machine (the fake `t3` answering for the local copy). Fake `t3` and `gh`
# are on PATH (tests/super-agent-fake.sh).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/dir"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills
rep() { bash "$s/reply.sh" "$@"; }

# A `t3_thread_read` result as the tool prints it: a thread object and `items`
# oldest first within the page, only the assistant ones carrying the text.
read_of() { # <status> <last assistant text> [<truncated: true|false>]
  jq -cn --arg st "$1" --arg t "$2" --argjson tr "${3:-false}" '
    {thread: {threadId: "t-6", status: $st, runCount: 3, pendingRequestCount: 0,
       worktreePath: "/wt/6", branch: "feat/x-6", updatedAt: "2026-11-18T15:40:20.493Z",
       title: "skills#6", link: "x", pullRequests: [], settled: false},
     recentRuns: [],
     items: [
       {position: 5, type: "assistant_message", text: "an earlier message", textTruncated: false},
       {position: 9, type: "user_message", text: "nudge", textTruncated: false},
       {position: 13, type: "assistant_message", text: $t, textTruncated: $tr}],
     nextPosition: 13, hasMore: false, earlierPosition: 5}' > "$tmp/read.json"
}

# the verdict reconcile gives the entry for thread t-6: its thread observation
verdict() { # <entry flags...>: the entry's `observed`, without its PR
  rm -rf "$led"
  bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 6 --thread t-6 --worktree /wt/6 --branch feat/x-6 "$@" >/dev/null
  sa_pr $repo feat/x-6 none; sa_issue $repo 6 open
  bash "$s/reconcile.sh" --ledger "$led" --remote "env-a=$tmp/dir" >/dev/null
  bash "$s/ledger.sh" --ledger "$led" get "$repo#6" | jq -c '.observed | del(.pr)'
}

for case in "waiting|idle|Done for now.\n\nWaiting on my own background work." \
            "gate|idle|ship 0.68.0\nUnmet criteria: none" \
            "plain|running|working on it"; do
  IFS='|' read -r name status text <<<"$case"
  text=$(printf '%b' "$text")
  read_of "$status" "$text"
  out=$(rep "$tmp/read.json" --dir "$tmp/dir"); rc=$?
  check_rc "$name: the converter exits 0" 0 "$rc"
  check "$name: it names the file it wrote" "$tmp/dir/t-6.json" "$(jq -r .file <<<"$out")"
  remote=$(verdict --environment env-a)
  sa_thread t-6 "$status" 3 0 /wt/6 feat/x-6 "$text" 2026-11-18T15:40:20.493Z
  local_v=$(verdict)
  check "$name: the remote path reads the verdict the thread gives locally" "$local_v" "$remote"
done

# --- a message cut short would hide the waiting line, so the converter refuses ----------
read_of idle "Waiting on my own" true
rm -f "$tmp/dir/t-6.json"
out=$(rep "$tmp/read.json" --dir "$tmp/dir" 2>/dev/null); rc=$?
check_rc "a truncated last message exits 1" 1 "$rc"
check "and writes no file" "no" "$([ -e "$tmp/dir/t-6.json" ] && echo yes || echo no)"

# --- a thread with no assistant message still converts ----------------------------------
read_of idle x; jq -c '.items = []' "$tmp/read.json" > "$tmp/empty.json"
rep "$tmp/empty.json" --dir "$tmp/dir" >/dev/null
check "no assistant message gives an empty messages list" "[]" "$(jq -c .messages "$tmp/dir/t-6.json")"

# --- bad input is tooling ---------------------------------------------------------------
printf 'not json\n' > "$tmp/bad.json"
rep "$tmp/bad.json" --dir "$tmp/dir" >/dev/null 2>&1; check_rc "a file that is not JSON exits 2" 2 "$?"
echo '{"messages":[]}' > "$tmp/bad.json"
rep "$tmp/bad.json" --dir "$tmp/dir" >/dev/null 2>&1; check_rc "a read with no thread object exits 2" 2 "$?"
rep "$tmp/read.json" >/dev/null 2>&1; check_rc "no --dir exits 2" 2 "$?"
finish
