# Super-agent incidents: turns that ended with no watcher

Part of [the incident research](super-agent-incidents.md), which holds the
sources, the basis labels (measured, recorded, inferred, guess), the session
table (S1 to S5) and the ranked causes.

## 1. A turn that ended with open work and no watcher

**What the skill said.** "No turn ends without a watcher running while the
ledger holds an open entry" is in `SKILL.md` at every commit read, from
2026-11-09 (v0.9.1) to v0.37.0 (**measured**: `git show` and `grep` at five
commits). It has always been prose. Nothing outside the model's turn starts the
watcher, and no hook checks for one (**measured**: `grep -n hook` over
`SKILL.md` and `reference/` finds only the guard hook, which protects three
state files).

### 1a. The super agent's own turn died, so nothing restarted the watcher

The watcher exits to wake the super agent, and starting it again is the last
step of that wake's turn. A turn that does not finish leaves no watcher.

| Date (UTC) | What ended the turn | Time with no watcher | Basis |
|---|---|---|---|
| 11-13 09:47 | A provider authentication error (HTTP 403) was the turn's whole reply | 20 min, until the owner wrote a greeting at 10:07. Two merges and one failed supervised thread were waiting | measured: S2 transcript |
| 11-12 16:09 | The super agent's own 5 hour usage limit | about 1 min (the reset was at 16:10) | measured: S2 |
| 11-13 06:40 | Usage limit | 30 min | measured: S2 |
| 11-13 11:41 | Usage limit | 29 min | measured: S2 |
| 11-18 09:41 | Weekly usage limit | 19 min | measured: S4 |
| 11-18, before 16:01 | The host restarted and cancelled the background watcher. The harness note says the shell "will not report back" | unknown; the previous message was at 15:42 | measured: S4 |
| 11-19, before 16:25 | Host restart, watcher cancelled | unknown; previous message 16:13. The owner's next message was a complaint that a thread had not been checked | measured: S5 |
| 11-19, before 18:12 | Host restart, watcher cancelled | up to 46 min; previous message 17:26, and the hourly backstop was the next wake | measured: S5 |

Cause: **script gap**. The rule cannot be kept by the party it is addressed to,
because in all eight cases that party was not running. The `notify` command
(v0.20.0) is the one alarm outside the loop, and it fires only after a watcher
exits on an event, so a cancelled watcher never arms it (**inferred** from
`reference/watching.md`).

The 11-10 retro also records "a stopped super agent was silent for three days"
(**recorded**: #1140). S1's transcript has no message between 11-06 17:52 and
11-09 08:53 (**measured**).

### 1b. A thread on a linked machine rested and no script could see it

`watch.sh` wakes a remote entry "from GitHub alone" (PR opened, checks finished,
merged, closed), and "the thread's own finish is read on a wake"
(`reference/watching.md`, `reference/remote.md`). A remote thread that rests
without one of those four events wakes nothing.

- **11-18 07:37.** Ten minutes after three triage threads launched on a linked
  machine, the owner told the super agent that one had completed, and the super
  agent then launched its ship (**measured**: S3). A triage run that ends by
  changing labels raises none of the four events (**inferred**).
- **11-19 20:20.** The owner told the super agent a ship ticket had finished.
  The thread had reached its merge gate on the linked machine and was waiting;
  the super agent then ruled on the hold (**measured**: S5).
- **11-19 16:25.** The owner asked why a linked-machine ship thread had not been
  checked. It had rested at its merge gate about 20 minutes earlier. The super
  agent's account: it had given reconcile a status file it wrote by hand, so
  reconcile kept reading the thread as running (**measured**: S5 message).
  Checked against the tool calls: at 15:48 it built the reply files with
  `jq -n` in a shell function, and reconcile and pulse ran at 15:59, 16:08 and
  16:12 against that directory with no new thread read (**measured**: S5 Bash
  calls). The skill text at the time: "`reply.sh` is the only way to write one
  ... Never write, edit or patch one yourself" (`reference/remote.md`, since
  v0.28.0 on 11-18).

Cause: **script gap** for the first two (no script can read a remote thread, so
a gate hold there waits for the hourly backstop), and **rule in prose only**
for the third. The guard hook covers the ledger, fleet and quota files, not
reply files, and reconcile accepts a reply file of any age and origin
(**measured**: `scripts/guard.sh` header). The super agent's own fix was a line
in its notes "for after the context reset" (**measured**: S5), which is prose
again.

### 1c. Work the ledger could not hold (mostly built since)

- **11-09 11:40 to 11:57.** The owner saw many finished threads in the T3 list
  and asked the super agent to check them; it then settled five. Asked why it
  missed a grill, it explained: the ledger had no kind for a grill, so it was
  recorded as a triage entry, reconcile settled it at its first rest, a settled
  entry is never read again, and the PR the grill opened later merged unseen
  (**measured**: S1). The rule's letter held (no open entry, so no watcher was
  owed). At 09:06 the same day it reported "watcher: off" while it alone was
  checking an owner-run thread by hand (**measured**: S1). The owner then ruled
  that every launched thread stays watched, even after the owner steps in
  (**measured**: ledger ruling of 11-09). Fixed by #1128 (v0.12.0) and #1146
  (v0.17.0).
- **11-06 to 11-10, recorded.** 13 launches of other kinds, 8 tickets shipped on
  a linked machine with no ledger entry, a merge gate that sat 37 minutes
  unseen, and a hand watcher that died at the 2 hour background limit
  (**recorded**: #1146).
- **11-12 08:03 to 08:15.** The super agent said three retro threads were
  settled; the owner's screenshot showed they were not. They were threads a
  schedule had started, not the ones it had settled, and it said it had missed
  them (**measured**: S2). A thread started by a schedule still has no entry
  (**inferred**: `reference/lessons.md` schedules the retro-runs, and nothing
  records their threads).
- **11-13 10:10 and 12:58, 11-13 03:05.** The owner sent screenshots of the T3
  list and asked the super agent to check or settle the threads in them
  (**measured**: S2, S3). The T3 list, not the super agent, was the owner's
  alarm.

Cause: **script gap** in the ledger's kinds, closed for launched tasks and
adopted threads by v0.17.0. Still open: schedule-started threads, and 1d.

### 1d. A task entry settles at its thread's first rest

One long task on a linked machine was added to the ledger four times, as
`task:<slug>`, `-b`, `-c` and `-d`, because "the automatic check had marked the
thread finished" while the owner was still sending it rulings (**measured**:
the four ledger keys, and the S3 message of 11-15 12:45). The skill says a task
entry is "settled once the thread has run and is at rest" (`reference/watching.md`).
Cause: **script gap**. Only a grill has the `interactive` flag that keeps an
entry past its first rest.
