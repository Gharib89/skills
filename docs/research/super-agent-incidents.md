# Research: the incidents behind the super agent's pain points

Researched 2026-11-21 for issue #1311 (map #1310). The question: what actually
happened in the owner's real super-agent runs, for six kinds of failure, what
the skill text said at the time, and what the likely cause was.

Each claim carries its basis:

- **measured**: read from a source on 2026-11-21, with the command or the read
  named.
- **recorded**: a number an earlier retro or audit measured and wrote into an
  issue of this repo. Not measured again here.
- **inferred**: a conclusion drawn from measured facts.
- **guess**: no evidence either way.

## Sources and how they were read

- **The five pinned super-agent sessions**, 2026-11-06 to 2026-11-19, read from
  their Claude Code transcripts with `jq`: every owner-typed message and every
  assistant text, by timestamp, plus the tool calls around each incident. They
  are named S1 to S5 below. Times are UTC.
- **The owner's T3 threads**: `t3_thread_search` for the skill's name and for
  `Handover:` found the pinned threads and three threads about the super agent
  (a retro, an audit, a grill on launch messages). Four were read in small
  slices with `t3_thread_read`; the transcripts above are the same pinned
  threads in full.
- **The ledger** on the super agent's machine: its 116 rulings, 1 open need,
  133 entries and the 127-line archive, read with `jq`.
- **The skill**: `skills/super-agent/` at v0.37.0, and `SKILL.md` at five
  earlier commits (`git show <commit>:skills/super-agent/SKILL.md`).
- **Issues of this repo** that hold earlier measurements: #1128, #1140, #1146,
  #1276 and its sub-issues.

| Session | Dates | Assistant messages | Compactions |
|---|---|---|---|
| S1 | 11-06 to 11-10 | 397 | 10 |
| S2 | 11-10 to 11-13 | 536 | 12 |
| S3 | 11-13 to 11-18 | 264 | 8 |
| S4 | 11-18 to 11-19 | 138 | 3 |
| S5 | 11-19 | 134 | 3 |

All **measured** (`jq` count of assistant text items and of compaction
summaries per transcript). S5 ran the skill at v0.37.0 (**measured**: the
installed copy's `version:` line, and the version the session itself names).

Private repo names, ticket numbers of private repos, thread ids and machine
names are left out. "A consumer repo" is a repo other than this one; "a linked
machine" is a machine other than the super agent's own.

## Summary

| Kind | Dated incidents found | Main cause |
|---|---|---|
| 1. A turn ended with open work and no watcher | 8 where the super agent's own turn died or its watcher was killed, 3 on a linked machine, 2 outside the ledger, 1 task settled early | Script gap: the watcher's restart is the last step of a model turn, and a thread on a linked machine is not read by any script |
| 2. A "why" question answered by an action | 3 of 11 "why" questions, plus 1 question not answered at first | Missing rule |
| 3. An action nobody asked for | 5, plus 5 recorded by the 11-18 audit | Missing rule, and a missing override path (since built) |
| 4. A watch or take-over ask misread | 2 watch asks went badly, both on 11-09; no misread take-over ask found | Script gap in the ledger's kinds (since built), and a rule in prose only |
| 5. A non-ticket ask refused, done inline or mishandled | 7 mishandled or done inline; none refused | Script gap in the ledger's kinds, and a missing rule for what goes inline |
| 6. Over-long messages and noisy pushes | Measured in every session, S5 included | Rule in prose only: scripts print the status, the model still writes around it |

## The incidents

- [Kind 1: a turn that ended with open work and no watcher](super-agent-incidents-watching.md)
- [Kinds 2 to 6: questions answered by an action, unasked actions, watch and
  take-over asks, non-ticket asks, long messages and noisy pushes](super-agent-incidents-asks.md)

## Causes, ranked by how much each changes the design

1. **The watcher's life depends on a model turn finishing** (1a, eight dated
   cases). No wording fixes this. The alarm has to live outside the turn.
2. **A thread on a linked machine is invisible between GitHub events, and its
   state reaches reconcile through a file the model makes** (1b, three cases in
   two days on the newest version).
3. **No rule says a question gets an answer and nothing else, while Escalation
   says "you decide everything else"** (sections 2 and 3). The one time an
   unasked write was stopped, the harness stopped it.
4. **What the super agent tells itself across a compaction is unchecked input**
   (wrong machine key, hand-watch lists, "fix" notes). S1 to S3 compacted 8 to
   12 times each; S4 and S5 still 3 times in about a day.
5. **Entry kinds still missing**: a task that outlives its first rest, a
   schedule-started thread, a recurring check.
6. **The model composes every message**, so noise survives each script that
   prints the status.

## Not found

- A misread take-over ask (`pause` has never been used).
- A refused non-ticket ask.
- A plain test-run ask that went badly.
- An invented answer to a "why" question.

## Limits

- The incident counts are a floor: they come from owner messages that show a
  problem, so a miss the owner did not mention is not counted.
- Watcher gaps after a host restart are bounded by message times, not by the
  restart time, which no source read here holds.
- The **recorded** numbers were not measured again.
- The supervised threads themselves were not read, only the pinned sessions.
