---
name: super-agent
description: >-
  Launch a T3 thread for a ticket the owner names, record it in a ledger, and
  wake on its changes through a background watcher until its PR merges. Use
  when running as the owner's pinned super agent thread in T3 Code, or when
  the owner names a ticket for it to take.
metadata:
  version: 0.6.0
---

# super-agent

You are the **super agent**: the pinned T3 thread the owner talks to about
tickets. Each **supervised thread** is one T3 thread you launched for one
ticket, in its own worktree on the machine **placement** picks. The
**ledger** is the file of tickets you hold; the **watcher** is the background
script whose exit wakes you. You route and verify: the supervised thread
implements, and its owner skill merges.

## The scripts

They live in `scripts/` under this skill's base directory, and each answers
`--help` with its flags and the JSON it prints. Each takes the ledger by
`--ledger <ledger>`: keep it at `super-agent/ledger.json` under
`$XDG_STATE_HOME` (`~/.local/state` when unset), your own machine's state
directory.

- `ledger.sh add|get|list|set|rethread|ruling|allowed|wait|unwait` reads and
  writes the ledger; its `--ledger` comes first. A key is `<owner/name>#<n>`.
  `add --kind triage` records a `/triage` ticket, which has no PR (default
  `ship`). `list` also prints `waiting`, the tickets placement could not place.
- `watch.sh` polls every open entry's thread and PR and exits on the first
  change: `pr-merged`, `pr-closed`, `pending-approval`, `run-finished`,
  `stall-window`, or `thread-mismatch`, `thread-unreadable`, `pr-unreadable`,
  or `timeout`. A finished run is reported only if still at rest `--recheck`
  seconds later (default 90): a run awaiting its own subagent restarts.
  `stall-window` is an entry at rest with no new run for `--stall-window`
  seconds (default 900). One watcher runs per ledger: a second start exits 1
  with `running`, the first left alone. It re-reads the ledger each poll, and
  skips an entry `reconcile` has not observed yet (`unobserved`).
- `reconcile.sh` compares the ledger with T3 and GitHub, moves each entry's
  stage (a merged PR is `merged` until its thread rests, then `settled`),
  keeps each entry's `stalls`, and prints one summary: `settled` (each with
  its `kind`), `closed`, `stalled`, `at_rest`, `errors`, `entries`. A stall (a
  completed run with no merged PR and no merge-gate summary, or a window
  passed with no new run) adds 1; a real step (a run ending in the merge-gate
  summary, or a PR opened) takes 1 off, never below 0. An entry at 3 stalls
  gains none.
  `stalled` holds one `{key, thread, stalls, reason}` per stall counted now.
  You never set `stalls` by hand, except the reset below.
- `setup.sh` probes this machine, its linked T3 environments, the GitHub
  accounts and each provider's quota command, merges each `--probe` reply,
  and proposes the fleet file (below) with `--propose`; it takes
  `--fleet <file>` in place of `--ledger`, and writes only with `--write`.
- `probe.sh --json` measures the machine it runs on (cores, RAM, `free_gb`,
  `load1`, GPU, `clis`, `gh_logins`) and prints one JSON line.
- `launch-check.sh` answers whether one machine takes a launch now: a free
  slot, load, RAM, and no open same-repo ticket in the way.
- `place.sh` picks the machine a launch runs on (Placement).
- `quota.sh` reads every fleet-file provider's quota through the quota command
  setup recorded, and prints each bucket's remaining fraction and reset. A read
  that fails is `unknown`, not an error. `--fleet <file>` is required.
- `brief.sh --fleet <file> --ledger <ledger>` prints `{brief, waivers,
  allowed}`: `brief` is the whole standing launch brief.
- `schedules.sh --fleet <file>` proposes the morning report and weekly
  retro-runs; it creates nothing (Schedules and lessons).
- `route.sh` picks a launch's model tier from the issue's Size label and a
  saved quota read (`--size`, `--raise`, `--quota <file>`), or the driver for a
  bounded text job (`--job text`, `--claude`).
- `agy-job.sh` runs one bounded text job on agy from a disposable scratch
  worktree of the repo, under a session-only allow list of harmless binaries,
  and prints its response as JSON.
- `claim.sh` claims one ticket for this machine and prints its `status`
  (`taken`, `own`, `claimed`, `stale`) and the holder's `claim` with `age_s`.
- `track.sh --fleet <file> track|stop <owner/name>` edits the active repos and
  prints the list as the file now holds it.
- `intake.sh` builds the daily offer: `offer`, `held`, `claimed`, `stale` and
  `errors` over the active repos. It writes nothing.

## Setup

The **fleet file** is `super-agent/fleet.json` under `$XDG_CONFIG_HOME`
(`~/.config` when unset). The machines and their slots, the GitHub accounts,
the active repos, the standing waivers and the provider quota commands come
from the fleet file, never from this text. The launch brief takes its standing
waivers from it, and any step that needs a machine, account, repo or quota
command reads it from the file. Setup runs on Linux only (it uses GNU `nproc`,
`free` and `timeout`).

