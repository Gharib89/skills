### Super agent

**Super agent**:
The one agent the owner talks to about every open ticket in every repo: a pinned T3 thread running the `super-agent` skill, which launches a thread per ticket, wakes on their changes, judges their gates and asks the owner only what is the owner's to decide. Its main agent is still the supervisor.
_Avoid_: router, orchestrator, chief of staff, dispatcher

**Supervised thread**:
One T3 thread the super agent launched, in its own worktree on whichever machine runs it, recorded as an entry of the ledger: for a ticket (kind `ship` or `triage`) or for any other job the owner asked for (kind **task**: a grill, a deploy, decks, a review). A thread someone else launched that the owner asks it to watch is **adopted**, with the same entry. Every one is watched until it is at rest, whatever its kind, unless the owner takes it over: that thread is **paused**, still holding its machine's slot, its thread neither read nor nudged and its PR not merged by the super agent (only its PR and issue are read, on GitHub), until the owner gives it back (watching restarts from the thread's state then), its ticket closes or merges (it then settles with nothing for the super agent to clean up), or, for a task, the owner drops it. A thread that waits on the owner by design, such as a grill, is **interactive**: it never counts as stalled and is not settled on its rest, but leaves when the owner drops it; the super agent touches no thread the ledger does not hold, except the probe threads it launches and, to settle them once at rest, the helper and review threads a supervised thread started.
_Avoid_: worker, worker thread, child thread, held thread (held is a permission-held call or a gate-held ticket), taken thread (taken is a won claim)

