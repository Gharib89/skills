# The status block

## Contents

- [Every wake](#every-wake)
- [A reviewer usage limit](#a-reviewer-usage-limit)
- [A need](#a-need)
- [A ruling](#a-ruling)
- [The digest](#the-digest)

`scripts/` is under this skill's base directory. Reconcile and pulse print the
block for you, as `status` in their answer (`status.sh --help` lists its
fields); never compose it or rewrite it. Pass them `--instance <id>` with this
thread's provider instance, read once per session from `t3 thread show
$T3CODE_THREAD_ID --json` (`.thread.providerInstanceId`); without it the block
has no `Super agent on` line. The rows are `Needs you`, `Merged`, `Running`,
`Waiting` and `Reviewer limit`, one line each, `Needs you` first; each ticket is
a link, and a `Running` ticket names the provider instance it launched on. A
`task` entry (a thread that is no ticket's) reads `task:<slug> (task)`, and an
adopted entry of either kind adds `(adopted)`. A posted block ends with one
`Quota <instance>` line per provider instance, its weekly and 5 hour remaining
or `unknown`, then a `Super agent on <instance>` line: the instance this thread
runs on.

## Every wake

Reconcile (or pulse) with `--quota <file> --instance <id>`, `<file>` the
latest saved quota read (Routing: `quota.sh --fleet <fleet> --save <file>`) and
`<id>` this thread's provider instance. `launch.sh record` answers a `status` of
its own, from its baseline reconcile: post and push it the same way. Every
`status` answer:

- `block` holds only the rows that changed since the last posted block, a row
  that emptied reading `<row>: none`, and `Merged` lists only the merges since
  that block. Post it as printed, with no push. Empty: post nothing, no prose
  either. A merge, a launch or a change to the waiting list reaches the owner
  this way.
- `unpushed` holds a need, whatever `block` says: that need is new, and it is
  the only thing that sends a push, bar the
  [daily handover](../SKILL.md#daily-handover)'s pin request. Send one push
  notification (the PushNotification tool) naming the run and the one action,
  then run `ledger.sh --ledger <ledger> pushed <key>`. Until then every
  reconcile lists it again. A need you record after this wake's reconcile is
  pushed and marked the same way at once; its row reaches the next block.
- A need that asks the owner to pick (approve or deny a held call, a scope
  fork) goes out as chat text after the block: the question, the options
  numbered with your recommendation first and marked, and its push. The owner
  answers in chat. Never open a question dialog: it blocks the loop until
  answered.
- A `status` holding only `error` built no block: act on the rest of the
  answer as usual, and tell the owner that error in chat.

## A reviewer usage limit

A hosted reviewer that answers a review request with a usage-limit notice is a
fact to record, not a hold: the run still sends its one request (the notice
carries no reset time, so the request is the only probe), and merges on the
fallback reviewer alone. When a run's merge summary, or a PR thread you read,
shows the notice, run `ledger.sh --ledger <ledger> limit <owner/name> --reviewer
<name>`; the first notice's time stays, and `Reviewer limit` then says that
repo's batch is merging on the fallback reviewer only. Clear it with `ledger.sh
--ledger <ledger> unlimit <owner/name>` when a later run records that reviewer
as landed, or the owner says it is back.

## A need

Record one when you escalate: `ledger.sh --ledger <ledger> need <key> --action
<text> --reason <word>`, `<key>` the entry (or the waiting ticket), `<text>` the
one action and `<word>` the `escalate` row's `reason`, or for a need no row
raised a word naming its cause (`verify`, `merge-gate`, `cleanup`). A need
with no reason silences every later `escalate` row of its entry until
`unneed`.
Clear it with `ledger.sh --ledger <ledger> unneed <key>` once the owner has
answered, its ticket settles, or its stall resets, since nothing else clears
one. A `closed` ticket's need stays until the owner answers. Repeating `need`
with the same action keeps its time and its push, so a re-escalation never
pushes twice.

## A ruling

Record the owner's answer with `scripts/ledger.sh --ledger <ledger> ruling
<text> --allow <call>`, which dates it. Pass `--allow` only when the answer lets
that call run unheld; when a thread later holds on it, the
[step-in](step-ins.md#the-step-ins) relaying the owner's answer cites it (a
deny is a ruling with no `--allow`). No ruling rides on a launch message: one
that changes how ship runs belongs in the repo's ship profile. A ruling of your
own on a merge-gate hold (`merge_gate_ruler: super-agent`) is recorded the same
way, then reported in the next block. A gate-hold ruling that holds for one
repo's later holds too adds `--repo <owner/name>`, and `ledger.sh --ledger
<ledger> scoped` lists it with its `repo` for the
[gate-hold step-in](step-ins.md#the-step-ins).

A ruling lapses 7 days after its date: `list`, `allowed` and `scoped` leave it
out from then on. When the owner says one should last, pin it with
`ledger.sh --ledger <ledger> pin <date> <text>`, its date and exact text as
`list` shows them. A preference a script reads lives where the script reads it:
a per-repo cap, a reviewer order or the work week in the fleet file or the
repo's ship profile, and a gate-hold ruling that holds for good in the fleet
file's standing waivers.

### The one-time rulings migration

Run this once, while the ledger has no `rulings_migrated` field
(`jq .rulings_migrated <ledger>` prints `null`) and holds a ruling written
before expiries (`jq '[.rulings[] | select(.expires == null)] | length'
<ledger>` prints more than 0); the migration sets that field, and from then on
skip this section.

1. Read every ruling, lapsed or not:
   `SA_NOW=<epoch of the oldest ruling's date at 00:00 UTC> ledger.sh --ledger
   <ledger> list`. Draft one row per ruling as `{date, text, mark, to}`:
   `mark` is `pin`, `lapse` or `move`, and a move's `to` names its
   destination.
2. Propose a mark for each: a preference a script reads moves to its fleet key
   or ship profile line, a `--repo` gate-hold ruling that holds for good moves
   to the fleet file's standing waivers, and any other ruling is pinned when it
   still holds and lapses otherwise.
3. Put the list on a page for the owner (an artifact, the rows grouped by mark
   with your reason for each), and post its link with a push. Wait for the
   owner to approve it or edit it; a row they strike is left unmarked, which
   lapses, unless its ruling already has its own `expires`, which it keeps.
4. Write each `move` into its destination first (the fleet key as
   [setup.md](setup.md) edits the fleet file, a profile line through that
   repo's own PR), then save the approved rows as a JSON array and run
   `ledger.sh --ledger <ledger> migrate-rulings <list.json>`. It refuses two
   things: a row whose date and text match no ruling (fix the row from `list`
   and rerun) and any run after the first. Send the owner its `pinned`,
   `lapsed` and `moved` lists in a push: the status block does not carry them.

## The digest

`status.sh --ledger <ledger> --digest` prints every row whatever changed, and
counts every `Merged` ticket as listed, as any posted block does, so the next
block leaves them out.
Run it on the owner's "status", at the morning report and on the wake where
`ledger.sh list` shows `waiting` empty after the last block's `Waiting` row.
Give detail about one ticket only when the owner asks about it.
