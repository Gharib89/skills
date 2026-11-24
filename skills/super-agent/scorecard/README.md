# Scorecard

`scripts/scorecard.sh` counts one row a day from the ledger and its archive, the
guard and timer logs, and the super agent's own transcript; its header gives the
usage and output. `scorecard.jsonl`, beside the ledger, holds the rows. The
daily handover appends the previous day's row and, at the first handover of a
week, runs the weekly review, whose rows join the bearings file's Needs you.

## What a row counts

- **Workload**: `open` is every entry (ledger and archive) launched before the
  day ended and not settled before it began; `settled` the entries settled that
  day. The per-open numbers divide by `open`.
- **Message**: one non-empty text block of an assistant entry, timestamped that
  day. `over_1500` counts those longer than 1,500 characters; `median_chars` is
  their median length, the two middle lengths averaged when the count is even.
- **Nothing changed**: a message matching any pattern in
  [nothing-changed.txt](nothing-changed.txt), case-insensitive.
- **Wake**: a turn start, a user entry that is no tool result and no harness
  boilerplate (a skill load, a compaction summary, a slash command's echo),
  running to the next one. A wake that made no API call is not counted. Its
  cause comes from its text: `watcher`, `backstop`, `owner`, `compaction
  resume`, `other background`, `other scheduled`, `restart or harness` or
  `other`.
- **Changing call**: a tool call that writes state: a `ledger.sh` write, a
  launch, claim, merge, cleanup, reply, intake or handover script, a `gh`
  issue or PR write, a `git` commit, push, merge or worktree change, a T3
  thread send, launch or interrupt, a schedule change, `Write`, `Edit`,
  `AskUserQuestion` or `PushNotification` (the full lists are `changing_bash`
  and `changing_tools` in the script). A wake with none **changed nothing**.
- **Tokens**: input, cache write, cache read and output, counted once per API
  message id. `weighted` is input + 2 x cache write + 0.1 x cache read + 5 x
  output; `nothing_changed_share` is the weighted share spent in wakes that
  changed nothing.
- **Needs**: `recorded` counts `ledger.sh need` calls, `alerted` the
  `ledger.sh pushed` marks, `alerted_twice` the needs marked pushed more than
  once. They come from the transcript, since `unneed` removes a need from the
  ledger.
- **Questions**: owner wakes whose text holds a `?`; `with_write` those whose
  wake made a changing call other than a reply or hand-off (`AskUserQuestion`,
  `PushNotification`, `Agent`, `Artifact`).

## Logs

Each guard writes `<name>-guard.jsonl` beside the ledger, one JSON line per
event, `{at, event: "block" | "pass"}`; the wake timer writes
`wake-timer.jsonl`, `{at, event: "outage", minutes}`. A log not written yet is
`null` in the row, never an error.

## Targets

[targets.json](targets.json) maps a dotted path into the row to its `max`. A
target still tagged with the `slice` that owns it is inert: that slice drops
the tag when it lands, so the review never raises a row for work not shipped.
The weekly review raises one row per live target a day of the week went over,
and one per guard whose log covers the four weeks ending with that week and
that blocked nothing in them. A number with no target never raises one.

[baseline.md](baseline.md) holds the rows recounted for 6 to 19 November 2026.
