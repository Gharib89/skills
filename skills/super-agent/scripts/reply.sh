#!/usr/bin/env bash
# The remote reply file writer: turn a saved `t3_thread_read` result into the file
# `--remote` reads in place of `t3 thread show`, which has no environment flag.
# Writing a reply file by hand once read a finished run as stalled and missed a
# finish, so this is the only way to write one (reference/remote.md).
#
#   reply <read file> --dir <dir>
#
# The read is the JSON `t3_thread_read` printed, its default `messages` view. The
# reply is `<dir>/<thread id>.json`: the read's thread fields `reconcile` reads and
# the last assistant message by position, whatever order the items came in. A last
# message whose text was cut short (`textTruncated`) is refused, and so is a page
# with no assistant message while `hasMore` says older items exist: the waiting line
# and the merge-gate summary sit at a message's end, so either read gives a false
# verdict. Read it again with a larger `maxCharsPerItem` or `limit`. A read whose
# thread lacks a field `reconcile` requires is refused too, so no file it would call
# `shape` is written.
#
# stdout: {file, thread, status}
# exit: 0 written · 1 the read cannot give a verdict (last message truncated, or no
#       assistant message with `hasMore`), nothing written · 2 usage, or a read that is
#       not a `t3_thread_read` result
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: reply <read file> --dir <dir>'
sa_help "$usage" "$@"
read_file='' dir=''
while [ $# -gt 0 ]; do
  case $1 in
    --dir) sa_flag_value "$usage" "${2:-}"; dir=$2; shift 2 ;;
    -*) sa_tooling "$usage" ;;
    *) [ -z "$read_file" ] || sa_tooling "$usage"; read_file=$1; shift ;;
  esac
done
[ -n "$read_file" ] && [ -n "$dir" ] || sa_tooling "$usage"
[ -f "$read_file" ] || sa_tooling "$read_file: no such file"

reply=$(jq -c '
  if (.items | type) != "array"
     or (.thread | type) != "object"
     or (.thread.threadId | type) != "string" or (.thread.status | type) != "string"
     or (.thread.runCount | type) != "number" or (.thread.pendingRequestCount | type) != "number"
  then empty else
    ([.items[] | select(.type == "assistant_message")] | sort_by(.position) | last) as $last
    | {thread: (.thread | {threadId, status, runCount, pendingRequestCount, worktreePath, branch, updatedAt}
          | with_entries(select(.value != null))),
       messages: (if $last == null then [] else [{role: "assistant", text: ($last.text // "")}] end),
       truncated: ($last.textTruncated == true),
       older: ($last == null and .hasMore == true)}
  end' "$read_file" 2>/dev/null)
[ -n "$reply" ] || sa_tooling "$read_file: not a t3_thread_read result"
if [ "$(jq -r .truncated <<<"$reply")" = true ]; then
  sa_fail "the last assistant message is truncated: read the thread again with a larger maxCharsPerItem"
fi
if [ "$(jq -r .older <<<"$reply")" = true ]; then
  sa_fail "the page holds no assistant message and hasMore is true: read the thread again with a larger limit"
fi
thread=$(jq -r .thread.threadId <<<"$reply")
case $thread in */*) sa_tooling "$thread: a thread id with a slash cannot name a file" ;; esac
mkdir -p "$dir" && jq -c 'del(.truncated, .older)' <<<"$reply" > "$dir/$thread.json" || sa_tooling "$dir: cannot write"
jq -cn --arg f "$dir/$thread.json" --arg t "$thread" --arg s "$(jq -r .thread.status <<<"$reply")" '{file: $f, thread: $t, status: $s}'
