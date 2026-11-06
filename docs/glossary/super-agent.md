### Super agent

**Super agent**:
The one agent the owner talks to about every open ticket in every repo: a pinned T3 thread running the `super-agent` skill, which launches a thread per ticket, wakes on their changes, judges their gates and asks the owner only what is the owner's to decide. Its main agent is still the supervisor.
_Avoid_: router, orchestrator, chief of staff, dispatcher

**Supervised thread**:
One T3 thread the super agent launched for one ticket, in its own worktree on whichever machine runs it, recorded as an entry of the ledger. The super agent touches no thread the ledger does not hold.
_Avoid_: worker, worker thread, child thread, held thread

**Ledger**:
The super agent's JSON file in the state directory, one entry per ticket it holds, with the ticket's supervised thread, model, stage and stall count, plus the owner's standing rulings, each dated. It is how a compacted or restarted super agent still knows what it owns; GitHub stays the record for issues, blocking edges and PRs.
_Avoid_: board, roster (that is drive-session's), wiki, memory

**Watcher**:
The background script the super agent leaves running at the end of each turn: it reads every supervised thread and its PR and exits on the first change, and its exit wakes the super agent. A thread finishing wakes nothing by itself.
_Avoid_: watchdog, poller, monitor

**Stall**:
A supervised thread at rest with its ticket not done: its run completed with no merged PR and no merge-gate summary, or no new run for the stall window. Each stall raises the ticket's stall count and each real step lowers it; the count decides whether the super agent nudges, re-briefs, or starts a fresh thread or escalates.
_Avoid_: hang, idle (idle is a thread state, not a judgement), crash

**Standing waiver**:
A merge-gate hold the launch template waives in advance, with its condition written out, so a run that meets it merges without a round trip to the owner. Any hold outside the listed waivers is still an escalation.
_Avoid_: auto-merge, merge allowance (that is the launch permission to merge at all), exception

**Fleet file**:
The owner's user-scope file, written by the super agent's setup step and carried to every machine, that lists what the super agent may use: each linked machine with its capabilities and slot count, each subscription with its quota read, the GitHub accounts, the active repos and the default standing waivers. The skill itself names none of these, so it stays the same for every owner.
_Avoid_: config, inventory, profile (a ship profile is per repo)

**Slot**:
One supervised thread a machine may run at once. The fleet file sets each machine's slot count as a ceiling, less the slots it keeps for the owner's messages (`reserve`, 1 on the super agent's own machine); a launch still checks the machine's free memory and load before it takes a slot. A probe thread takes none.
_Avoid_: worker, lane, seat

**Placement**:
Choosing the machine a launch runs on: the super agent's own machine first, a GPU machine for GPU work, the next reachable linked machine that fits when one is down, and a row in the ledger's waiting list when none does. A machine is reached only through its T3 environment id, and only if the owner already linked it.
_Avoid_: scheduling, load balancing

**Probe thread**:
A scratch thread the super agent launches on a linked machine to run the fixed probe there (cores, RAM, GPU, provider CLIs, gh logins) and reply with one JSON line, which setup merges into the fleet file. It is settled once its reply is read and is no ledger entry.
_Avoid_: health check, ping
