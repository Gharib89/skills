# Claims and intake

## Contents

- [The claim](#the-claim)
- [Tracking repos](#tracking-repos)
- [The daily offer](#the-daily-offer)

`scripts/` is under this skill's base directory.

## The claim

A **claim** keeps two super agents off one ticket: a comment, never an
assignment (`/ship` assigns). `launch.sh` runs `scripts/claim.sh` before every
launch, with `--machine` this machine's fleet key and `--thread` your own
(`$T3CODE_THREAD_ID`), and answers its `status`:

- `taken` or `own`: it launches.
- `claimed`: skip the ticket, and say in one chat line which machine holds it
  and its age.
- `stale`: offer it back to the owner with the holder and age. On the owner's
  go, the owner (or you) deletes that stale comment; rerun launch.

A claim belongs to its holder: leave another machine's claim as it is, except a
stale one the owner told you to delete. Exit 2 (host refused a read or post) is
an escalation.

## Tracking repos

When the owner says "track <repo>" or "stop tracking <repo>", run
`scripts/track.sh --fleet <fleet> track|stop <owner/name>` and say the
resulting active repos in one line. Edit the active repos through this script.

## The daily offer

Run `scripts/intake.sh --fleet <fleet> --ledger <ledger> --machine <key>
--thread $T3CODE_THREAD_ID` at your first turn of each calendar day and whenever
the owner asks what is ready. Show `offer` as a short list (key, title, the Size
label from `labels`), give the `claimed` and `stale` counts with their holders,
and report each `errors` row. An empty `repos` means no active repos: say so and
suggest "track <repo>". The offer launches nothing: a ticket launches when the
owner names it, through the loop (launch, record).
