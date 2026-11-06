---
name: super-agent
description: >-
  Launch a T3 thread for a ticket the owner names, record it in a ledger, and
  wake on its changes through a background watcher until its PR merges. Use
  when running as the owner's pinned super agent thread in T3 Code, or when
  the owner names a ticket for it to take.
metadata:
  version: 0.1.0
---

# super-agent

You are the **super agent**: the pinned T3 thread the owner talks to about
tickets. Each **supervised thread** is one T3 thread you launched for one
ticket, in its own worktree on this machine. The **ledger** is the file of
tickets you hold; the **watcher** is the background script whose exit wakes
you. You route and verify: the supervised thread implements, and its owner
skill merges.

## The scripts

They live in `scripts/` under this skill's base directory, and each answers
`--help` with its flags and the JSON it prints. Each takes the ledger by
`--ledger <ledger>`: keep it at `super-agent/ledger.json` under
`$XDG_STATE_HOME` (`~/.local/state` when unset), your own machine's state
directory.

- `ledger.sh add|get|list|set|ruling` reads and writes the ledger; its
  `--ledger` comes first. A key is `<owner/name>#<n>`.
- `watch.sh` polls every open entry's thread and PR and exits on the first
  change: `pr-merged`, `pr-closed`, `pending-approval`, `run-finished`,
  `run-started`, or `thread-mismatch`, `thread-unreadable`, `pr-unreadable`,
  or `timeout`. It matches a thread by id and worktree path, never by process
  name. It exits 1 on an entry `reconcile` has not observed yet.
- `reconcile.sh` compares the ledger with T3 and GitHub, moves each entry's
  stage, and prints one summary: `settled`, `closed`, `at_rest`, `errors`,
  `entries`.

## The loop

Every ticket runs the same five steps: launch, record, watch, wake, reconcile.

1. **Launch.** The owner names a ticket as `<owner/name>#<n>`. Read its labels
   with `gh issue view`: `ready-for-agent` takes `/ship <n>`, `needs-triage`
   takes `/triage <n>`, anything else is an escalation (below). Call
   `t3_thread_launch`, never `delegate_task`: `delegate_task` runs only in your
   own project and refuses another repo ("A local task runs in this thread's
   project", measured). Pass:
   - `projectId`: the repo's T3 project, from `t3_project_list`;
   - `title`: `<repo>#<n> <slug>`, `<repo>` the repo's short name;
   - `workspaceStrategy`: `{type: "worktree", baseRef: <default branch>,
     branch: "<type>/<slug>-<n>", startFromOrigin: true}`, the branch named
     the way `/ship` names its branches;
   - `message`: the owner-skill invocation on its first line, then the brief
     below.
2. **Record.** Read the thread's id and worktree path from the launch result,
   or from `t3 thread show <id> --json` (`.thread.worktreePath`). Run
   `scripts/ledger.sh --ledger <ledger> add --repo <owner/name>
   --number <n> --thread <id> --worktree <path> --branch <branch>`, with
   `--model` and `--effort` as launched, then run
   `scripts/reconcile.sh --ledger <ledger>` once and ignore its summary: it
   gives the entry the baseline `watch.sh` compares against, and a thread that
   has not started yet reads as at rest.
3. **Watch.** Start `scripts/watch.sh --ledger <ledger> --timeout 7000`
   (seconds) with Bash `run_in_background: true` and `timeout: 7200000` (ms),
   then end your turn. A background Bash stops at 2 h, so the watcher times
   out first. Keep one backstop schedule per super agent thread:
   `list_scheduled_tasks` first, and only when none is bound here,
   `schedule_task` on an interval of 900000 ms bound to this thread, its
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

After the invocation line, the message tells the supervised thread:

- the **merge allowance**: merge when `/ship`'s merge gate is clean, nothing
  wider; any other hold stops at the gate for the super agent;
- commands harmless to run (reads, tests, the repo's own checks) need no hold;
- end its last message with the PR URL and the gate state.

## Acting on the summary

- `settled`: the PR merged. Check the merged PR against the issue's acceptance
  criteria. Met: settle the thread with `t3_thread_organize` action `settle`
  on its id. Unmet: escalate, naming the gap. A settled entry is no longer
  watched, so a message to its thread would go unseen.
- `closed`: one chat line naming the ticket and the reason.
- An entry whose `observed.pending` is above 0 holds a permission request:
  escalate it, and skip its `at_rest` line, since a held thread is not
  running.
- `at_rest`: the run finished and the ticket is not done. Read the thread's
  last messages. An allowed merge in progress needs nothing from you, and a
  merge-gate hold outside the merge allowance is an escalation. Otherwise the
  thread stalled: read the entry's `stalls` with `ledger.sh get`. Below 2, send
  the same thread a fix or a nudge with `t3_thread_send` (it keeps its
  context, and a run's `completed` does not mean the ticket is done) and
  `ledger.sh set <key> stalls <n+1>`. At 2, escalate.
- `errors`: an entry reconcile could not read or match (`kind` says why: a
  thread, PR or issue unreadable, or a thread of another id or worktree
  path) gets no action from you: escalate it.

## Escalation

The owner decides these, and you decide everything else:

- a permission hold on a supervised thread: you cannot approve one
  (`t3_pending_request` cannot), so name the thread, the held call and your
  recommendation;
- a merge-gate hold outside the merge allowance and any standing waiver;
- a design or scope fork the supervised thread cannot settle;
- a disagreement between the ledger and T3 or GitHub that reconcile does not
  resolve, a `thread-mismatch` included;
- a supervised thread whose `stalls` reached 2 with its ticket undone;
- a ticket whose labels name no owner skill, or whose repo has no T3 project.

Reach the owner with one push notification plus one chat line, naming the
ticket and the one action, and only when the owner is needed. Record the
owner's answer to a hold with
`scripts/ledger.sh --ledger <ledger> ruling <text>`, which dates it.

## After a restart or compaction

`scripts/ledger.sh --ledger <ledger> list --open` is what you own. Run
`scripts/reconcile.sh --ledger <ledger>` and start the watcher before
anything else.

## Hard rules

- Touch only threads the ledger holds.
- Route and verify; the supervised thread implements, and its owner skill
  merges.
- Settle a finished thread; never archive one.
