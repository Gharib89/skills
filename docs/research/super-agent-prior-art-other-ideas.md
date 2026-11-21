# Prior art for the super agent: ideas no pain point names

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Useful ideas none of the eleven pain points names

1. **Count only records as evidence, never text on a screen.** A Fleet agent
   merged because a reviewer's pane showed `VERDICT: LGTM` from an interrupted
   review; the fix accepts a verdict only as a structured record with the
   commit reviewed and the tree's fingerprint. **sourced** (Fleet part 3) The
   super agent reads a thread's last message for a merge-gate summary, which is
   text; tie what it acts on to the PR head SHA. **inferred**
2. **Input comes only from sent messages.** Fleet's Chief read grey suggestion
   text in an empty input box as the owner's approval and deleted eight
   worktrees. **sourced** (Fleet part 3) T3 thread reads are structured, so the
   risk is lower, but a quoted instruction inside a supervised thread's output
   is the same class: only the owner's own messages are consent. **inferred**
3. **The guard runs the gate itself.** An agent chained `gate | grep && merge`
   and the grep matched the failure lines; the fix is a guard that runs the
   gate, confirms the pass line and refuses a chained merge. **sourced** (Fleet
   part 3)
4. **Done means verified by something other than the author, with a
   deterministic floor.** The verdict is "verified, not resolved, or
   inconclusive, and only verified closes the ticket". **sourced** (ryle.dev)
   The skill's `verify` row is this; the floor (a check the model cannot
   override) is the part to add. **inferred**
5. **A step with no explicit outcome is a bug.** "A step that exits green
   without doing anything is the most expensive bug you'll have." **sourced**
   (ryle.dev) Applies to every schedule the super agent owns: an expected run
   that did not happen should be an event. **inferred**
6. **Every incident becomes a deterministic replay.** Batty runs its real
   daemon against fake agent shims; "Every regression scenario started life as
   a real bug from production telemetry." **sourced** (Batty) Each "it did not
   watch" incident from the evidence ticket should land as a fixture for
   `watch.sh` and `reconcile.sh`. **inferred**
7. **Measure the wait on the owner.** "Median time to respond to
   `needs_input`, and total time sessions spent blocked waiting on me";
   swapping in a smarter model does not move it. **sourced** (Agent Pulse)
   Fleet splits a human decision into waiting time and attention cost, which
   are fixed differently. **sourced** (Fleet part 4) Needs already have a
   record; add the open and close time and report the median in the weekly
   retro. **inferred**
8. **Draw the ask-first line by reversibility.** Four questions: can it be
   undone, who is hurt if it is wrong, can a machine verify it, and does it
   touch money, production, credentials or deletion (that last one always
   stays with the person). **sourced** (Fleet part 4) This is a ready frame
   for the map's open question "which actions the super agent must ask about".
   **inferred**
9. **A patrol for what no screen shows.** Fleet's second agent looks only for
   problems absent from every board, and on its fourth round found that an
   "escalate" verdict had nowhere to route: 124 correct verdicts in six days
   had arrived looking like model malfunctions. **sourced** (Fleet part 2) A
   scripted invariants pass fits here: worktrees with no entry, branches with
   commits in no PR, a schedule bound to a settled thread, a need older than a
   week. **inferred**
10. **A cooldown on self-healing.** Batty's stall handler re-fired right after
    its own restart and looped; the fix holds the restarted member idle until
    its first state event. **sourced** (Batty) The stall ladder's rethread
    deserves the same guard. **inferred**
11. **Keep limits out of the agents' reach.** "Pauses, spending limits and
    merge rights belong on the server." **sourced** (ryle.dev) Branch
    protection and the ship profile already carry merge rights; a spend cap on
    an away session (FirstMate records one at `/afk`) is the missing one.
    **inferred**
12. **Handoffs carry a path and a hash.** Every handoff line names a file and
    its SHA-256 so the next session can prove it has the exact file meant.
    **sourced** (Dan Mercede) Cheap to add to the bearings file. **inferred**
