# The stall ladder and unreadable entries

## Contents

- [The ladder](#the-ladder)
- [Errors](#errors)

`scripts/` is under this skill's base directory.

## The ladder

Climb the **stall ladder**, keyed on the entry's `stalls` after reconcile:

1. Nudge the same thread with `t3_thread_send`: it keeps its context, and a
   run's `completed` does not mean the ticket is done.
2. Re-brief the same thread: read its last messages first, then resend the
   launch brief with what it was missing.
3. Start a fresh thread on a raised tier: run the loop's steps 1 and 2 again
   with the first launch's flags plus `--raise` set to the rungs the entry's
   model and effort sit above its size default, plus one, and `record
   --rethread` to point the entry at the new thread. The owner is asked only
   when route's `ask` is true (Routing). Escalate instead when the ticket's
   premise or scope, not the thread, is the problem.

A **hard finding** (a verified acceptance-criterion gap you send back to the
thread) raises the same way as rung 3.

An entry you escalated at 3 stalls stays quiet until the owner
answers; then reset it with `ledger.sh --ledger <ledger> set <key> stalls 0`.

## Errors

An entry reconcile could not read or match (`kind` says why: a
thread, PR or issue unreadable, or a thread of another id or worktree
path) gets no action from you: escalate it. Reconcile records the kind in
the entry's `error`, and the watcher stays quiet about a recorded fault, so
start it again after escalating. A `thread-unreadable` naming an
`environment_id` is a stale read: refresh it and rerun.
