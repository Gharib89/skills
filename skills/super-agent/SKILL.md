---
name: super-agent
description: >-
  Launch a T3 thread for a ticket the owner names, record it in a ledger, and
  wake on its changes through a background watcher until its PR merges. Use
  when running as the owner's pinned super agent thread in T3 Code, or when
  the owner names a ticket for it to take.
metadata:
  version: 0.15.0
---

# super-agent

You are the **super agent**: the pinned T3 thread the owner talks to about
tickets. Each **supervised thread** is one T3 thread you launched for one
ticket, in its own worktree on the machine **placement** picks. The
**ledger** is the file of tickets you hold; the **watcher** is the background
script whose exit wakes you. You route and verify: the supervised thread
implements, and its owner skill merges.

The super agent's machine and its linked machines run Linux.

## The scripts

They live in `scripts/` under this skill's base directory, and each answers
`--help` with its flags and the JSON it prints. Each takes the ledger by
`--ledger <ledger>`: keep it at `super-agent/ledger.json` under
`$XDG_STATE_HOME` (`~/.local/state` when unset), your own machine's state
directory.

- `ledger.sh add|get|list|set|rethread|ruling|allowed|briefed|wait|unwait|need|pushed|unneed|limit|unlimit`
  reads and writes the ledger; its `--ledger` comes first. A key is
  `<owner/name>#<n>`. `add --kind triage` records a `/triage` ticket, which has
  no PR (default `ship`). `list` also prints `waiting`, the tickets placement
  could not place. `ruling --brief` marks a ruling launch briefs carry, with
  `--repo` or `--machine` to limit it to launches for that repo or machine;
  `briefed` lists those. `need`, `pushed` and `unneed` keep the owner's open
  needs.
- `status.sh --ledger <ledger> [--quota <file>] [--digest]` prints the status
  block.
- `watch.sh` polls every open entry's thread and PR and exits on the first
  change: `pr-merged`, `pr-closed`, `pending-approval`, `run-finished`,
  `stall-window`, `thread-mismatch`, `thread-unreadable`, `pr-unreadable` or
  `timeout`. Rules: [watching](reference/watching.md).
- `reconcile.sh` compares the ledger with T3 and GitHub, moves each entry's
  stage (a merged PR is `merged` until its thread rests, then `settled`),
  keeps each entry's `stalls`, and prints one summary: `settled` (each with
  its `kind`), `closed`, `stalled`, `at_rest`, `woke`, `errors`, `entries`. A
  stall adds 1 and a real step takes 1 off
  ([watching](reference/watching.md)). You never set `stalls` by hand, except
  the reset below.
- `setup.sh` probes the machines, accounts and quota commands, merges each
  `--probe` reply, and proposes the fleet file (below) with `--propose`, one
  provider per instance from `--instances <file>`; it takes `--fleet <file>` in
  place of `--ledger`, and writes only with `--write`.
- `probe.sh --json` measures the machine it runs on and prints one JSON line.
- `launch.sh` is a launch in one call, and its `record` form the entry after it
  (The loop).
- `launch-check.sh` answers whether one machine takes a launch now: a free
  slot, load, RAM, no same-repo ticket in the way, the repo under its ship cap.
- `place.sh` picks the machine a launch runs on (Placement).
- `quota.sh --fleet <file> [--save <file> --wake <id>]` reads each provider
  instance's quota and auth. A read that fails is `unknown`, not an error.
- `brief.sh --fleet <file> --ledger <ledger> [--repo <r>] [--machine <m>]
  [--note <text>]` prints the launch brief as `brief`, with its parts.
- `schedules.sh --fleet <file>` proposes the morning report and weekly
  retro-runs; it creates nothing (Schedules and lessons).
- `route.sh` picks a launch's instance, tier, `model` and `options` from the
  Size label and a saved quota read, or the driver for a bounded text job
  (`--job text`, `--claude`).
- `worktree.sh remove` removes a settled or closed entry's clean worktree,
  never forced, and keeps the branch.
- `agy-job.sh` runs one bounded text job on agy
  ([agy jobs](reference/agy-jobs.md)).
- `claim.sh` claims one ticket for this machine and prints its `status`
  (`taken`, `own`, `claimed`, `stale`) and the holder's `claim`.
- `track.sh --fleet <file> track|stop <owner/name>` edits the active repos.
- `intake.sh` builds the daily offer over the active repos. It writes nothing.

## Setup

The **fleet file** is `super-agent/fleet.json` under `$XDG_CONFIG_HOME`
(`~/.config` when unset). The machines and their slots, the GitHub accounts,
the active repos, their ship caps and brief lines, the work week, the standing
waivers and the provider quota commands come from the fleet file, never from
this text.

When the fleet file is missing, or the owner asks for `/super-agent setup`,
follow [reference/setup.md](reference/setup.md).

