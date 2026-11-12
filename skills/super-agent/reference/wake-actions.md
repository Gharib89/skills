# The wake's actions

## Contents

- [cleanup](#cleanup)
- [verify](#verify)
- [escalate](#escalate)
- [Merge-gate holds](#merge-gate-holds)
- [parents_done](#parents_done)

`scripts/` is under this skill's base directory. Reconcile marks an entry
`cleanup_owed` when it settles or closes and a ship entry `verify_owed` when it
first reaches `merged` or `settled` with a merged PR; the rows below stay until
the super agent clears the field or records a need
([watching](watching.md#the-wakes-actions)).

## cleanup

An entry ended and its thread and worktree are yours to close. Per row:

1. Settle the thread with `t3_thread_organize` action `settle` on its `thread`
   (and `environment_id`), skipping that call when its status is already
   `settled`. Of kind `task`, first read its last message in a small slice and
   say its outcome in one chat line. Of kind `triage`, first confirm the issue
   now carries a ready label or the owner skill's other outcome; with none,
   record a need naming the gap and go on.
2. Settle the threads the entry's thread started (its helper and review
   threads): `t3_thread_list` with `includeSubagents` and the entry's
   `environment_id`, each row whose `parentThreadId` is the entry's thread.
   Settle each one at rest (status not `running` or `waiting`, not already
   `settled`) the same way, once. Read nothing of it and send it nothing. With
   one still running, skip steps 3 and 4: the row stays, so a later wake
   settles it.
3. Run `scripts/worktree.sh remove --ledger <ledger> <key>` (a remote entry:
   [remote](remote.md)); a `task` entry holding no worktree has nothing to
   remove. A `kept: true` result posts nothing; on a refusal (exit 1) record a
   need and skip step 4, so the row stays. Add `--delete-branch` only when the
   owner asked to delete the branch: it deletes a merged PR's local branch
   after the worktree goes, and never otherwise.
4. Run `scripts/ledger.sh --ledger <ledger> set <key> cleanup_owed false`.

A settled entry is unwatched: a message to its thread goes unseen.

## verify

A ship PR merged. Check it (the row's `pr`) against the issue's acceptance
criteria, then `ledger.sh set <key> verify_owed false`. Unmet: record a need
naming the gap first, with `--reason verify` (the PR merged, so the owner
decides, not the thread). A row in stage `merged` waits for its thread to rest,
which settles it; do the check now.

## escalate

Only the owner can unblock it. Record one need per row with `ledger.sh need`
(SKILL.md, Escalation format), adding `--reason <the row's reason>`: it silences
that row only, so a later cause on the entry still prints. By `reason`:

- `permission-hold` (`detail` the held requests): name the thread, the held call
  and your recommendation; a held thread is not a stall.
- `fault` (`detail` the error kind): see [stall ladder](stall-ladder.md#errors);
  start the watcher again after escalating.
- `stall-cap`: the entry is at rest at 3 stalls. A `stalled` row may print on
  the same wake: run rung 3 of the [stall ladder](stall-ladder.md) first, or
  judge it does not apply, then record the need.
- `pr-closed`, `issue-closed`: the ticket ended without a merge; name the
  reason. The row stays until the entry's `cleanup_owed` is cleared.

## Merge-gate holds

A run's hold outside the merge allowance and the standing waivers follows the
fleet file's `merge_gate_ruler`. `owner` (the default, and a fleet file without
the key): record a need with `ledger.sh need`. `super-agent`: you rule on the
hold, record it with `ledger.sh ruling`, tell the run in its thread (the run
acts on it and writes nothing of it into a PR body), and say it in the next
status block. A ruling you cannot defend is the owner's: record a need.

A hold on a failure the PR did not cause (a red check on the base, a script the
PR never touched) is never waived, whichever way the ruler is set, and no
ruling or run may waive it. Per hold:

1. File the failure as its own issue, ordered before the ticket
   ([lessons](lessons.md)), and put it first on the waiting list
   (`ledger.sh wait <its key> --reason failure --order 0`); a ticket with
   no thread yet waits behind it (`ledger.sh wait <key> --reason failure
   --after <its key>`).
2. The held ticket's PR stays unmerged, its entry open and watched; tell its run
   in its thread to wait for that fix.
3. When reconcile shows the fix's entry `merged`, tell the run to re-run the
   gate.

## parents_done

An open parent issue whose sub-issues are all closed, listed once per parent
(the ledger keeps `parents_offered`). Say it in one chat line, key and title,
and offer to close it. Close it only on the owner's word, with `gh api -X PATCH
repos/<owner/name>/issues/<n> -f state=closed -f state_reason=completed`, and
verify `state` closed by REST.
