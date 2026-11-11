# The wake's actions

## Contents

- [cleanup](#cleanup)
- [verify](#verify)
- [escalate](#escalate)

`scripts/` is under this skill's base directory. Reconcile marks an entry
`cleanup_owed` when it settles or closes and a ship entry `verify_owed` when it
first reaches `merged` or `settled` with a merged PR; the rows below stay until
the super agent clears the field or records a need
([watching](watching.md#the-wakes-actions)).

## cleanup

An entry ended and its thread and worktree are yours to close. Per row:

1. Settle the thread with `t3_thread_organize` action `settle` on its `thread`
   (and `environment_id`). Of kind `task`, first read its last message in a
   small slice and say its outcome in one chat line. Of kind `triage`, first
   confirm the issue now carries a ready label or the owner skill's other
   outcome.
2. Run `scripts/worktree.sh remove --ledger <ledger> <key>` (a remote entry:
   [remote](remote.md)); a `task` entry holding no worktree has nothing to
   remove. A `kept: true` result posts nothing; a refusal (exit 1) is an
   escalation.
3. Run `scripts/ledger.sh --ledger <ledger> set <key> cleanup_owed false`.

A settled entry is unwatched: a message to its thread goes unseen.

## verify

A ship PR merged. Check it (the row's `pr`) against the issue's acceptance
criteria, then `ledger.sh set <key> verify_owed false`. Unmet: record a need
naming the gap first. A row in stage `merged` waits for its thread to rest,
which settles it; do the check now.

## escalate

Only the owner can unblock it. Record one need per row with `ledger.sh need`
(SKILL.md, Escalation format), which silences the row. By `reason`:

- `permission-hold` (`detail` the held requests): name the thread, the held call
  and your recommendation; a held thread is not a stall.
- `fault` (`detail` the error kind): see [stall ladder](stall-ladder.md#errors);
  start the watcher again after escalating.
- `stall-cap`: the entry is at rest at 3 stalls and rung 3 of the ladder failed
  or does not apply.
- `pr-closed`, `issue-closed`: the ticket ended without a merge; name the
  reason. The row stays until the entry's `cleanup_owed` is cleared.
