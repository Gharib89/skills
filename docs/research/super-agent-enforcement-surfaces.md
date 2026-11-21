# Research: what T3 Code and the Claude Code harness can enforce or report for the super agent

Researched 2026-11-21 for issue #1315 (map #1310): which super agent rules a
hook, a script or a T3 tool can carry instead of the skill's prose.

Probed inside a T3-hosted Claude thread in `auto` mode: Claude Code 2.1.329,
`t3` CLI v0.1.6, T3 server 0.1.11-nightly.20261119.4941. Each claim carries its
basis: **measured** (a probe run that day, command or tool named), **sourced**
(a primary page), **inferred** or **guess**. The probes only read: schemas,
help text, existing schedules and threads, local session transcripts, and
sample JSON piped into hook scripts. `HOOKS` below is
<https://code.claude.com/docs/en/hooks>, `SKILLS` is
<https://code.claude.com/docs/en/skills>, both read 2026-11-21.

## Verdicts

| # | Question | Verdict |
|---|---|---|
| 1 | A Stop hook refusing a turn end while an entry is open and no watcher runs | **Possible** from the user settings file. Skill frontmatter is not a reliable carrier under T3. |
| 2 | Has the owner typed in a supervised thread | **Possible**: each message carries author, source and time. |
| 2 | Is the owner present | **Not possible**: no signal found. |
| 3 | Transfer and worktree handoff as take-over and give-back | **Not a fit**: neither moves control of a thread. |
| 4 | A schedule as the carrier of a recurring check | **Possible**, with the limits below. |
| 5 | Seeing a permission hold on another thread | **Possible as a count**; the held call's content is unprobed. |
| 5 | Answering it from outside | **Not possible** through T3. A `PermissionRequest` hook inside the held session is the one route, unprobed. |

## 1. A Stop hook that keeps the watcher rule

### It fires under T3, and a block feeds its reason back

- T3 runs a thread as `claude --output-format stream-json --input-format
  stream-json --permission-prompt-tool=stdio --resume=<session>
  --permission-mode=auto`, with no flag limiting setting sources. **measured**
  (`/proc/$CLAUDE_PID/cmdline`).
- The session transcript records `entrypoint: "t3-code"` and, per turn, a
  `stop_hook_summary` naming the hooks that ran: the repo's
  `.claude/settings.json` Stop hook and one `callback` (T3's own,
  **inferred**). 2,894 such summaries exist across local transcripts.
  **measured** (`grep stop_hook_summary` over `~/.claude/projects/`, grouped
  by `entrypoint` with `jq`).
- Stop hooks fire on scheduled turns too: four hourly backstop wakes of a super
  agent thread each have a summary within a second of the turn's last message.
  **measured** (summary timestamps against `t3_thread_read`).
- 13 Stop hook runs in T3-hosted transcripts blocked (exit 2), on Claude Code
  2.1.318 to 2.1.323. In the one read in full, the next record is a user-role
  meta message starting `Stop hook feedback:` with the hook's stderr, and the
  assistant acts on it. **measured** (`jq` over summaries with `hookErrors`,
  then the records around one).