**Ledger**:
The super agent's JSON file in the state directory, one entry per supervised thread it holds (a ticket's, keyed by issue, or a task's, keyed `task:<slug>` and closed on its thread's rest, never on an issue's state; an adopted entry marked as such), with the thread, model, stage and stall count, plus the owner's recent rulings, each dated and lapsing after a week unless pinned (a lasting preference lives where a script reads it: the fleet file or the repo's ship profile). A settled entry moves to the ledger's archive a week after it settles. It is how a compacted or restarted super agent still knows what it owns; GitHub stays the record for issues, blocking edges and PRs.
_Avoid_: board, roster (that is drive-session's), wiki, memory

**Waiting list**:
The ledger's `waiting` rows, in order: the owner's queue. A row is a ticket with no thread yet, either one placement could not place (a machine or the ship cap was in the way) or one the owner queued; it may carry an order and an `--after` blocker, another ticket's key that must merge first, which is the ledger's own and adds no blocking edge on GitHub. Reconcile prints its `ready` rows (blocker merged, repo under its ship cap), drops a row whose issue closed, and the super agent launches the `ready` ones. The owner's word "queue" means this list.
_Avoid_: backlog, pending list, a queue kept in a scratch file

**Status block**:
The one report the owner reads, printed by every reconcile from the ledger alone and posted as printed: the rows `Needs you`, `Merged`, `Running` and `Waiting`, an empty row left out, each ticket a link and each task or adopted entry marked as one, ending on the provider instance the super agent itself runs on. A wake that changed no row posts none, and only a new open need sends a push; a digest prints the whole block on the owner's "status", at the morning report and when the waiting list empties.
_Avoid_: report (prose written fresh on each wake), summary, dashboard

**Watcher**:
The background script the super agent leaves running at the end of each turn: it reads every supervised thread and its PR and exits on the first change, and its exit wakes the super agent; a thread on a linked machine is woken from GitHub alone (its PR opening, its checks finishing, a merge or a close) and read itself only on a wake. One runs per ledger, and it keeps watching a ticket whose PR merged until the thread rests, which is when the ticket settles. A thread finishing wakes nothing by itself.
_Avoid_: watchdog, poller, monitor

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
The fleet file's `notify` shell command and delay. When the watcher exits on an event and no reconcile follows within the delay, the command runs once, so a super agent that stopped is noticed by something other than itself. A reconcile within the delay runs nothing.
_Avoid_: alert, heartbeat, backstop (that is the schedule that wakes the super agent)

**Parents done**:
Reconcile's `parents_done` list: an open parent issue (a spec) whose sub-issues are all closed, offered to the owner once. The super agent closes the parent only on the owner's word.
_Avoid_: batch complete, epic done

**Standing waiver**:
A merge-gate hold the owner waives in advance, with its condition written out, so a hold that meets it merges without a round trip to the owner. The fleet file lists them; they never reach a supervised thread up front: the super agent cites the one that matches in a step-in when the thread stops at its gate. A hold outside the listed waivers goes to the merge-gate ruler.
_Avoid_: auto-merge, merge allowance (that is the permission to merge at all), exception

**Launch message**:
The first message of a supervised thread: its owner-skill invocation (`/ship-run <n>`, `/triage <n>`), plus one `Note:` line only when the owner gave one for that ticket. A `/triage` message also carries one contract line after the invocation, since the triage skill is upstream and cannot ask for the waiting line itself. Nothing else rides on it: rules the run must follow live in the skill, the repo's profile or the global rules it loads.
_Avoid_: launch brief, preamble, system prompt

**Step-in**:
A message the super agent sends into a supervised thread after its launch message, only when the thread reaches the situation it answers, and carrying only what that situation needs.
_Avoid_: re-brief, reminder, broadcast

**Fleet file**:
The owner's user-scope file, written by the super agent's setup step and carried to every machine, that lists what the super agent may use: each linked machine with its capabilities and slot count, each provider instance with its quota read and auth result, the GitHub accounts, the active repos (each with its ship cap and machine pin), the default standing waivers, who rules on a merge-gate hold and the notify command. The skill itself names none of these, so it stays the same for every owner.
_Avoid_: config, inventory, profile (a ship profile is per repo)

**Provider instance**:
One T3 provider the super agent may launch on, named by T3's instance id: two Claude accounts are two instances of one driver, Pi another. Each is signed in and read for quota under its own account directory, so the fleet file keys its providers by instance id and routing picks the instance with the most weekly headroom, skipping one that is signed out; two instances on one account read the same buckets. An instance's **weekly weight** (a number, default 1, the owner's) says how many times larger its weekly quota is than another's, so headroom is its weekly remaining times that weight: 40% of a seat three times the size outranks 60% of the small one. Two fractions in the fleet file set the **floors**: an instance whose weekly bucket is under the weekly reserve, or a `claude` instance whose 5 hour bucket is under the 5 hour floor, is skipped, and the route's reason names which.
_Avoid_: account, provider (that is the driver), subscription

**Slot**:
One supervised thread a machine may run at once. The fleet file sets each machine's slot count as a ceiling, less the slots it keeps for the owner's messages (`reserve`, 1 on the super agent's own machine); a launch still checks the machine's free memory and load before it takes a slot. A probe thread takes none. The `fleet` script sets it. A slot bounds a machine; the **ship cap** bounds a repo.
_Avoid_: worker, lane, seat

**Placement**:
Choosing the machine a launch runs on: the super agent's own machine first, a GPU machine for GPU work, the next reachable linked machine that fits when one is down, and a row in the ledger's waiting list when none does, a launch over its repo's ship cap included. A repo the fleet file pins to a machine (a **machine pin**) is placed there alone, and waits when that machine is down or full. A machine is reached only through its T3 environment id, and only if the owner already linked it.
_Avoid_: scheduling, load balancing

**Ship cap**:
The most supervised threads one repo may have open at once, across every machine, set per repo in the fleet file as `max_ships` (3 when unset). It counts every open thread of the repo, ship and triage alike, so a launch over it becomes a waiting row naming the cap. Different from a slot, which is a machine's ceiling.
_Avoid_: repo limit, concurrency limit, quota (that is a provider's)

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

**Probe thread**:
A scratch thread the super agent launches on a linked machine to run the fixed probe there (cores, RAM, GPU, provider CLIs, gh logins) and reply with one JSON line, which setup merges into the fleet file. It is settled once its reply is read and is no ledger entry.
_Avoid_: health check, ping

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
The daily row `scorecard.sh` counts from the ledger, the guard and timer logs and the super agent's own transcript (workload, messages, needs, questions, wakes and tokens), stamped with the skill version that ran the day, and the weekly review that raises one Needs you row per number over its target. A new super-agent version is judged by these counts, not by a model's reading.
_Avoid_: metrics, dashboard, report card

**Replay case**:
A test that reproduces one dated super-agent incident from a hand-built fixture, `tests/super-agent-replay-<incident>.test.sh`, proven red on the incident's version before the fix makes it green.
_Avoid_: regression fixture, incident test
