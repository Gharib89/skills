# Watching and reconciling

What `watch.sh` and `reconcile.sh` count as a change or a stall. Their `--help`
lists the fields; this file holds the rules behind them.

## Watch

- A finished run is reported only if it is still at rest `--recheck` seconds
  later (default 90): a run awaiting its own subagent restarts.
- `stall-window` is an entry at rest with no new run for `--stall-window`
  seconds (default 900).
- It re-reads the ledger each poll, and skips an entry `reconcile` has not
  observed yet (`unobserved`).
- A remote entry (an `environment_id`) is read from GitHub alone, found by its
  branch: `pr-opened`, `checks-finished` (the checks on its head went from none
  or pending to done), `pr-merged` and `pr-closed`. Its thread fields stay the
  last reconcile's, so the thread's own finish is read on a wake.
- A thread at rest whose last message ends on the waiting line
  (`Waiting on my own background work.`, set by the launch brief) is still
  working: it raises no `run-finished` event and gains no stall until the stall
  window has passed since the thread rested (its `updatedAt`), then the rest
  counts like any other. Reconcile reads it the same way, as `running`.
- A PR that merges while its thread still runs (or waits on the line) raises
  one `pr-merged` event, when the thread rests or `--stall-window` seconds have
  passed since the merge, whichever comes first, not two. A remote entry's
  `pr-merged` is not held: its thread read is stale.
- One watcher runs per ledger: a second start exits 1 with `running`, and the
  first is left alone.

## The wake's actions

- `reconcile` marks an entry `cleanup_owed` when it settles or closes, and a
  ship entry `verify_owed` when it first reaches `merged` or `settled` with a
  merged PR. `cleanup`, `verify` and `escalate` list them, in every answer,
  until the super agent clears the field (`ledger set <key> cleanup_owed false`)
  or, for `escalate`, records a need. An entry settled before these fields
  existed has neither, so it prints no row.
- `escalate` gives one row per entry, the first of: a permission request
  (`permission-hold`), a recorded error (`fault`), 3 stalls at rest
  (`stall-cap`), a closed PR or issue still owing its cleanup (`pr-closed`,
  `issue-closed`).
- `pulse.sh` runs reconcile and reads the watcher's lock: a backstop turn that
  finds the watcher alive and nothing to act on ends there.
- `ledger set` refuses `stage`: only reconcile moves it. `rethread` clears both
  owed fields with the rest of the entry's state.

## Settling a triage entry

- A `--kind triage` entry settles when its thread has run, is at rest, and the
  issue carries neither `needs-triage` nor `needs-info`: a grill waiting on the
  owner has `needs-info` and stays `at-rest`.
- `reconcile` reads a settled triage entry's thread once more each run. A run
  count above the settled one, or a running thread, reopens it (`woke`). The
  watcher does not see a settled entry, so a `woke` shows at the next reconcile.

## Settling a task entry

- A `--kind task` entry has no ticket. It is `running` while its thread runs and
  `settled` once the thread has run (a run count of 1 or more) and is at rest
  with no permission request, whatever any issue or PR says: a task whose
  branch's PR merged stays open while its thread runs.

## Unqueued issues

- `reconcile --ledger <file> --fleet <file>` lists an open issue in an active
  repo that was created since the earliest open entry launched, and that no
  entry of any stage, waiting row or `super-agent-claim` comment holds. Each
  is listed once (the ledger keeps `unqueued_offered`) and launched only on the
  owner's go.

## Stalls

- A stall (a completed run with no merged PR and no merge-gate summary, or a
  window passed with no new run) adds 1.
- A real step (a run ending in the merge-gate summary, or a PR opened) takes 1
  off, never below 0.
- An entry at 3 stalls gains none.
- `stalled` holds one `{key, thread, stalls, reason}` per stall counted now.