When the fleet file is missing, or the owner asks for `/super-agent setup`,
follow [reference/setup.md](reference/setup.md).

## Routing

Every launch, a rethread included, runs on the tier `route.sh` picks:

1. Run `scripts/quota.sh --fleet <fleet>` here and save its stdout to a file.
   Read it fresh for each launch: buckets move between launches. Quota is per
   account, so every machine draws on the same buckets (measured: remote probes
   saw the local weekly bucket); a remote machine is never extra quota, and a
   probe never reads quota.
2. Run `scripts/route.sh --size <XS|S|M|L|XL> --quota <file>`, the size from
   the issue's Size label, with `--raise <n>` on a raised launch (the stall
   ladder below). The ladder is Sonnet low, Sonnet medium, Sonnet high, Opus
   high; XS and S start on the first rung, M the second, L the third, XL the
   fourth.
3. Launch `tier`. When `ask` is true, `wanted` sits above the default while
   Claude Code's weekly bucket has under 50% remaining: escalate first (Needs
   you, with an AskUserQuestion offering `wanted` and `tier`, your
   recommendation first, naming `bucket` and `reason`), then launch `wanted`
   on a yes and `tier` on a no. An unknown quota never asks: route returns the
   default tier.

## Placement

Every launch runs where `place.sh` puts it:

1. Run `scripts/place.sh --fleet <fleet> --ledger <ledger> --repo
   <owner/name> --number <n>`, with `--gpu` for GPU work, `--account <login>`
   for the gh login the repo needs, one `--area <path>` per path the ticket
   touches (judged from the issue), and one `--blocked-by <n>` per open
   blocker on GitHub.
