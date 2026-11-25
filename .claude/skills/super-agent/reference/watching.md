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
  (`Waiting on my own background work.`, set by ship's run contract, or for a
  triage thread by the contract line its launch message carries) is still
  working: it raises no `run-finished` event and gains no stall until the stall
  window has passed since the thread rested (its `updatedAt`), then the rest
  counts like any other. Reconcile reads it the same way, as `running`.
- A thread at rest on a usage-limit line (`... limit · resets 6:10pm
  (Africa/Cairo)`) is read the same way, with the reset in place of the rest: no
  `run-finished` and no stall until the reset plus the stall window, since T3
  resumes it at the reset by itself
  ([stall ladder](stall-ladder.md#a-usage-limit-stop)).
- A PR that merges while its thread still runs (or waits on the line) raises
  one `pr-merged` event, when the thread rests or `--stall-window` seconds have
  passed since the merge, whichever comes first. Past the window with the
  thread still working, its later rest raises `run-finished` once more, which
  settles the entry. A remote entry's `pr-merged` is not held: its thread read
  is stale.
- One watcher runs per ledger: a second start exits 1 with `running`, and the
  first is left alone.

## The wake timer

Every other alarm in the loop is the super agent, so a turn that died (a limit
stop, an auth error) or a host restart that cancelled the watcher wakes
nothing. The wake timer is a systemd user timer that runs `wake-timer.sh` every
5 minutes, with no model. Its `--help` has the rules; in short:

- It acts only while `watch.sh --ledger <ledger> --owed` says a watcher is owed. With the super
  agent's own thread (`own_thread` in the ledger) idle, it sends the thread one
  line: `Wake timer: no watcher is running. Run pulse and restart the watcher.`
- A running thread is the watch guard's. A limit stop is held until its reset
  plus 10 minutes; a reset it cannot read gets the wake.
- The fleet file's **notify** command, `{"command": <shell text>, "delay":
  <whole seconds of 1 or more, 600 when unset>}`, runs once when the send
  fails, when no reconcile follows the wake within the delay, or when a
  permission request has waited 10 minutes on the thread, with
  `SA_NOTIFY_MESSAGE` set. With T3 not answering, or no command, the desktop
  notifier stands in.
- An outage, from the first owed tick to the next reconcile, gets one wake and
  at most one notify, logged as JSON lines in `wake-timer.jsonl` beside the
  ledger.
- `guard.sh --install` prints the two unit files and the line that enables
  them; installing them is the owner's. A timer systemctl does not report
  running is a `Needs you` row at setup and each handover.

## The wake's actions

`reconcile` marks an entry `cleanup_owed` when it settles or closes, and a ship
entry `verify_owed` when it first reaches `merged` or `settled` with a merged
PR (an entry settled before these fields existed has neither, so no row). Its
`cleanup`, `verify` and `escalate` rows stay in every answer until the super
agent clears the field or, for `escalate`, records a need:
[wake-actions](wake-actions.md) holds each row's steps. `pulse.sh` runs
reconcile and reads the watcher's lock. `ledger set` refuses `stage`: reconcile
moves it, and `add` and `rethread` start it at `launched` (`launch` writes
`add --launching`, stage `launching`, before its thread exists); `rethread`
clears both owed fields.

## Settling a triage entry

- A `--kind triage` entry settles when its thread has run, is at rest, and the
  issue carries neither `needs-triage` nor `needs-info`: a grill waiting on the
  owner has `needs-info` and stays `at-rest`.
- `reconcile` reads the thread of a triage entry settled in the last 7 days once
  more each run; an older one is not read. A run count above the settled one,
  or a running thread, reopens it (`woke`). The watcher does not see a settled
  entry, so a `woke` shows at the next reconcile.

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
