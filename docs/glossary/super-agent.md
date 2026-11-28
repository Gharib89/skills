### Super agent

The fleet file, machines, provider instances, the machine check, slots, placement and the ship cap are in [Super agent: fleet and placement](super-agent-fleet.md).

**Super agent**:
The one agent the owner talks to about every open ticket in every repo: a pinned T3 thread running the `super-agent` skill, which launches a thread per ticket, wakes on their changes, judges their gates and asks the owner only what is the owner's to decide. Its main agent is still the supervisor.
_Avoid_: router, orchestrator, chief of staff, dispatcher

**Supervised thread**:
One T3 thread the super agent launched, in its own worktree (a scratch folder for a task with no repo) on whichever machine runs it, recorded as an entry of the ledger: for a ticket (kind `ship` or `triage`) or for any other job the owner asked for (kind **task**: a grill, a deploy, decks, a review). A thread someone else launched that the owner asks it to watch is **adopted**, with the same entry. Every one is watched until it ends, whatever its kind (a ticket's on its PR or issue, a one-off task's on its `Result:` line, an interactive task's on the owner's drop), unless the owner takes it over: that thread is **owner-run**, still holding its machine's slot, its thread neither read nor nudged and its PR not merged by the super agent (only its PR and issue are read, on GitHub), until the owner says "Watch <thread>" (watching restarts from the thread's state then), its ticket closes or merges (it then settles with nothing for the super agent to clean up), or, for a task, the owner drops it. A thread that waits on the owner by design, such as a grill, is an **interactive task**; the super agent touches no thread the ledger does not hold, except the scratch threads it launches and, to settle them once at rest, the helper and review threads a supervised thread started.
_Avoid_: worker, worker thread, child thread, held thread (held is a permission-held call or a gate-held ticket), taken thread (taken is a won claim)

**Owner-run**:
A supervised thread the owner took ("I'll take <thread>"): the entry is marked `owner_run`, keeps its slot, counts no stall, gets no step-in and no cleanup, has its open needs cleared, and is read from GitHub alone. The call guard refuses a send into it, the status block lists it under `Yours`, and after 3 days one escalate row asks the owner "watch or drop?".
_Avoid_: paused, given back (the owner ends it with "Watch <thread>")

**Owner-steered**:
A supervised thread whose newest message from outside it is the owner's, newer than the entry's `held_since` (else `launched_at`). Reconcile marks the entry `steered` from the owner read's `owner_at`: it counts no stall and gets no nudge, its `Running` row ends `(you spoke last)`, the call guard refuses a send into it, and after the stall window at rest an escalate row asks the owner "watch or take?" until a need is recorded.
_Avoid_: owner-active, hijacked

**Call guard**:
The PreToolUse hook `call-guard.sh` of the super agent folder's generated settings: it refuses, with exit 2, a send into a thread no open ledger entry holds, or that is owner-run or owner-steered, unless the owner's `tell` lets exactly one send through. Each refusal is a line of `call-guard.jsonl` that the scorecard counts per week. A guard rail on the call's text, not a sandbox.
_Avoid_: send filter, send lock

