# A one-off task's helpers, sourced by _lib.sh. Its contract line is the last line of its
# launch message (`launch.d/task.sh`, and a ticket-form `--skill` task's in `launch.sh`),
# and the adoption step-in `ledger adopt` answers for a task thread that never got it.
# `reconcile` settles a task on the `Result:` last line and raises `needs-owner` on the
# other, each read through `sa_task_end`.
# shellcheck disable=SC2034  # read by launch.sh, launch.d/task.sh and ledger.d/add.sh
sa_task_contract='Your final message ends with one last line: `Result: <one line> <link>`, the link to what you produced (a PR, a comment, or a file of findings in the repo, else in this folder), or `Needs owner: <question>` when only the owner can unblock you.'

# sa_task_slug_ok <slug>: true when the slug fits a `task:<slug>` key (letters, digits,
# `.`, `_` and `-`, not empty, not starting with `.`).
sa_task_slug_ok() { case $1 in ''|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac; }

# sa_task_end <last line>: the line a model wrote with its markup taken off (a trailing CR,
# a leading `- ` or `* ` list marker, wrapping backticks or `**`, and backticks, `**` or `*`
# around the label), so `- **Result:** x` and `**Result: x**` read `Result: x`. The label
# stays case-sensitive: `result: x` is no contract line.
sa_task_end() {
  sed -E 's/\r$//; s/^[-*] +//; s/^`([^`]*)`$/\1/; s/^\*\*([^*]*)\*\*$/\1/; s/^(`|\*\*|\*)(Result|Needs owner)(:?)\1(:?)/\2\3\4/' <<<"$1"
}
