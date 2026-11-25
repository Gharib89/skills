# Handing a thread over

The owner's four phrases about a thread, and the **call guard** that backs
them. Echo the phrase in one line ("Taking th-1: ...") before acting on it.
`scripts/` is under this skill's base directory.

## Watch <thread>

A thread someone else launched is adopted from one read. Call
`t3_thread_read` with `afterPosition: -1` and a low `limit`, save the result to
a file, then:

`ledger.sh --ledger <ledger> adopt --read <file>` (`--repo <owner/name>` when
the thread's worktree has no `origin` remote; `--task <slug>` for a thread
that is no ticket's; `--machine` and `--environment` for a linked machine).

The entry is filled from the read: worktree, branch and first pull request
from the thread, and the ticket from the first message (`/ship-run <n>` is a
ship, `/triage <n>` a triage). A first message that is neither, with no
`--task`, is refused. Adoption starts the clock (`launched_at`, `held_since`)
and posts the claim for a ship thread. Then run steps 2 to 4 as for a launched
thread. Adopting a thread the ledger holds leaves one entry: it is **given
back** when owner-run, and its owner-steered mark is cleared.

## I'll take <thread>

`ledger.sh --ledger <ledger> take <key>`. The entry is **owner-run**: it keeps
its slot, gets no step-in, no stall and no cleanup, its open needs are
cleared, and it is read from GitHub alone (a ticket's settles when its PR
merges or its issue closes; a task's stays until dropped or given back). Send
nothing into it, merge nothing for it, never remove its worktree. The status
block lists it under `Yours`. After 3 days one `owner-run` escalate row asks
"watch or drop?", once. "Watch <thread>" gives it back: watching restarts from
the thread's state now.

## Drop <thread>

`ledger.sh --ledger <ledger> drop <key>` removes the entry, leaving its claim
and worktree to the owner. An interactive task leaves no other way.

## Tell <thread> X

The owner's one-off message into a thread the call guard refuses:
`ledger.sh --ledger <ledger> tell <key or thread id>`, then send X once. The
tell records a dated ruling and is spent by that one send; a second send is
refused again.

## The call guard

`scripts/call-guard.sh` is a PreToolUse hook of the super agent folder's
generated settings ([setup](setup.md#the-guard-hook)). It refuses, with exit
2, a send (`t3_thread_send`, `t3_thread_send_attachments`, or `t3 thread send`
in Bash) into a thread that is:

- `not-held`: no open ledger entry holds it;
- `owner-run`: the owner took it;
- `owner-steered`: the newest message from outside the thread is the owner's.

Your own thread and an unspent `tell` pass. Each refusal is a line of
`call-guard.jsonl` beside the ledger, which the scorecard counts per week. A
refusal is a fact: report it, never work around it, never send by another
route.

## Owner-steered

`reply.sh` reads who spoke last (`owner_at`), and `reconcile.sh --ledger
<ledger> --reads <dir>` (the directory of those reply files) marks the entry
`steered` when the owner's message is the newest from outside the thread and
newer than `held_since`. A steered entry counts no stall and gets no nudge; its
`Running` row ends `(you spoke last)`. After the stall window at rest one
`owner-steered` escalate row asks "watch or take?": answer it as
[wake actions](wake-actions.md#escalate) says. Save each local thread's
`t3_thread_read` and convert it with `reply.sh --dir <reads dir>` before
reconcile, as for [remote entries](remote.md).
