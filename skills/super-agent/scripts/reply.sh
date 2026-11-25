#!/usr/bin/env bash
# The remote reply file writer: turn a saved `t3_thread_read` result into the file
# `--remote` reads in place of `t3 thread show`, which has no environment flag.
# Writing a reply file by hand once read a finished run as stalled and missed a
# finish, so this is the only way to write one (reference/remote.md).
#
#   reply <read file> --dir <dir> [--owner-only]
#
# The read is the JSON `t3_thread_read` printed, its default `messages` view. The
# reply is `<dir>/<thread id>.json`: the read's thread fields `reconcile` reads, the
# last assistant message by position, whatever order the items came in, and `owner_at`,
# the `updatedAt` of the newest user message by position when its `createdBy` is `user`
# (the owner typed it: a super agent send is `agent`, a `/compact` `system`), else null;
# a page holding no user message at all has no `owner_at` key, which is unknown, not null.
# `reconcile --reads <dir>` (or `--remote` for a linked machine) takes an owner-steered
# thread from it (it keeps the mark it has on unknown), since the `t3` CLI returns no
# message author. With `--owner-only` the file holds the thread id and `owner_at` alone,
# written from a read of any size (a truncated last message or a missing assistant message
# is no refusal), for `--reads`: it is no reply for `--remote`. A last
# message whose text was cut short (`textTruncated`) is refused, and so is a page
# with no assistant message while `hasMore` says older items exist: the waiting line
# and the merge-gate summary sit at a message's end, so either read gives a false
# verdict. Read it again with a larger `maxCharsPerItem` or `limit`. A read whose
# thread lacks a field `reconcile` requires, or one with no `hasMore`, is refused
# too: no file `reconcile` would call `shape` is written, and a read that cannot say
# whether an older page exists gives no verdict.
#
# stdout: {file, thread, status} (the read's `thread.status`, also for `--owner-only`)
# exit: 0 written · 1 the read cannot give a verdict (last message truncated, or no
#       assistant message with `hasMore`), nothing written · 2 usage, or a read that is
#       not a `t3_thread_read` result
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reply <read file> --dir <dir> [--owner-only]'
sa_help "$usage" "$@"
read_file='' dir='' owner_only=false
while [ $# -gt 0 ]; do
  case $1 in
    --dir) sa_flag_value "$usage" "${2:-}"; dir=$2; shift 2 ;;
    --owner-only) owner_only=true; shift ;;
    -*) sa_tooling "$usage" ;;
    *) [ -z "$read_file" ] || sa_tooling "$usage"; read_file=$1; shift ;;
  esac
done
[ -n "$read_file" ] && [ -n "$dir" ] || sa_tooling "$usage"
[ -f "$read_file" ] || sa_tooling "$read_file: no such file"

reply=$(jq -c "$sa_jq_thread_shape"'
  if (.items | type) != "array" or (.hasMore | type) != "boolean" or (thread_shape | not) then empty else
    ([.items[] | select(.type == "assistant_message")] | sort_by(.position) | last) as $last
    | {thread: (.thread | {threadId, status, runCount, pendingRequestCount, worktreePath, branch, updatedAt}
          | with_entries(select(.value != null))),
       messages: (if $last == null then [] else [{role: "assistant", text: ($last.text // "")}] end),
       truncated: ($last.textTruncated == true),
       older: ($last == null and .hasMore == true)}
    # a page with no user message has no owner_at key: unknown, not null
    + (([.items[] | select(.type == "user_message")] | sort_by(.position) | last) as $u
       | if $u == null then {} else {owner_at: (if $u.createdBy == "user" then ($u.updatedAt // null) else null end)} end)
  end' "$read_file" 2>/dev/null)
[ -n "$reply" ] || sa_tooling "$read_file: not a t3_thread_read result"
status=$(jq -r .thread.status <<<"$reply")
if $owner_only; then
  reply=$(jq -c '{thread: {threadId: .thread.threadId}} + (if has("owner_at") then {owner_at} else {} end)' <<<"$reply")
elif [ "$(jq -r .truncated <<<"$reply")" = true ]; then
  sa_fail "the last assistant message is truncated: read the thread again with a larger maxCharsPerItem"
elif [ "$(jq -r .older <<<"$reply")" = true ]; then
  sa_fail "the page holds no assistant message and hasMore is true: read the thread again with a larger limit"
fi
thread=$(jq -r .thread.threadId <<<"$reply")
sa_thread_file_ok "$thread" || sa_tooling "$thread: a thread id with a slash cannot name a file"
mkdir -p "$dir" && jq -c 'del(.truncated, .older)' <<<"$reply" > "$dir/$thread.json" || sa_tooling "$dir: cannot write"
jq -cn --arg f "$dir/$thread.json" --arg t "$thread" --arg s "$status" '{file: $f, thread: $t, status: $s}'