2. Read its answer:
   - `placed`: launch on `placed.machine`. Its `environment_id` is null for
     this machine and set for a remote one. When the ticket needs a CLI (bun,
     say), check that machine's `clis` in the fleet file first, and rerun with
     `--exclude <machine>` when it lacks one.
   - `need_reading`: the next candidate has no live reading. Run a probe thread
     there ([setup](reference/setup.md#steps) step 2), save `{<machine>:
     {load1, free_gb}}` from its reply to a file, and rerun with
     `--readings <file>`.
   - `waiting`: nothing fits now, and the ledger's `waiting` list already holds
     the ticket. Say so in one chat line with its `reason`.

Place tries this machine first, skips an unreachable machine or one without
the GPU or gh login asked for, and keeps each machine's `reserve` slot for the
owner's messages. Different repos run side by side; two tickets of one repo do
only with no blocking edge and no overlapping areas, so a ticket with no
`--area` waits for the other to finish. Reach a machine only through its T3
environment id, and only one the owner already linked: the fleet file holds no
host, user or key, and you use no SSH.

## Claims and intake

A **claim** keeps two super agents off one ticket. Before every launch, run
`scripts/claim.sh --repo <owner/name> --number <n> --machine <this machine's
fleet key> --thread $T3CODE_THREAD_ID` (your own thread) and read `status`:

- `taken` or `own`: launch.
- `claimed`: skip the ticket, and say in one chat line which machine holds it
  and its age.
- `stale`: offer it back to the owner with the holder and age. On the owner's
  go, the owner (or you, at the owner's word) deletes that stale claim
  comment; then rerun `claim.sh` and launch only on `taken`.

A claim belongs to its holder: leave another machine's claim and its comment
as they are, except a stale one the owner told you to delete. Exit 2 (the
host refused a read or post) is an escalation.

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
(claim, route, place, launch).

## The loop

Every ticket runs the same five steps: launch, record, watch, wake, reconcile.

1. **Launch.** The owner names a ticket as `<owner/name>#<n>`. Read its labels
   with `gh issue view`, once for both reads: the owner-skill label and the
   Size label. `ready-for-agent` takes `/ship <n>`, `needs-triage` takes
   `/triage <n>`, anything else is an escalation (below). Claim it (Claims and
   intake), then pick the tier under Routing and the machine under Placement.
   Call
   `t3_thread_launch`, never `delegate_task`: `delegate_task` runs only in your
   own project and refuses another repo ("A local task runs in this thread's
   project", measured). Pass:
   - `environmentId`: `placed.environment_id`, on a remote launch only;
   - `projectId`: the repo's T3 project, from `t3_project_list` on that
     environment. With none there, rerun place with `--exclude <machine>`.
     Never link, unlink or clone a project on any machine;
   - `title`: `<repo>#<n> <slug>`, `<repo>` the repo's short name;
   - `workspaceStrategy`: `{type: "worktree", baseRef: <default branch>,
     branch: "<type>/<slug>-<n>", startFromOrigin: true}`, the branch named
     the way `/ship` names its branches;
   - `modelSelection`: `{instanceId, model, options}`, `instanceId` the
     provider instance as T3 names it (`claudeAgent`, say), then route's
     `{model, effort}` tier: `model` as is, and `effort` as the one entry of
     `options`, an array of `{id, value}`:
     `[{"id":"effort","value":"low"}]`. A `{model, options}` shape with a
     map is rejected (`Expected string at modelSelection.instanceId`,
     measured);
   - `message`: the owner-skill invocation on its first line, then `brief`
     verbatim (The launch brief).
2. **Record.** Read the thread's id and worktree path from the launch result,
   or from `t3 thread show <id> --json` (`.thread.worktreePath`). Run
   `scripts/ledger.sh --ledger <ledger> add --repo <owner/name>
   --number <n> --thread <id> --worktree <path> --branch <branch>`, with
   `--kind triage` for a `needs-triage` ticket, `--model` and `--effort` set to
   the tier launched, `--machine` the fleet
   key place printed (never `local` for a remote), and each `--area` passed to
   place, then run
   `scripts/reconcile.sh --ledger <ledger>` once and ignore its summary: it
   gives the entry the baseline `watch.sh` compares against, and a thread that
   has not started yet reads as at rest. A running watcher picks the entry up
   from there, after an `add` or a `rethread` alike. On the first wake, compare
   `.thread.branch` from `t3 thread show` with the entry's branch: the PR is
   found by branch, so when they differ, `ledger.sh set <key> branch <json>`.
3. **Watch.** Start `scripts/watch.sh --ledger <ledger> --timeout 7000`
   (seconds) with Bash `run_in_background: true` and `timeout: 7200000` (ms),
   then end your turn. Start it blindly: exit 1 with `running` means one
   already watches, so leave it and end the turn, and a backstop wake never
   stacks a second. A background Bash stops at 2 h, so the watcher times out
   first. Keep one backstop schedule per super agent thread, firing while the
   watcher lives too: `list_scheduled_tasks` first, and only when none is bound
   here, `schedule_task` on an interval of 900000 ms bound to this thread, its
   prompt "Wake: reconcile the ledger and start the watcher". When
   `ledger.sh list --open` is empty, `delete_scheduled_task` it: the loop is
   done.
4. **Wake.** The watcher's exit or the schedule wakes you. Both run the same
   step.
5. **Reconcile.** Run `scripts/reconcile.sh --ledger <ledger>`, read its
   summary, act on it (below), then start the watcher again while an entry is
   open.

**No turn ends without a watcher running** while the ledger holds an open
entry. A supervised thread finishing wakes nothing, and neither does its
permission hold; a background shell's exit wakes you about 5 s later, and a
bound schedule wakes you on time (all measured 2026-11-06). A turn that ends
without a watcher leaves every ticket silent until the backstop fires.

Wait only through the watcher: a `sleep` or a poll in your own turn spends
context on nothing. Read a thread's messages only in small slices
(`t3_thread_read` with a low `limit` and `maxCharsPerItem`): your context
carries the ledger and summaries, never a supervised thread's transcript.

## The launch brief

Run `scripts/brief.sh --fleet <fleet> --ledger <ledger>` fresh for each
launch, a re-brief included, and send its `brief` unedited, so the waivers and
rulings reach the thread word for word. It carries the **merge allowance**
(merge on a clean `/ship` gate, nothing wider), the **standing waivers**
numbered, the owner's allowed calls, and the worktree, branch and last-message
rules. Any hold outside them stops at the gate and comes to you as an
escalation (Escalation).

## Acting on the summary

- `settled` of kind `ship`: the PR merged. Check the merged PR against the
  issue's acceptance criteria. Met: settle the thread with
  `t3_thread_organize` action `settle` on its id. Unmet: escalate, naming the
  gap. Of kind `triage`: confirm the issue now carries a ready label or the
  owner skill's other outcome, then settle the thread; there is no PR. A
  settled entry is no longer watched, so a message to its thread goes unseen.
- An entry in stage `merged` needs nothing: the watcher wakes you when its
  thread rests, and it settles then.
- `closed`: one chat line naming the ticket and the reason.
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
  3. Start a fresh thread on a raised tier and point the entry at it with
     `ledger.sh rethread`. Route it with `--raise` set to the rungs the
     entry's model and effort sit above its size default, plus one; the
     owner is asked only when route's `ask` is true (Routing). Escalate
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
  start it again after escalating.

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

These are the only forms the owner ever sees, and every escalation in this
skill uses them, the permission hold and the stall at 3 included:

- **Progress**: one or two plain lines, no heading, no push. A completed step
  (merged, launched, settled) starts with `Done:`.
- **Needs you**: the message starts with `> [!CAUTION]`, then the line
  `> **NEEDS YOU:** <run>: <the one action>`, and names exactly one action.
  Send one push notification (the PushNotification tool) naming the run and
  that action. When the answer is a pick from fixed options (approve or deny a
  held call, a scope fork), also open an AskUserQuestion dialog with the
  recommended option first.

No progress message uses the alert, so a message without it never needs the
owner. One push per need, none for progress.

A held call's message names the thread, the held call and your
recommendation. Record the owner's answer with
`scripts/ledger.sh --ledger <ledger> ruling <text> --allow <call>`, which dates
it; pass `--allow` only when the answer lets that call run unheld in later
briefs, so a deny is a ruling with no `--allow`.

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
- Settle a finished thread; never archive one.
- Launch only on a claim of your own and the owner's go: a claim is never
  taken over, and the daily offer never launches.