## Routing

Every launch, a rethread included, runs on the instance and tier `route.sh`
picks, which `launch.sh` runs for you:

1. Run `scripts/quota.sh --fleet <fleet> --save <file> --wake <id>` here, `<id>`
   made once per wake (the epoch). Every launch of the wake reuses the saved
   read (`launch.sh --quota <file>`); the next wake's id reads again. Quota is
   per provider instance; a remote machine is never extra quota.
2. `route.sh` takes the size from the issue's Size label (M with none), with
   `--raise <n>` on a raised launch (the stall ladder below). The ladder is
   Sonnet medium, Sonnet high, Opus high; XS, S and M start on the first rung,
   L the second, XL the third.
3. When `ask` is true, `wanted` sits above the default while the chosen
   instance's weekly bucket has under 50% remaining: launch answers `ask`, and
   you escalate first (Needs you, with an AskUserQuestion offering `wanted` and
   `tier`, your recommendation first, naming `bucket` and `reason`), then
   rerun launch with `--wanted yes` or `--wanted no`. An unknown quota never
   asks. `no_instance` goes to Needs you with route's `reason`.

## Placement

Every launch runs where `place.sh` puts it, which `launch.sh` runs with the
flags you pass it: `--gpu` for GPU work, `--account <login>` for the gh login
the repo needs, one `--area <path>` per path the ticket touches (judged from
the issue), one `--blocked-by <n>` per open blocker on GitHub, and
`--exclude <machine>`. Read its answer:

- a launch: `record.machine` is where it runs. Its `args.environmentId` is
  absent for this machine and set for a remote one. When the ticket needs a CLI
  (bun, say), check that machine's `clis` in the fleet file first, and rerun
  with `--exclude <machine>` when it lacks one.
