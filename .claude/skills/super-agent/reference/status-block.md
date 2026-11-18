# The status block

## Contents

- [Every wake](#every-wake)
- [A reviewer usage limit](#a-reviewer-usage-limit)
- [A need](#a-need)
- [A ruling](#a-ruling)
- [The digest](#the-digest)

`scripts/` is under this skill's base directory. `status.sh --help` lists its
fields. Pass `--instance <id>` with this thread's provider instance, read once
per session from `t3 thread show $T3CODE_THREAD_ID --json`
(`.thread.providerInstanceId`); without it the block has no `Super agent on`
line. The block is rows `Needs you`, `Merged`, `Running`, `Waiting` and
`Reviewer limit`, one line each, an empty row left out, `Needs you` first; each
ticket is a link, and a `Running` ticket names the provider instance it
launched on. A `task` entry (a thread that is no ticket's) reads
`task:<slug> (task)`, and an adopted entry of either kind adds `(adopted)`. A
posted block ends with one `Quota <instance>` line per provider
instance, its weekly and 5 hour remaining or `unknown`, then a `Super agent on
<instance>` line: the instance this thread runs on.

## Every wake

After `reconcile.sh`, run `scripts/status.sh --ledger <ledger> --quota <file>
--instance <id>`,
`<file>` the wake's saved quota read (Routing; read it with `quota.sh --fleet
<fleet> --save <file> --wake <id>` if no launch did):

- `block` empty: post nothing, no prose either. A block is empty when no row
  changed (`changed` false) and no digest was asked.
- `block` set: post it as printed, with no push. A merge, a launch or a change
  to the waiting list reaches the owner this way.
- `unpushed` holds a need, whatever `block` says: that need is new, and it is
  the only thing that sends a push. Send one push notification (the
  PushNotification tool) naming the run and the one action, then run
  `ledger.sh --ledger <ledger> pushed <key>`.

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
out from then on (ADR 0021). When the owner says one should last, pin it with
`ledger.sh --ledger <ledger> pin <date> <text>`, its date and exact text as
`list` shows them. A preference a script can read does not stay a ruling: a
per-repo cap, a reviewer order or the work week goes to the fleet file, and a
gate-hold ruling that holds for good goes to the fleet file's standing waivers.

### The one-time rulings migration

The rulings recorded before lapses existed are sorted once, by the owner:

1. Draft the list from `ledger.sh --ledger <ledger> list`, run with `SA_NOW` set
   to the epoch of the oldest ruling's date so none reads as lapsed: one row per
   ruling, `{date, text, mark, to}`, `mark` being `pin`, `lapse` or `move`, and
   `to`, for a move, the fleet key or ship profile line it moves to. Propose a
   mark for each by the kind ADR 0021 gives it: an unscoped one lapses or is
   pinned, a `--repo` one lapses or moves to the fleet file's standing waivers,
   an `--allow` one lapses or is pinned.
2. Put the list on a page for the owner (an artifact, the rows grouped by mark
   with your reason for each), and post its link with a push. Wait for the
   owner to approve it or edit it; a row they strike is left unmarked, which
   lapses.
3. Write each `move` into its destination first (the fleet key as
   [setup.md](setup.md) edits the fleet file, a profile line through that
   repo's own PR), then save the
   approved rows as a JSON array and run `ledger.sh --ledger <ledger>
   migrate-rulings <list.json>`. It refuses a row naming a ruling the ledger
   lacks and a second run; a ruling the list leaves out lapses. Report its
   `pinned`, `lapsed` and `moved` in the next status block.

## The digest

`status.sh --ledger <ledger> --digest` prints the whole block whatever changed,
and counts every `Merged` ticket as listed, so the next block leaves them out.
Run it on the owner's "status", at the morning report and on the wake where
`ledger.sh list` shows `waiting` empty after the last block's `Waiting` row.
Give detail about one ticket only when the owner asks about it.
