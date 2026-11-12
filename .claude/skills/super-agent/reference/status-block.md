# The status block

## Contents

- [Every wake](#every-wake)
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
<text>`, `<key>` the entry (or the waiting ticket) and `<text>` the one action.
Clear it with `ledger.sh --ledger <ledger> unneed <key>` once the owner has
answered, its ticket settles, or its stall resets, since nothing else clears
one. A `closed` ticket's need stays until the owner answers. Repeating `need`
with the same action keeps its time and its push, so a re-escalation never
pushes twice.

## A ruling

Record the owner's answer with `scripts/ledger.sh --ledger <ledger> ruling
<text> --allow <call>`, which dates it. Pass `--allow` only when the answer lets
that call run unheld in later briefs (a deny is a ruling with no `--allow`), and
`--brief` when later briefs must carry the ruling, with `--repo` or `--machine`
to limit it. A standing line for one repo or machine belongs in the fleet file
([setup](setup.md#fleet-brief-lines)). A ruling of your own on a merge-gate hold
(`merge_gate_ruler: super-agent`) is recorded the same way, then reported in the
next block.

## The digest

`status.sh --ledger <ledger> --digest` prints the whole block whatever changed,
and counts every `Merged` ticket as listed, so the next block leaves them out.
Run it on the owner's "status", at the morning report and on the wake where
`ledger.sh list` shows `waiting` empty after the last block's `Waiting` row.
Give detail about one ticket only when the owner asks about it.