**Ledger**:
The super agent's JSON file in the state directory, one entry per supervised thread it holds (a ticket's, keyed by issue, or a task's, keyed `task:<slug>` and settled when its thread's last line is `Result:`, never on its first rest or an issue's state; an interactive task's leaves only on the owner's drop; an adopted entry marked as such), with the thread, model, stage and stall count, plus the owner's recent rulings, each dated and lapsing after a week unless pinned (a lasting preference lives where a script reads it: the fleet file or the repo's ship profile). A settled entry moves to the ledger's archive a week after it settles. It is how a compacted or restarted super agent still knows what it owns; GitHub stays the record for issues, blocking edges and PRs.
_Avoid_: board, roster (that is drive-session's), wiki, memory

**One-off task**:
A task that does one bounded job the owner asked for in plain words ("run", "research", "test" or "deploy X"), launched by `launch.sh task` and placed like a ticket (a slot, pins, a waiting row when nothing fits) with no claim. Its launch message ends with the contract line: its final message's last line is `Result: <one line> <link>` or `Needs owner: <question>`. Reconcile settles it on `Result:`, raises a `needs-owner` escalate row on `Needs owner:` (no stall), and counts any other rest as a stall; the status block lists it once under `Finished`. Anything the super agent's own record cannot answer becomes one, except an asked machine check.
_Avoid_: inline job, side quest, errand

**Interactive task**:
A task that waits on the owner by design ("grill me on X"): it takes no slot, runs on the super agent's machine, carries no contract line, never counts as stalled and is never settled on its rest; it leaves only when the owner drops it.
_Avoid_: conversation thread, long-running task

**Waiting list**:
The ledger's `waiting` rows, in order: the owner's queue. A row is a ticket with no thread yet (or a one-off task nothing fit, carrying its ask, skill and placement flags), either one placement could not place (a machine or the ship cap was in the way) or one the owner queued; it may carry an order and an `--after` blocker, another ticket's key that must merge first, which is the ledger's own and adds no blocking edge on GitHub. Reconcile prints its `ready` rows (a ticket's when its blocker merged and its repo is under its ship cap, a task's on every pass), drops a ticket's row whose issue closed, and the super agent launches the `ready` ones. The owner's word "queue" means this list.
_Avoid_: backlog, pending list, a queue kept in a scratch file

**Watcher**:
The background script the super agent leaves running at the end of each turn: it reads every supervised thread and its PR and exits on the first change, and its exit wakes the super agent; a thread on a linked machine is read with the T3 CLI there over SSH, one call per machine per poll, and wakes it for every reason a local thread does. A machine it cannot read is watched from GitHub alone (its PR opening, its checks finishing, a merge or a close), and after 5 minutes unread the watcher exits once with one offer naming the machine. One runs per ledger, and it keeps watching a ticket whose PR merged until the thread rests, which is when the ticket settles. A thread finishing wakes nothing by itself.
_Avoid_: watchdog, poller, monitor

**State guard**:
The PreToolUse hook (`scripts/guard.sh`) in the super agent folder's generated settings that refuses a hand write to the ledger, fleet or quota file and names the script that updates it. A refusal means an override has no flag yet: the super agent reports it, never works around it.
_Avoid_: write lock, permission

**Watch guard**:
The Stop hook (`scripts/watch-guard.sh`) in the same generated settings that refuses the super agent's turn end once while `watch.sh --owed` says a watcher is owed (an open, observed entry and no live watcher, or open entries to reconcile first), naming the open entries and the command to run; the stop after that passes. It logs each block and each unwatched pass to `watch-guard.jsonl` beside the ledger, which the scorecard counts, and allows the stop when it cannot judge. The super agent still starts the watcher itself.
_Avoid_: watchdog, heartbeat

**Owner question**:
Any owner message that asks and tells nothing: why, what, when, how. A message that asks and tells gets the answer first, then exactly the told action, and a request phrased as a question ("can you launch 1234?") is a request. It starts an answer-only turn.
_Avoid_: owner ask (a request is an ask too), query

**Answer-only turn**:
The turn an owner question starts: the reply opens with an answer built from the record re-read in that turn, offers the fix as a numbered option recorded as a need with the reason word `ask-first`, and changes nothing. Only read-only calls and the watcher restart run in it, and no reconcile unless the watch guard asks. The owner's reply is the go. The observe hook logs each changing call made in one, and passes it.
_Avoid_: read-only mode, dry run

**Question flag**:
The UserPromptSubmit hook (`scripts/question-flag.sh`) in the same generated settings that adds one reminder line to a turn whose prompt holds a `?` or opens with why, what, when, where, who, which or how, and carries no T3 sender prefix, and logs the prompt's id to `question-flag.jsonl` beside the ledger, which the scorecard counts. The super agent still judges question or request, so a misfire costs one ignored line.
_Avoid_: question detector, answer-only gate (it refuses nothing)

**Wake timer**:
The systemd user timer that runs `scripts/wake-timer.sh` every 5 minutes, with no model, on the super agent's machine. While `watch.sh --owed` says a watcher is owed and the super agent's own thread is idle, it sends the thread one fixed wake line, then runs the notify command if no reconcile follows. A running thread is the watch guard's, and a limit stop is held until its reset plus 10 minutes. Its unit files are the owner's to install: `guard.sh --install` prints them, and a missing timer is a `needs` line in `home`.
_Avoid_: heartbeat, cron job, backstop (that is the hourly schedule)

**Waiting line**:
The fixed last line, `Waiting on my own background work.`, that ship's run contract, or a `/triage` launch message's contract line, tells a run to end a turn on when the turn ends only to wait on its own background work (a check, a CI wait, a subagent). The watcher and reconcile read a thread at rest on it as still working until the stall window passes: no `run-finished` event, no stall. A run's final message is its outcome (the PR URL and the gate state for ship, the triage outcome for triage), never this line.
_Avoid_: heartbeat, keepalive, status ping

**Limit stop**:
A thread at rest on a usage-limit line such as `You've hit your 5-hour limit · resets 6:10pm (Africa/Cairo)`. T3 resumes it by itself at the reset, so the watcher and reconcile read it as still working, with no `run-finished` event and no stall, until the reset plus the stall window; a rest still there after that is an ordinary stall. A reset they cannot read leaves an ordinary rest.
_Avoid_: rate-limit pause

**Wake action**:
A row in one of the three lists reconcile prints for what the super agent owes after a wake: `cleanup` (an entry ended: settle its thread, remove its worktree), `verify` (a ship PR merged: check it against the issue's criteria) and `escalate` (only the owner can unblock it: a permission hold, a fault, a stall at the cap, a closed PR or issue). A row stays in every answer until the super agent clears its cause (`cleanup_owed` or `verify_owed` set false, or a recorded need), so a wake that does nothing prints it again. The super agent does what the lists print, and never sets an entry's stage: reconcile moves it.
_Avoid_: todo, task (that is a ledger kind), notification

**Stall**:
A supervised thread at rest with its ticket not done: its run completed with no merged PR and no merge-gate summary, or no new run for the stall window. A run stopped on a usage limit is not stalled before its reset, since T3 resumes it then. Each stall raises the ticket's stall count and each real step lowers it; the count decides whether the super agent nudges, sends the missing fact, or starts a fresh thread or escalates.
_Avoid_: hang, idle (idle is a thread state, not a judgement), crash

**Merge-gate ruler**:
The fleet file's `merge_gate_ruler`: who rules on a merge-gate hold no standing waiver or ruling matches, the owner (default) or the super agent, which then decides and reports to the owner. A hold on a failure the PR did not cause is never waived by either: the failure is filed as its own issue and ordered first, and the gate re-runs after its fix.
_Avoid_: approver, gatekeeper

**Notify command**:
The fleet file's `notify` shell command and delay, which the wake timer runs once per outage: when its wake line cannot be sent, when no reconcile follows the wake within the delay, or when a permission request has waited 10 minutes on the super agent's thread. So a super agent that cannot recover by itself is noticed by the owner. A reconcile within the delay runs nothing.
_Avoid_: alert, heartbeat, backstop (that is the hourly schedule that wakes the super agent)

**Parents done**:
Reconcile's `parents_done` list: an open parent issue (a spec) whose sub-issues are all closed, offered to the owner once. The super agent closes the parent only on the owner's word.
_Avoid_: batch complete, epic done

**Standing waiver**:
A merge-gate hold the owner waives in advance, with its condition written out, so a hold that meets it merges without a round trip to the owner. The fleet file lists them; they never reach a supervised thread up front: the super agent cites the one that matches in a step-in when the thread stops at its gate. A hold outside the listed waivers goes to the merge-gate ruler.
_Avoid_: auto-merge, merge allowance (that is the permission to merge at all), exception

**Launch message**:
The first message of a supervised thread: its owner-skill invocation (`/ship-run <n>`, `/triage <n>`), plus one `Note:` line only when the owner gave one for that ticket. A `/triage` message also carries one contract line after the invocation, since the triage skill is upstream and cannot ask for the waiting line itself. A one-off task's is its ask, its last line the task contract line. Nothing else rides on it: rules the run must follow live in the skill, the repo's profile or the global rules it loads.
_Avoid_: launch brief, preamble, system prompt

**Step-in**:
A message the super agent sends into a supervised thread after its launch message, only when the thread reaches the situation it answers, and carrying only what that situation needs. The adoption step-in is one: the contract line, sent once into a one-off task thread the super agent adopted.
_Avoid_: re-brief, reminder, broadcast

**Claim**:
The mark a super agent puts on a ticket before it launches one: a comment (never an assignment: `/ship-run` assigns through its own claim), first line `<!-- super-agent-claim machine=<key> thread=<id> -->`, naming the machine and the claiming thread. The earliest claim comment on an issue holds it, so another super agent skips the ticket. A claim older than the stale window (3 days by default) is **stale**: it is offered back to the owner and never taken over.
_Avoid_: lock, lease, reservation

**Active repos**:
The fleet file's list of repos the super agent scans for ready work, edited by the owner's "track <repo>" and "stop tracking <repo>". Only they feed the **daily offer**.
_Avoid_: watchlist, subscriptions

**Daily offer**:
The list of open `ready-for-agent` issues in the active repos that no ledger entry or other machine's claim holds, which the super agent shows the owner once a day. It writes nothing; a ticket launches only on the owner's go.
_Avoid_: digest, auto-pickup, queue

**Unqueued issue**:
An open issue in an active repo, created since a batch began, that no ledger entry, waiting row or claim holds: a follow-up a run opened, say. Reconcile lists each once and the super agent offers it to the owner; it launches only on the owner's go.
_Avoid_: backlog, orphan issue

**Recurring find**:
One class of mistake or gap seen in two or more tickets. It is filed once as an issue in the repo it hits and ordered before the work it would hit, never fixed per ticket; a find that holds across repos is proposed to the owner as a global rule instead.
_Avoid_: pattern, trend, retro item

**Daily handover**:
The morning report's hand-off from the running super agent thread to a fresh one it launches with a bearings file, refreshing a stale super-agent copy first; the old thread then settles and the owner pins the new one. Only one super agent runs on a ledger at a time.
_Avoid_: rollover, rotation

**Bearings file**:
The Markdown file `handover.sh` writes from the ledger for the successor: the predecessor thread, the ledger, the skill versions, and the open entries, needs and waiting rows. It is a starting summary; the ledger stays the record.
_Avoid_: handoff notes, state dump

**Scorecard**:
The daily row `scorecard.sh` counts from the ledger, the guard and timer logs and the super agent's own transcript (workload, messages, needs, questions, wakes and tokens), stamped with the skill version that ran the day, and the weekly review that adds one line to the bearings file's Needs you list per number over its target. A new super-agent version is judged by these counts, not by a model's reading.
_Avoid_: metrics, dashboard, report card

**Replay case**:
A test that reproduces one dated super-agent incident from a hand-built fixture, `tests/super-agent-replay-<incident>.test.sh`, proven red on the incident's version before the fix makes it green.
_Avoid_: regression fixture, incident test

**Super agent folder**:
The folder the pinned super agent thread runs in, `super-agent/home` under `$XDG_STATE_HOME` (`~/.local/state` when unset), holding the generated `.claude/settings.local.json` and `.claude/settings.json` that `setup.sh --write` and every daily handover rewrite. Its settings reach only that thread, so they carry the super agent's hooks, starting with the state guard, and the cut that lowers its context floor. The owner creates its T3 project once.
_Avoid_: super agent workspace, pinned folder

**Context floor**:
The context the pinned super agent thread's first call reads after a fresh start or after a compaction; every later call reads at least that much. The scorecard counts both (`floor.fresh`, `floor.compacted`), and the super agent folder's settings lower it.
_Avoid_: baseline context

**Context floor cut**:
The super agent folder's `.claude/settings.json`: the tools, MCP servers, rules files and skills the pinned thread never uses, denied, excluded or switched off to lower its context floor. A two-week trial that `cut-off` in the folder turns off.
_Avoid_: trim, slim settings
