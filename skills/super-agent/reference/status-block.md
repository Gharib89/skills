# The status block

## Contents

- [Every wake](#every-wake)
- [A need](#a-need)
- [The digest](#the-digest)

`scripts/` is under this skill's base directory. `status.sh --help` lists its
fields. The block is rows `Needs you`, `Merged`, `Running` and `Waiting`, one
line each, an empty row left out, `Needs you` first; each ticket is a link.

## Every wake

After `reconcile.sh`, run `scripts/status.sh --ledger <ledger>`:

- `block` empty: post nothing, no prose either. A block is empty when no row
  changed (`changed` false) and no digest was asked.
- `block` set: post it as printed, with no push. A merge, a launch or a change
  to the waiting list reaches the owner this way.
- `unpushed` holds a need, whatever `block` says: that need is new, and it is
  the only thing that sends a push. Send one push notification (the
  PushNotification tool) naming the run and the one action, then run
  `ledger.sh --ledger <ledger> pushed <key>`.

## A need

Record one when you escalate: `ledger.sh --ledger <ledger> need <key> --action
<text>`, `<key>` the entry (or the waiting ticket) and `<text>` the one action.
Clear it with `ledger.sh --ledger <ledger> unneed <key>` once the owner has
answered, its ticket settles, or its stall resets, since nothing else clears
one. A `closed` ticket's need stays until the owner answers. Repeating `need`
with the same action keeps its time and its push, so a re-escalation never
pushes twice.

## The digest

`status.sh --ledger <ledger> --digest` prints the whole block whatever changed,
and counts every `Merged` ticket as listed, so the next block leaves them out.
Run it on the owner's "status", at the morning report and on the wake where
`ledger.sh list` shows `waiting` empty after the last block's `Waiting` row.
Give detail about one ticket only when the owner asks about it.
