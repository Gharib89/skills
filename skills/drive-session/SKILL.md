---
name: drive-session
description: >-
  Supervise Claude sessions in Herdr tabs: spawn one or more, watch them with
  one background wait, answer or escalate what they ask, report each outcome.
  Use when the user asks to run, babysit or drive sessions in Herdr (a batch of
  `/ship` runs, a skill smoke test in another checkout). Needs HERDR_ENV=1.
metadata:
  version: 0.1.0
---

# drive-session

You are the **supervisor**: the main agent driving the run. Each **supervised
session** is one claude agent in a Herdr tab you created, beside your own tab
in your workspace. The **roster** is the run's file listing them, so a
compaction or a resumed supervisor still knows which sessions it owns.

Herdr is this skill's subject: every script refuses to run without
`HERDR_ENV=1`, and needs herdr 0.9.3 or newer. Install it with
`npx skills add Gharib89/skills --skill drive-session --agent claude-code -y`.

## The four scripts

They live in `scripts/` under this skill's base directory, each taking the
roster by `--roster <file>`, and each answers `--help` with its flags and the
JSON it prints. They are the only way to touch a roster session: each one keeps
the row's `seen_seq`, the agent's `state_change_seq` when you last looked.
Herdr reports the previous turn's `done` until the next turn starts, and the
sequence number is what tells that stale `done` from a new one.

- `spawn <name> --roster <file> --cwd <dir> --prompt <text> [--model <m>]`
  opens the tab without focus, starts claude, sends the task and adds the row.
- `watch --roster <file>` blocks until one session has an **event**, prints it
  and exits: `done`, `idle` or `blocked` past its `seen_seq`, or `gone` (the
  agent exited or its pane closed).
- `read <name> --roster <file>` prints the session's recent output and
  acknowledges its event.
- `answer <name> --roster <file> --text <t>` sends a prompt;
  `answer <name> --roster <file> --keys <k>...` presses keys into a dialog.

## The run

1. **Roster.** One per run, in your scratchpad:
   `<scratchpad>/drive-session/roster.json`. Read it back after a compaction.
2. **Spawn** each session. Name it after its task (`ship-541`), the name
   doubling as the tab label. `--cwd` is a folder Claude Code already trusts:
   in any other, claude stops on the trust dialog, and `spawn` answers
   `"status": "blocked", "prompted": false`. Answer that dialog with keys, and
   once `watch` reports the session `idle`, send the task as `answer` text.
   `--model` takes the user's choice: a cheap model for a smoke test, the
   default for a ship run.
3. **Watch.** Run `watch --roster <file>` with the Bash tool's
   `run_in_background`, then end your turn. Its exit wakes you; a poll or a
   sleep of your own spends context on nothing.
4. **Read** the session it names with `read`, every time, before deciding.
5. **Decide**, by the event:
   - `done`: the turn ended. Judge from the output whether the task is at
     rest (a ship run's merge summary, a hand-back, a smoke test's verdict) or
     wants a next prompt.
   - `blocked`: a question or permission dialog. Answer it from the session's
     context and the user's rules (CLAUDE.md, `~/.claude/rules/`), or
     escalate it when the escalation list below names it.
   - `idle`: the session waits at its prompt. Send what it waits for.
   - `gone`: the agent exited or its pane closed. Record it as crashed.
6. **Answer** with `answer`: `--keys` for a dialog (a numbered option such as
   `1`, then `Enter`; `esc` to back out), `--text` at a prompt. `answer`
   refuses text to a blocked session, since Herdr would refuse it too.
7. **Loop** from step 3 until every session is at rest, then report.

## Escalation

An **escalation** forwards a blocked session's question to the user. Escalate
exactly these, and answer everything else yourself:

- a merge gate, unless the launch prompt granted the merge allowance and the
  gate is clean;
- an approval for a destructive or irreversible command;
- a fork in scope, schema or architecture.

An escalation names the session, quotes its question, and carries your proposed
answer, so the user can reply in one word. Relay the reply with `answer` to that
session. While it waits, keep watching the others.

The **merge allowance** is the launch prompt's permission to merge on a clean
gate ("merge each if all OK"). A gate is clean when the session's merge summary
shows CI green and lists no unmet criterion and no finding left open; then
answer the gate with `--text merge`.

## Supervised ship runs

A supervised `/ship` is an **attended** run: you are the human present. Launch
it as `/ship <issue>`, leaving `--unattended` to the user alone, and answer its
hand-offs and questions the way the user would, by the escalation list.

## The report

When every session is at rest, report one row per session: its name, its task,
and its resting state (merged, at the merge gate, handed back, escalated and
waiting, or crashed), with the PR link where there is one. To answer "what is
`<name>` doing?" mid-run, `read` it and summarize.

Leave every supervised tab open, so the user can read each transcript. Close
only a tab you created, and only when the user asks.
