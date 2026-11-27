# Tasks

## Contents

- [What the pinned thread answers](#what-the-pinned-thread-answers)
- [Launching a task](#launching-a-task)
- [How a task ends](#how-a-task-ends)
- [An adopted task thread](#an-adopted-task-thread)

`scripts/` is under this skill's base directory. A **task** is any thread that
is no ticket's: a **one-off task** does one bounded job and ends on its own
`Result:` line; an **interactive task** (a grill) waits on the owner by design
and leaves only on the owner's "Drop".

## What the pinned thread answers

Answer in this thread only what your own record holds: the ledger, the status
block and the GitHub state of the entries. Anything that needs new reading,
research, a test or a change is a one-off task, whatever its size: a secret
rotation, a dotfile edit, a deploy, a question about code you have not read.
Only an asked machine check runs inline.

The owner asks in plain words. "Run", "research", "test" or "deploy X" is a
one-off task; "grill me on X" is an interactive one. Echo what you understood
in one line ("Task deploy-dashboard: deploy the dashboard to the dev host"),
then launch it.

## Launching a task

`scripts/launch.sh task <slug> --ask '<the ask>' --fleet <fleet> --ledger
<ledger> --quota <file> --machine <this machine's fleet key> --out <launch
file>`, `<slug>` a short name in letters, digits, `.`, `_` and `-`. Add `--repo
<owner/name>` when the work belongs to a repo, `--skill <name>` when a skill
runs it (`scripts/skills.sh` lists them), `--interactive` for a grill (a grill
skill sets it by itself), and the placement flags a ticket takes (`--gpu`,
`--account`, `--area` with a repo, `--exclude`, `--readings`). It claims
nothing and reads no issue, routes the task as an M and records it at
`launching`. Act on its answer as on a ticket's (step 1 of the loop): `ask`,
`no_instance` and `need_reading` the same way; `launch: true` goes to
`t3_thread_launch` and `launch.sh record --launch <launch file>`.

- A one-off task is placed as a ticket is: it takes a slot and honours pins.
  When nothing fits it answers `waiting`, and the ledger holds a `task:<slug>`
  waiting row carrying its ask, repo and skill. Reconcile lists that row in
  `ready` on every wake: relaunch it with `launch.sh task` and the row's
  values; an answer of `waiting` again leaves it waiting.
- An interactive task takes no slot and runs on this machine.
- With `--repo` the thread works in a worktree on `task/<slug>`; with none it
  runs in a scratch folder (`args.scratch`), and `needs` is empty.

## How a task ends

A one-off task's launch message ends with the contract line
(`sa_task_contract`, `scripts/lib/task.sh`): its final message's last line is
`Result: <one line> <link>`, the link to what it produced, findings written to
a file in the repo or the scratch folder, or `Needs owner: <question>`.
Reconcile reads that line once the thread has run and rests:

- `Result:` settles the entry. The next status block prints it once in the
  `Finished` row, `task:<slug>: <result>`, the result's link the link to what
  it produced. Its cleanup row follows as for any settled entry.
- `Needs owner:` leaves it at rest with no stall and raises one `needs-owner`
  escalate row ([wake-actions](wake-actions.md#escalate)); the owner's answer
  goes into the thread as the need's step-in.
- Any other last line is a rest like a ticket's, and counts a stall: climb the
  stall ladder.

An interactive task carries no contract line: it is never settled on its rest
and counts no stall.

## An adopted task thread

A one-off task thread you adopt never got the contract line. `ledger.sh adopt`
answers it as `step_in` for a new non-interactive task entry: send it once
with `t3_thread_send`, as the adoption step-in
([step-ins](step-ins.md#the-step-ins)). A re-adopt of a thread the ledger
holds (`existing: true`), a ship or triage thread and an interactive task
answer none.
