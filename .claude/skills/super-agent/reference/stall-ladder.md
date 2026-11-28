# The stall ladder and unreadable entries

## Contents

- [The ladder](#the-ladder)
- [A usage-limit stop](#a-usage-limit-stop)
- [Errors](#errors)

`scripts/` is under this skill's base directory.

## The ladder

Climb the **stall ladder**, keyed on the entry's `stalls` after reconcile:

1. Nudge the same thread with `t3_thread_send`: it keeps its context, and a
   run's `completed` does not mean the ticket is done.
2. Send the same thread the missing fact: read its last messages first, then
   send only what they show it lacks, never the launch message or a rule again
   ([step-ins](step-ins.md#the-step-ins)).
3. Start a fresh thread on a raised tier: run the loop's steps 1 and 2 again
   with the first launch's flags plus `--raise` set to the rungs the entry's
   model and effort sit above its size default, plus one, and `record
   --rethread` to point the entry at the new thread (a task's launch is
   `launch.sh task`, [tasks](tasks.md#how-a-task-ends)). The owner is asked only
   when route's `ask` is true (Routing). Escalate instead when the ticket's
   premise or scope, not the thread, is the problem.

A **hard finding** (a verified acceptance-criterion gap you send back to the
thread) raises the same way as rung 3.

An entry you escalated at 3 stalls stays quiet until the owner
answers; then reset it with `ledger.sh --ledger <ledger> reset-stalls <key>`,
which records a ruling.

## A usage-limit stop

A run's limit stop ends on a line such as `You've hit your 5-hour limit ·
resets 6:10pm (Africa/Cairo)`. T3 resumes that thread by itself after the
reset, and a 5-hour stop outlasts the stall window, so a nudge would land on a
thread about to resume. Reconcile reads the line and its reset (the first such
clock time after the thread's rest, in the zone named) and counts the thread as
running, with no stall, until the reset plus the stall window: climb nothing
before then. A thread still at rest after that is an ordinary stall, and the
ladder starts at rung 1. A reset reconcile cannot read leaves the rest
ordinary.

## Errors

An entry reconcile could not read or match (`kind` says why: a
thread, PR or issue unreadable, or a thread of another id or worktree
path) gets no action from you: escalate it. Reconcile records the kind in
the entry's `error`, and the watcher stays quiet about a recorded fault, so
start it again after escalating. A `thread-unreadable` naming an
`environment_id` is its machine's SSH read failing: act on its `reason` as
[remote](remote.md#errors) says.