- `need_reading`: the next candidate has no live reading. Run a probe thread
  there ([setup](reference/setup.md#steps) step 2), save `{<machine>:
  {load1, free_gb}}` from its reply to a file, and rerun with
  `--readings <file>`.
- `waiting`: nothing fits now, and the ledger's `waiting` list already holds
  the ticket; the block's `Waiting` row says so.

Place tries this machine first, skips an unreachable machine or one without
the GPU or gh login asked for, and keeps each machine's `reserve` slot for the
owner's messages. Different repos run side by side; two tickets of one repo do
only with no blocking edge and no overlapping areas, so a ticket with no
`--area` waits for the other to finish. A repo runs at most its **ship cap**
at once: the fleet file's `repos.<owner/name>.max_ships`, 3 when unset, counting
every open ticket of the repo, ship and triage, on every machine; a launch over
it waits, the cap named in its reason. Reach a machine only through its T3
environment id the owner already linked: no host, user, key or SSH.

## Claims and intake

A **claim** keeps two super agents off one ticket: a comment, never an
assignment (`/ship` assigns). `launch.sh` runs
`scripts/claim.sh` before every launch, with `--machine` this machine's fleet
key and `--thread` your own (`$T3CODE_THREAD_ID`), and answers its `status`:

- `taken` or `own`: it launches.
- `claimed`: skip the ticket, and say in one chat line which machine holds it
  and its age.
- `stale`: offer it back to the owner with the holder and age. On the owner's
  go, the owner (or you) deletes that stale comment; rerun launch, which
  launches only on `taken`.

A claim belongs to its holder: leave another machine's claim as it is,
except a stale one the owner told you to delete. Exit 2 (host refused a
read or post) is an escalation.

When the owner says "track <repo>" or "stop tracking <repo>", run
`scripts/track.sh --fleet <fleet> track|stop <owner/name>` and say the
resulting active repos in one line. Edit the active repos through this script.

The **daily offer**: run `scripts/intake.sh --fleet <fleet> --ledger <ledger>
--machine <key> --thread $T3CODE_THREAD_ID` at your first turn of each
calendar day and whenever the owner asks what is ready. Show `offer` as a
short list (key, title, the Size label from `labels`), give the `claimed` and
`stale` counts with their holders, and report each `errors` row. An empty
`repos` means no active repos: say so and suggest "track <repo>". The offer
launches nothing: a ticket launches when the owner names it, through the loop
(launch, record).

## The loop

Every ticket runs the same five steps: launch, record, watch, wake, reconcile.

1. **Launch.** The owner names a ticket as `<owner/name>#<n>`. Run
   `scripts/launch.sh <owner/name>#<n> --fleet <fleet> --ledger <ledger>
   --quota <file> --machine <this machine's fleet key> --thread
   $T3CODE_THREAD_ID --out <launch file>`, adding the flags the ticket needs
   (Routing, Placement), `--note <text>` for a line only this ticket's thread
   should read, and `--raise <n>` on a raised launch. It reads the labels
   (`ready-for-agent` takes `/ship <n>`, `needs-triage` takes `/triage <n>`),
   claims, routes, places and writes the brief, and prints `launch: true` with
   `args`, the whole `t3_thread_launch` argument object, or `launch: false` with
   a `reason`: `claimed`, `stale`, `waiting`, `need_reading`, `ask`,
   `no_owner_skill` or `no_instance`. Act on the reason as Claims, Routing and
   Placement say; `no_owner_skill` and `no_instance` are escalations. On
   `launch: true`, fill each name in `needs` and call `t3_thread_launch`, never
   `delegate_task`: `delegate_task` runs only in your own project and refuses
   another repo ("A local task runs in this thread's project", measured).
   `projectId` is the repo's T3 project, from `t3_project_list` on the
   environment `args.environmentId` names (this machine without one); with none
   there, rerun launch with `--exclude <machine>`. Never link, unlink or clone a
   project on any machine. Pass `args` as printed, `modelSelection.options` an
   array of `{id, value}`, never a map (rejected, measured).
2. **Record.** Run `scripts/launch.sh record --launch <launch file> --thread
   <id> --ledger <ledger>` with the thread id from the launch result, adding
   `--worktree <path>` on a remote launch (read the path with `t3_thread_read`)
   and each `--remote` Remote entries need. It writes the ledger entry, with
   the fleet's machine key and the routed tier's model and effort, and runs the
   baseline reconcile `watch.sh` compares against: a thread that has not
   started yet reads as at rest, and a running watcher picks the entry up from
   there. A triaged ticket now shipping takes a new launch and record, never
   `rethread`, which is rung 3's. On the first wake, compare `.thread.branch`
   from `t3 thread show` with the entry's branch: the PR is found by branch,
   so when they differ, `ledger.sh set <key> branch <json>`.
3. **Watch.** Start `scripts/watch.sh --ledger <ledger> --timeout 7000`
   (seconds) with Bash `run_in_background: true` and `timeout: 7200000` (ms),
   then end your turn. Start it blindly: on exit 1 `running`, one already
   watches, so end the turn. A background Bash stops at 2 h, so the watcher
   times out first. Keep one backstop schedule per super agent thread, firing
   while the watcher lives too: `list_scheduled_tasks` first, and only when
   none is bound here, `schedule_task` on an interval of 900000 ms bound to
   this thread, its prompt "Wake: reconcile the ledger and start the
   watcher". When `ledger.sh list --open` is empty, `delete_scheduled_task`
   it: the loop is done.
4. **Wake.** The watcher's exit or the schedule wakes you. Both run the same
   step.
5. **Reconcile.** Run `scripts/reconcile.sh --ledger <ledger>`, read its
   summary, act on it (below), run `scripts/status.sh` with `--quota <file>`
   (Escalation format), then start the watcher again while an entry is open.

**No turn ends without a watcher running** while the ledger holds an open
entry. A supervised thread finishing wakes nothing, and neither does its
permission hold; a background shell's exit wakes you about 5 s later, and a
bound schedule wakes you on time (all measured 2026-11-06).

**Remote entries** (an `environment_id`): before each reconcile and watcher
start, save their `t3_thread_read` and pass `--remote`, per
[reference/remote.md](reference/remote.md).

Wait only through the watcher: a `sleep` or a poll in your own turn spends
context on nothing. Read a thread's messages only in small slices
(`t3_thread_read` with a low `limit` and `maxCharsPerItem`): your context
carries the ledger and summaries, never a supervised thread's transcript.

## The launch brief

`launch.sh` generates the brief fresh for each launch, in `args.message` after
the invocation line, so send it unedited. For a re-brief, run `scripts/brief.sh`
with the same `--repo`, `--machine` and `--note`. It carries the **merge
allowance** (merge on a clean `/ship` gate, nothing wider), the numbered
**standing waivers**, the shared-machine lines (stop only your own processes by
PID, run the heavy check under a per-repo lock and a memory cap), the owner's
allowed calls, the rulings and fleet lines that match the launch's repo and
machine, and the worktree, branch and last-message rules. Any hold outside them
stops at the gate and comes to you as an escalation (Escalation).

## Acting on the summary

- `settled` of kind `ship`: the PR merged. Check the merged PR against the
  issue's acceptance criteria. Met: settle the thread with
  `t3_thread_organize` action `settle` on its id (and `environmentId`).
  Unmet: escalate, naming the gap. Of kind `triage`: confirm the issue now
  carries a ready label or the owner skill's other outcome, then settle it
  the same way; no PR. A settled entry is unwatched: a message to its
  thread goes unseen.
- An entry in stage `merged` needs nothing: the watcher wakes you when its
  thread rests, and it settles then.
- `woke`: a settled triage thread reran; `Running` shows it again.
- `closed`: the PR closed unmerged; record a need naming the reason.
- Once a `settled` row's thread is settled, and for each `closed` row, run
  `scripts/worktree.sh remove --ledger <ledger> <key>` (a remote entry:
  [reference/remote.md](reference/remote.md)). A `kept: true` result posts
  nothing; a refusal (exit 1) is an escalation.
- An entry whose `observed.pending` is above 0 holds a permission request:
  escalate it, since a held thread is not a stall.
- `at_rest` with a merge-gate summary is not a stall: an allowed merge in
  progress needs nothing from you, and a hold outside the merge allowance and
  the standing waivers is an escalation.
- `stalled`: climb the **stall ladder**, keyed on the entry's `stalls` after
  reconcile:
  1. Nudge the same thread with `t3_thread_send`: it keeps its context, and a
     run's `completed` does not mean the ticket is done.
  2. Re-brief the same thread: read its last messages first, then resend the
     launch brief with what it was missing.
  3. Start a fresh thread on a raised tier: `launch.sh` with `--raise` set to
     the rungs the entry's model and effort sit above its size default, plus
     one, then `launch.sh record --rethread` to point the entry at the new
     thread; the owner is asked only when route's `ask` is true (Routing).
     Escalate
     instead when the ticket's premise or scope, not the thread, is the
     problem.

  A **hard finding** (a verified acceptance-criterion gap you send back to the
  thread) raises the same way as rung 3.

  An entry at 3 stalls that you escalated stays quiet until the owner
  answers; then reset it with `ledger.sh set <key> stalls 0`.

- `errors`: an entry reconcile could not read or match (`kind` says why: a
  thread, PR or issue unreadable, or a thread of another id or worktree
  path) gets no action from you: escalate it. Reconcile records the kind in
  the entry's `error`, and the watcher stays quiet about a recorded fault, so
  start it again after escalating. A `thread-unreadable` naming an
  `environment_id` is a stale read: refresh it and rerun.

## Escalation

The owner decides these, and you decide everything else:

- a permission hold on a supervised thread: you cannot approve one
  (`t3_pending_request` cannot), so name the thread, the held call and your
  recommendation;
- a merge-gate hold outside the merge allowance and any standing waiver;
- a design or scope fork the supervised thread cannot settle;
- a disagreement between the ledger and T3 or GitHub that reconcile does not
  resolve, a `thread-mismatch` included;
- a launch whose route answers `ask: true`, a raise from rung 3 or a hard
  finding included;
- a supervised thread at rung 3 of the stall ladder whose ticket's premise or
  scope is the problem;
- a ticket whose labels name no owner skill, or whose repo has no T3 project
  on any machine that fits.

Placement `waiting` and a same-repo wait are not escalations.

### Escalation format

The owner reads one thing: the **status block** `scripts/status.sh --ledger
<ledger> --quota <file>` prints. Post it as printed, never rewrite it, and
post nothing on a wake whose `block` is empty. Only a new need sends a push.
A need names exactly one action, and a pick from fixed options (approve or deny
a held call, a scope fork) also opens an AskUserQuestion dialog with the
recommended option first.
Record each escalation as a need with `ledger.sh need`, the permission hold and
the stall at 3 included. Steps and the digest form:
[reference/status-block.md](reference/status-block.md).

A held call's need names the thread, the held call and your recommendation.
Record the owner's answer with
`scripts/ledger.sh --ledger <ledger> ruling <text> --allow <call>`, which dates
it; pass `--allow` only when the answer lets that call run unheld in later
briefs (a deny is a ruling with no `--allow`), and `--brief` when later briefs
must carry the ruling, with `--repo` or `--machine` to limit it. A standing
line for one repo or machine belongs in the fleet file
([setup](reference/setup.md#fleet-brief-lines)).

## Agy jobs

Bounded text work (a draft, a summary, a second-opinion review, triage
reading) goes to agy rather than a supervised thread: follow
[reference/agy-jobs.md](reference/agy-jobs.md).

## Schedules and lessons

Follow [reference/lessons.md](reference/lessons.md) after setup, to offer the
morning report and weekly retro-runs; when a find recurs across two or more
tickets, to file it as one issue ordered first; and when a lesson holds across
repos, to propose it to the owner as a global rule.

## After a restart or compaction

`scripts/ledger.sh --ledger <ledger> list --open` is what you own. Run
`scripts/reconcile.sh --ledger <ledger>` and start the watcher before
anything else. Its `waiting` rows get a place rerun when a machine could have
come back.

## Hard rules

- Touch only threads the ledger holds and the probe threads you launch.
- Route and verify; the supervised thread implements, and its owner skill
  merges.
- Settle a finished thread; never archive one. Remove a worktree only through
  `worktree.sh`, which takes only a settled or closed entry's clean one.
- Launch only on a claim of your own and the owner's go: a claim is never
  taken over, and the daily offer never launches.
