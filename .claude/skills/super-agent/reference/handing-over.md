# Handing a thread over

The owner's four phrases about a thread, and the **call guard** that backs them.
Echo the phrase in one line ("Taking th-1: ...") before acting on it. `scripts/`
is under this skill's base directory.

## Watch <thread>

`<thread>` here is a thread id, one the ledger may not hold yet. When the owner
names the thread by title, find its id with `t3_thread_list` (or
`t3_thread_search`) and ask when two match. A thread someone else launched is
adopted from one read. Call `t3_thread_read` with `afterPosition: -1` and a low
`limit`, save the result to a file, then:

`ledger.sh --ledger <ledger> adopt --read <file>` (`--repo <owner/name>` when
the thread's worktree has no GitHub `origin` remote; `--task <slug>` for a
thread that is no ticket's; `--machine` and `--environment` for a linked
machine).

The entry is filled from the read: worktree and branch from the thread, and the
ticket from the first message (`/ship-run <n>` is a ship, `/triage <n>` a
triage). A first message that is neither, with no `--task` or `--number`, is
refused. The first reconcile finds the PR by the branch. Adoption starts the
clock (`launched_at`, `held_since`) and posts the claim for a ship thread.

`adopt` is the launched thread's record step. Then reconcile once (it takes the
baseline the watcher compares against) and start the watcher, as steps 5 and 3
of the loop say. A thread the ledger already holds stays one entry: when it was
owner-run it stops being owner-run, and its owner-steered mark and need are
cleared. Naming another key for it (a different `--task`, `--number` or ticket)
is refused: drop that entry first, or run `adopt --thread <id>` with no read and
no ticket flags. A `--number` is only for a first message that names no ticket;
the first message's kind (ship or triage) wins.

## I'll take <thread>

`ledger.sh --ledger <ledger> take <key>` (the entry's key). The entry is
**owner-run**: it keeps its slot, gets no step-in, no stall and no cleanup, its
open needs are cleared, and it is read from GitHub alone (a ticket's settles
when its PR merges or its issue closes; a task's stays until "Drop" or "Watch").
Send nothing into it, merge nothing for it, never remove its worktree. The
status block lists it under `Yours`. After 3 days one `owner-run` escalate row
asks "watch or drop?", once; it rides the next wake (the hourly backstop runs
pulse). "Watch <thread>" ends it: watching restarts from the thread's state now.
A ledger from 0.45.0 may hold `paused: true`; it reads as `owner_run` and
`paused` is dropped at the next write.

## Drop <thread>

`ledger.sh --ledger <ledger> drop <key>` (the entry's key) removes the entry,
leaving its claim and worktree to the owner. An interactive task leaves no other
way.

## Tell <thread> X

The owner's one-off message into a thread. Only the owner's own "Tell <thread>
X" allows it, never your judgment that they would want it. Record the tell
first, then send, never the other way: `ledger.sh --ledger <ledger> tell <key or
thread id>`, then send X once with `t3_thread_send`. The tell records a dated
ruling and is bound to the entry's thread at tell time; the next send to that
thread spends it, and a second send is refused again. A tell the owner gave more
than an hour ago has lapsed.

## The call guard

`scripts/call-guard.sh` is a PreToolUse hook of the super agent folder's
generated settings ([setup](setup.md#the-guard-hook)). It refuses, with exit 2,
a send (`t3_thread_send`, `t3_thread_send_attachments`, or `t3 thread send` in
Bash) into a thread that is:

- `not-held`: no open ledger entry holds it;
- `owner-run`: the owner took it;
- `owner-steered`: the newest message from outside the thread is the owner's.

Your own thread and an unspent `tell` pass. Each refusal is a line of
`call-guard.jsonl` beside the ledger, which the scorecard counts per week. A
refusal is a fact: report it, never work around it, never send by another route.

## Owner-steered

A message of the owner's in a supervised thread leaves its entry in the ledger:
never unwatch, settle or rethread it for that. `reply.sh` reads who spoke last
(`owner_at`), and `reconcile.sh --ledger <ledger> --reads <dir>` (the directory
of those reply files) marks the entry `steered` when the owner's message is the
newest from outside the thread and newer than `held_since` (else `launched_at`).
A steered entry counts no stall and gets no nudge; its `Running` row ends `(you
spoke last)`, and the call guard refuses your sends into it. After the stall
window at rest, and not at a merge-gate summary, one `owner-steered` escalate
row asks "watch or take?" on every reconcile, and the watcher wakes once per
stall window, until you record its need: answer it as [wake
actions](wake-actions.md#escalate) says, and record a need (`--reason
owner-steered`) so the row and the watcher's wake stay quiet. The owner's answer
decides: "I'll take <thread>" makes it owner-run, "Watch <thread>" watches it
again and clears that need, so the next steer is asked about afresh. The loop's
"Thread reads" paragraph in [SKILL.md](../SKILL.md) says how the reads are saved
and passed. More in [the owner steps in](step-ins.md#the-owner-steps-in).
