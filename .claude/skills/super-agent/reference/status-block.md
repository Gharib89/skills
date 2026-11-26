# The status block

## Contents

- [Every wake](#every-wake)
- [A reviewer usage limit](#a-reviewer-usage-limit)
- [A need](#a-need)
- [An acknowledge mark](#an-acknowledge-mark)
- [A ruling](#a-ruling)
- [The digest](#the-digest)

`scripts/` is under this skill's base directory. Reconcile and pulse print the
block for you, as `status` in their answer (`status.sh --help` lists its
fields); never compose it or rewrite it. Pass them `--instance <id>` with this
thread's provider instance, read once per session from `t3 thread show
$T3CODE_THREAD_ID --json` (`.thread.providerInstanceId`); without it the block
has no `Super agent on` line. The block opens with the **needs-you message**,
every open [need](#a-need) printed in full, then after a blank line the rows
`Merged`, `Running`, `Yours`, `Waiting` and `Reviewer limit`, one line each;
each ticket is a link, and a `Running` ticket names the provider instance it
launched on and ends `(you spoke last)` when the owner's message is the newest
from outside its thread. `Yours` lists the entries the owner took ("I'll take"),
each with its pull request's state and how long it has been the owner's. A
`task` entry (a thread that is no ticket's) reads `task:<slug> (task)`, and an
adopted entry of either kind adds `(adopted)`. A posted block ends with one
`Quota <instance>` line per provider instance, its weekly and 5 hour remaining
or `unknown`, then a `Super agent on <instance>` line: the instance this thread
runs on.

## Every wake

Reconcile (or pulse) with `--fleet <fleet> --quota <file> --instance <id>`
(the fleet file's `work_week` sets the reminder clock), `<file>` the
latest saved quota read (Routing: `quota.sh --fleet <fleet> --save <file> --wake
<wake-id>`) and `<id>` this thread's provider instance. `launch.sh record`
answers a `status` of its own, from its baseline reconcile: post it the same
way. Every `status` answer:

- `block` holds the needs-you message when the needs changed or one is raised,
  then only the rows that changed since the last posted block, a row that
  emptied reading `<row>: none` (needs that emptied, `Nothing needs you now.`),
  and `Merged` lists only the merges since that block. Post it as printed, in
  chat. Empty: post nothing, no prose either. A merge, a launch, a change to the
  waiting list and every need reach the owner this way.
- `raised` lists the needs this block alerts: a need not alerted before, and a
  blocking need's one reminder. Nothing to do with it; the block carries them.
  A need you record after this wake's reconcile is in no block yet: run
  `status.sh --ledger <ledger> --fleet <fleet> --quota <file> --instance <id>`
  and post its `block` at once.
- The owner answers in chat, `88 1` (ticket and option) or a bare `1` while one
  need with options is open: `ledger.sh --ledger <ledger> answer '<reply>'`
  names the need and the option, or exits 1 when the reply names none or
  several. Never open a question dialog: it blocks the loop until answered.
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

Record one when you escalate:

```sh
ledger.sh --ledger <ledger> need <key> --action <question> --reason <word> \
  --why <clause> --option <option> --option <option>...
```

The question reads `<verb> <ticket> <detail>`, and an option
`<label>: <consequence>` or a bare `<label>`.

`<key>` is the entry (or the waiting ticket); the action is the question without
its `?`, its second word the ticket (`name#n`, `owner/name#n` or `task:slug`),
the verb and ticket within its first 30 characters and the whole within 72.
`<word>` is the `escalate` row's `reason`, or for a need no row raised a word
naming its cause (`verify`, `merge-gate`, `cleanup`). Give 2 to 4 options, the
recommended one first, each label at most 5 words, the label ending at the first
`: `; a held call the owner answers in its own thread takes
`--answer-in <thread link>` and no options, your recommendation in `--why`.
`ledger need` refuses a need the message could not print, and a reason word it
does not know: its refusal lists the words.

The reason word sets the need's class. A **blocking need** is one whose thread
or the queue is stopped until the owner acts (`permission-hold`, `merge-gate`,
`scope`, `stall-cap`, `fault`, `no-instance`, `no-owner-skill`, `no-project`,
`stale-ship`, `route-ask`, `owner-steered`, `triage`); it prints bold, before
the offers. An **offer** is one nothing waits on (`daily-offer`, `unqueued`,
`parents-done`, `stale-skill`, `pr-closed`, `issue-closed`, `ask-first`,
`owner-run`, `verify`, `cleanup`); it prints behind `Offer:`. Each need prints
at most 6 lines, its options numbered from 1.

The block that first prints a need sets its alert mark. A blocking need still
open 4 working hours later (hours on the fleet file's `work_week` days) is
raised once more, and never again. Repeating `need` with the same action keeps
its time and both marks, whatever its reason word, so a re-escalation is never
raised twice. Each alert and reminder is logged in `needs-alerts.jsonl` beside
the ledger, which the scorecard counts. A need 0.46.0 recorded and pushed
counts as alerted at its `since`; it prints as its ticket's link and its action,
so record it again with `--why` and options: on the same key it keeps its marks,
whatever the new action.

Clear it with `ledger.sh --ledger <ledger> unneed <key>` once the owner has
answered, its ticket settles, or its stall resets, since nothing else clears
one. A `closed` ticket's need stays until the owner answers.

## An acknowledge mark

An `escalate` row that needs nothing of the owner yet (a stall you are already
handling, a fault you will retry) takes an **acknowledge mark**, not a need:
`ledger.sh --ledger <ledger> ack <key> --reason <the row's reason>`. It hides
that row and adds nothing to the block. It lapses once the entry's stage
changes, so the row prints again if the cause comes back.

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
   with your reason for each), and post its link in chat. Wait for the
   owner to approve it or edit it; a row they strike is left unmarked, which
   lapses, unless its ruling already has its own `expires`, which it keeps.
4. Write each `move` into its destination first (the fleet key as
   [setup.md](setup.md) edits the fleet file, a profile line through that
   repo's own PR), then save the approved rows as a JSON array and run
   `ledger.sh --ledger <ledger> migrate-rulings <list.json>`. It refuses two
   things: a row whose date and text match no ruling (fix the row from `list`
   and rerun) and any run after the first. Post the owner its `pinned`,
   `lapsed` and `moved` lists in chat: the status block does not carry them.

## The digest

`status.sh --ledger <ledger> --digest` prints every row whatever changed, and
counts every `Merged` ticket as listed, as any posted block does, so the next
block leaves them out.
Run it on the owner's "status", at the morning report and on the wake where
`ledger.sh list` shows `waiting` empty after the last block's `Waiting` row.
Give detail about one ticket only when the owner asks about it.
