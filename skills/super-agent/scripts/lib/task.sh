# A one-off task's contract line, sourced by _lib.sh: the last line of its launch message
# (`launch.d/task.sh`), and the adoption step-in `ledger adopt` answers for a task thread
# that never got it. `reconcile` settles a task on the `Result:` last line and raises
# `needs-owner` on the other.
# shellcheck disable=SC2034  # read by launch.d/task.sh and ledger.d/add.sh
sa_task_contract='Your final message ends with one last line: `Result: <one line> <link>`, the link to what you produced (a PR, a comment, or a file of findings in the repo, else in this folder), or `Needs owner: <question>` when only the owner can unblock you.'
