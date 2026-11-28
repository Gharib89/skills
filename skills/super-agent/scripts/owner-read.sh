#!/usr/bin/env bash
# The owner read: turn a saved `t3_thread_read` result into the file `reconcile
# --reads <dir>` takes an owner-steered thread from, since the `t3` CLI returns no
# message author (probed 2026-11-28: each message holds only `role`, `runId` and
# `text`). The same read serves a thread on a linked machine, read with its
# `environmentId`.
#
#   owner-read <read file> --dir <dir>
#
# The read is the JSON `t3_thread_read` printed, its default `messages` view, of any
# size. The file is `<dir>/<thread id>.json`: the thread id and `owner_at`, the
# `updatedAt` of the newest user message by position when its `createdBy` is `user`
# (the owner typed it: a super agent send is `agent`, a `/compact` `system`), else
# null; a page holding no user message at all has no `owner_at` key, which is
# unknown, not null, and keeps the entry's mark.
#
# stdout: {file, thread, status} (the read's `thread.status`)
# exit: 0 written · 2 usage, or a read that is not a `t3_thread_read` result
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: owner-read <read file> --dir <dir>'
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

read=$(jq -c "$sa_jq_thread_shape"'
  if (.items | type) != "array" or (thread_shape | not) then empty else
    {thread: {threadId: .thread.threadId}, status: .thread.status}
    # a page with no user message has no owner_at key: unknown, not null
    + (([.items[] | select(.type == "user_message")] | sort_by(.position) | last) as $u
       | if $u == null then {} else {owner_at: (if $u.createdBy == "user" then ($u.updatedAt // null) else null end)} end)
  end' "$read_file" 2>/dev/null)
[ -n "$read" ] || sa_tooling "$read_file: not a t3_thread_read result"
thread=$(jq -r .thread.threadId <<<"$read") status=$(jq -r .status <<<"$read")
sa_thread_file_ok "$thread" || sa_tooling "$thread: a thread id with a slash cannot name a file"
mkdir -p "$dir" && jq -c 'del(.status)' <<<"$read" > "$dir/$thread.json" || sa_tooling "$dir: cannot write"
jq -cn --arg f "$dir/$thread.json" --arg t "$thread" --arg s "$status" '{file: $f, thread: $t, status: $s}'