- A Stop hook blocks by exit 2 (stderr is the reason) or by printing
  `{"decision": "block", "reason": "..."}`.
  `hookSpecificOutput.additionalContext` continues the turn the same way,
  labelled feedback, not an error. **sourced** (`HOOKS`, "Stop decision
  control").
- Stop does not run after a user interrupt, and an API error fires
  `StopFailure`, which cannot block. **sourced** (`HOOKS`, "Stop"). So an
  interrupted turn, a usage-limit stop or a dead session still ends
  unwatched: the backstop schedule and the notify command stay. **inferred**.

### What the hook reads

Stop stdin carries `stop_hook_active` (true while continuing after a block),
`last_assistant_message`, `background_tasks` (in-flight tasks; a `shell` one
has its `command`) and `session_crons` (the session's own wakeups, not T3's
schedules, **inferred**). **sourced** (`HOOKS`, "Stop input"). The hook has two
witnesses of a live watcher: the lock `<ledger>.watch` holding a live
`watch.sh` pid (the test `pulse.sh` uses) and a `watch.sh` shell in
`background_tasks`. Whether T3-hosted sessions fill `background_tasks` is
**unprobed**; the lock needs nothing from the harness.

### Scope and loop guards

- A user-settings hook runs in every Claude session on the machine, supervised
  threads included, and they can read the same ledger path. The session's
  environment holds `T3CODE_THREAD_ID` (**measured**,
  `/proc/$CLAUDE_PID/environ`), but no script stores the super agent's thread
  id in the ledger (**measured**, `grep` over `skills/super-agent/scripts/`).
  The hook needs that one new fact, written at first launch and at the daily
  handover, and exits 0 unless the two match.
- Claude Code overrides a block after 8 consecutive Stop hook continuations;
  the count resets on every tool call; `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`
  raises it. **sourced** (`HOOKS`, "Stop input"). The reset means the cap does
  not end a loop where the agent calls a tool between stops and the condition
  never clears, so the hook must allow the stop when `stop_hook_active` is
  true: one block per stop attempt. **inferred**.
- `watch.sh` exits 1 when a watcher runs or no open entry is observed yet
  (**measured**, its header), so the hook must test the same two facts or it
  blocks on a state the watcher refuses to start in.
- The repo's own Stop hook stores a fingerprint of the state it last judged
  and stays silent when unchanged (**measured**,
  `.claude/hooks/check-hook.sh`): a second guard worth copying.

### A prototype, tested by piping sample input

A 17-line prototype (thread scope, open-entry count, lock, `background_tasks`,
`stop_hook_active`) against a throwaway ledger. **measured** (`printf '<json>'
| bash stop.sh` per case): an open entry with no watcher, or with a dead pid
in the lock, printed `{"decision":"block","reason":"The ledger holds 1 open
entry(ies) and no watcher runs. ..."}`; `stop_hook_active` true, a `watch.sh`
in `background_tasks`, a live `watch.sh` pid in the lock, another thread's
session, an all-settled ledger and a missing ledger each printed nothing and
exited 0. This proves the decision logic and output shape, not the harness's
reaction in the super agent thread.

### Can the skill ship it

- **User settings: yes.** `guard.sh --install` already merges a `PreToolUse`
  entry into `~/.claude/settings.json`, and it is installed and refuses a
  ledger write. **measured** (`jq .hooks` on that file; sample JSON piped into
  `guard.sh` exits 2 for a ledger path, 0 for another file). A Stop entry can
  ride the same installer.
- **Skill frontmatter: supported, unreliable here.** Frontmatter `hooks`
  register when the skill is invoked and "are removed when you exit or leave
  the conversation with a command such as `/clear` or `/resume`". **sourced**
  (`HOOKS`, "Hooks in skills and agents"; `SKILLS`, frontmatter reference). T3
  respawns `claude --resume` inside one thread: the probe session's process
  was 15 minutes old in a 56-minute-old thread. **measured** (`ps -o
  lstart=,etimes= -p $CLAUDE_PID` against the thread's `createdAt`). A
  respawned process holds the hook only once the skill is invoked again
  (**inferred**), so a backstop wake that runs `pulse.sh` without invoking the
  skill would run unhooked.
- **Project settings: no** (it would ship in every repo that installs the
  skill). **A plugin: possible**, a skill folder with `.claude-plugin/plugin.json`
  loads with its own hooks (**sourced**, `SKILLS`), not probed.

A stronger variant: an `asyncRewake` hook "runs in the background and wakes
Claude on exit code 2", "even when the session is idle" (**sourced**, `HOOKS`,
"Run hooks in the background"). A Stop hook of that kind running `watch.sh`
would be the watcher, with no agent action. Whether its wake reaches a
T3-hosted session is **unprobed**, and that it does is a **guess**.

### Remaining probes

1. Install the prototype as a user-settings Stop entry, open one entry in a
   scratch ledger, end a turn in a scratch T3 thread with no watcher: confirm
   the reason arrives, the thread stays `running`, and the second stop passes.
2. Have that hook save its stdin once: is a `run_in_background` shell listed in
   `background_tasks` under `entrypoint: "t3-code"`.
3. The same hook in a scratch skill's frontmatter: invoke the skill, wait for
   T3 to respawn the process, end a scheduled turn. Does it still fire.
4. An `asyncRewake` Stop hook that sleeps 60 s and exits 2 in an idle T3
   thread: does a turn start.

## 2. Whether the owner typed, and whether the owner is present

`t3_thread_read` returns each item with `createdBy`, `creationSource`,
`updatedAt`, `type`, `runId` and `position`. **measured** (reads of a settled
super agent thread and a settled supervised thread, `limit` 3 to 14):

| Writer | `type` | `createdBy` | `creationSource` | Extra |
|---|---|---|---|---|
| The owner, web client | `user_message` | `user` | `web` | |
| The owner, phone | `user_message` | `user` | `mobile` | |
| Another thread's agent (the launch message) | `user_message` | `agent` | `mcp` | `senderThreadId` |
| A bound schedule firing | `user_message` | `agent` | `mcp` | `messageId` starts `scheduled-task-message:` with the task id and fire time |
| The thread's own agent | `assistant_message` | `agent` | `provider` | |

So "the owner stepped into this thread" is script-readable: a `user_message`
with `createdBy: "user"` after the launch message, with its time and device.
That a `t3_thread_send` step-in carries the launch message's fields is
**inferred** (only the launch message was sampled).

The `t3` CLI is not enough: `t3 thread show <id> --json` returns messages as
`{role, runId, text}` only. **measured** (keys listed with `jq`). `watch.sh`
reads threads through that CLI, so it cannot see an owner message today; a
script needs the MCP read saved to a file (the route `reply.sh` already gives
remote entries) or a CLI that grows the fields.

**Presence: no signal.** The thread record has `createdAt`, `updatedAt`,
`settled`, `settledAt`, `snoozed`, `pinned`, `archived`, `pendingRequestCount`
and no viewed, focused or last-seen field; `t3_environment_read` returns
identity and preferences only; no `t3` subcommand concerns clients; and
`t3_thread_organize` has `mark_unread`, so a read state exists that no read
tool returns. **measured** (`t3_thread_read`, `t3 thread list --json` keys,
`t3 --help`, tool schemas). The only proxy is the newest owner message across
threads. This supports the map's note that "away" is an explicit switch.

Remaining probe: `t3_thread_read` on a thread that received a `t3_thread_send`
step-in and a `t3 thread send` CLI message, recording each one's `createdBy`,
`creationSource` and `senderThreadId`.

## 3. Thread transfer and worktree handoff

- `t3_thread_transfer` moves **context**, not control: `fork` copies a thread's
  context from a source point into a new thread with the same setup and runs
  no turn; `merge_back` merges context into a related thread of the same
  project; `status` lists transfers. **measured** (schema; `status` on the
  probe thread returned `{"transfers": []}`).
- `t3_worktree_handoff` moves **the calling thread itself** into a new
  worktree on a new branch. It takes no thread id, ends the live session,
  resumes only with a `continuationPrompt`, and fails if the thread has a
  worktree. **measured** (schema; `t3_worktree_status` returned `attached:
  false`).

Neither fits. T3 has no owner-of-a-thread field to transfer (**measured** key
list): the owner takes a thread over by typing in it, and it stays the same
thread. A fork would split the work in two while the ledger entry, claim and
watcher key on the first thread, and `merge_back` returns context, not commits
(**inferred**). The handoff cannot act on another thread and would fail on a
ship thread, which already has a worktree. `ledger.sh pause` and `unpause`
stay the carrier; section 2 adds the trigger, since a script can see the
owner's message and pause without the owner saying "take".

Remaining probe: `fork` a settled scratch thread and read the new thread's
`worktreePath`, `branch` and `parentThreadId`, then what `merge_back` adds to
the target.

## 4. Schedules as the carrier for a recurring check

`schedule_task` creates "scheduled work that runs with no turn active" from a
prompt and one trigger: `interval` (`everyMs`, minimum 60,000), `fixed_time`
(`timeOfDay`, `weekdays`), `once` (`runAt`) or `webhook` (up to 16 filters, a
signature, a dedupe window of 10 to 3,600 s). `bindToCurrentThread` true posts
each run into the creating thread, false starts a new thread per run;
`freshSession` true makes runs share one thread with a fresh provider session
each; `projectId` and `environmentId` place it elsewhere; `enabled: false`
pauses. **measured** (schemas). `list_scheduled_tasks` returns per task its
id, `prompt`, `enabled`, `boundThreadId`, `freshSession`, `schedule`,
`nextRunAt` and `lastRunStatus`, one project per call. **measured** (the call
listed five tasks).

- A bound run arrives as a `user_message` with `createdBy: "agent"`,
  `creationSource: "mcp"` and a `messageId` naming the task, so a scheduled
  wake is told from the owner and from a step-in by fields. **measured**.
- An hourly interval fired at 04:19:21, 05:19:23, 06:19:25 and 07:19:26 UTC:
  on time, drifting about 2 s per fire. **measured** (`updatedAt`).
- Each run was an ordinary turn: it ran `pulse.sh`, answered in about 30 s,
  and the Stop hooks fired. **measured**. So a bound run has the thread's
  context and tools: it can read any thread, post in its own, and send to
  another (the send **inferred** from the tool set).
- A `once` task stays listed after it ran, and a disabled task stays listed.
  **measured**. Nothing prunes them, so "is my backstop scheduled" must test
  `enabled` and `boundThreadId`, not presence.
- Binding is to a thread id: the list held a backstop and a morning report
  bound to earlier super agent threads, both disabled. **measured**. A
  handover that forgets a schedule leaves it firing in a thread nobody reads.

A recurring check fits an **unbound `freshSession`** task in the check's own
project: one thread holds its history, no context grows, and the super agent
is not woken by an empty run. What the schedule does not give:

- **Report only on a change.** Every run is a model turn ending in a message.
  The change test belongs in a script the prompt names, with the last value in
  a state file.
- **A wake for the super agent.** A thread a schedule made wakes nothing when
  it finishes (measured 2026-11-06, `docs/research/super-agent.md` section 5).
  The run sends to the super agent's thread, or the watcher polls it as an
  entry.
- **A run without a turn.** No script-only schedule exists, so a fast poll
  belongs in a background script with the schedule as backstop.

Remaining probes: an unbound `freshSession` task whose prompt sends one line
to its creator (first run makes the thread, later runs reuse it without
context, the send wakes the creator); a bound schedule firing mid-turn
(queued, steered or dropped); `run_scheduled_task_now` from an `auto` thread
(its description says it "needs a full-access or default caller").

## 5. A permission hold on another thread

- **Seen as a count.** `pendingRequestCount` is in `t3_thread_read`,
  `t3_thread_list` and `t3 thread show --json`, and `watch.sh` turns a rise
  into `pending-approval`. **measured**.
- `t3_pending_request` lists "pending user questions"; "approvals are not
  listed", and `respond` "cannot approve a permission request". **measured**
  (schema; `list` on the probe thread returned no ids). No other tool or `t3`
  subcommand takes an approval.
- Whether the held call's text is readable from outside is **unprobed**: no
  thread was waiting (`t3_thread_list` with `statuses: ["waiting"]` returned
  none). The `activity` view lists `command_execution` items with their
  command text (**measured** on a settled thread), so a held one may appear
  with a pending status (**guess**).
- The harness has a route inside the held session. T3 passes
  `--permission-prompt-tool=stdio` (**measured**), and for such a call
  `PermissionRequest` hooks "run alongside your host, and whichever decides
  first applies"; one can return `behavior: "allow"` or `"deny"`, and cannot
  approve what a deny rule refuses. **sourced** (`HOOKS`,
  "PermissionRequest"). A user-settings hook on the supervised thread's
  machine could write the held call to a file the super agent's scripts read,
  and apply a standing allow list before the hold reaches the owner. Both are
  **inferred** and **unprobed** under T3.
- A thread's permission mode is set at launch (`t3_thread_launch`
  `runtimeMode`, "modes cannot exceed yours") and cannot be changed from
  outside: `t3_thread_configure` says "permission modes stay". **measured**.

Remaining probes: launch a scratch thread in `approval-required` with a
one-command task, and while it holds read it with `view: "activity"` and call
`t3_pending_request` `list` with its id; then a `PermissionRequest` hook that
saves its stdin, to see whether it runs for a T3-hosted hold and whether
returning `allow` releases it.

## What this changes for the map

- **Pain point 1.** A user-settings Stop hook can refuse the turn end, scoped
  by one new ledger fact. Interrupts, API errors and dead sessions stay with
  the backstop schedule and the notify command.
- **Pain points 4 and 5.** The owner's messages in a supervised thread are
  readable through `t3_thread_read`, not through the CLI the watcher uses.
  Transfer and handoff are the wrong tools; pause and unpause stay.
- **Pain point 7.** No presence signal: "away" has to be a switch.
- **Pain point 3.** A schedule carries a recurring check, with the change test
  in a script and a cleanup and handover step for the schedule list.
- **Pain point 6.** A hold is visible as a count; naming the held call needs
  the unprobed activity read or a `PermissionRequest` hook per machine.
