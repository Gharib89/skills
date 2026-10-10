---
name: drive-session
description: >-
  Supervise Claude sessions in Herdr tabs and answer what they ask. Use when
  the user wants sessions driven in Herdr: a batch of `/ship` runs, or a skill
  smoke test in another checkout. Needs HERDR_ENV=1.
metadata:
  version: 0.1.0
---

# drive-session

You are the **supervisor**: the main agent driving the run. Each **supervised
session** is one claude agent in a Herdr tab you created, beside your own tab
in your workspace. The **roster** is the file listing them, so a
compaction or a resumed supervisor still knows which sessions it owns.

Herdr is this skill's subject: every script refuses to run without
`HERDR_ENV=1`, and needs herdr 0.9.3 or newer. Install it with
`npx skills add Gharib89/skills --skill drive-session --agent claude-code -y`.

## The four scripts

They live in `scripts/` under this skill's base directory, each taking the
roster by `--roster <file>`, and each answers `--help` with its flags and the
JSON it prints. Read, wait on and answer a roster session through them alone:
each keeps the row's sequence number, which is what tells Herdr's stale `done`
from a new turn.

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
   doubling as the tab label, one spawn at a time, since each rewrites the
   roster. `--cwd` is a folder Claude Code already trusts: in any other, claude
   stops on the trust dialog, `spawn` answers `"prompted": false`, and `watch`
   reports the dialog as `blocked`. Answer it with keys, and once `watch`
   reports the session `idle`, send the task as `answer` text. `--model` takes
   the user's choice: a cheap model for a smoke test, the default for a ship
   run.
3. **Watch.** Run `watch --roster <file> --timeout 1500000` with the Bash
   tool's `run_in_background`, then end your turn. Its exit wakes you; a poll
   or a sleep of your own spends context on nothing. The timeout keeps it under
   the background command's own time limit: a `timeout` answer, or an exit
   with no output, means start step 3 again.
4. **Read** the session it names with `read`, every time, before deciding.
5. **Decide**, by the event:
   - `done` or `idle`: the turn ended and the session waits at its prompt
     (Herdr reports a finished turn as either). Judge from the output whether
     the task is at rest (a smoke test's verdict) or wants a next prompt. A
     ship run's merge summary, a hand-off, or a question ending the turn is a
     stop: take it to the escalation list below.
   - `blocked`: a question or permission dialog. Answer it from the session's
     context and the user's rules (CLAUDE.md, `~/.claude/rules/`), or
     escalate it when the escalation list below names it.
   - `gone`: record it as crashed.
6. **Answer** with `answer`: `--keys` for a dialog (a numbered option such as
   `1`, then `Enter`; `esc` to back out), `--text` at a prompt (`--text=<t>`
   for text opening with `-`). `answer` refuses text to a blocked session,
   since Herdr would refuse it too.
7. **Loop** from step 3 while any session is running. A session waiting on an
   escalation is at rest; once you relay the user's reply, it runs again, so
   start step 3 again. When `watch` exits 1 on no live session, every session
   is gone: report.

## Escalation

An **escalation** forwards a session's question or stop to the user, whether
it came as a dialog (`blocked`) or a turn ending on it (`done`, `idle`).
Escalate exactly these, and answer everything else yourself:

- a merge gate, unless the launch prompt granted the merge allowance and the
  gate is clean;
- an approval for a destructive or irreversible command;
- a fork in scope, schema or architecture.

An escalation names the session, quotes its question, and carries your proposed
answer, so the user can reply in one word. Relay the reply with `answer` to that
session. While it waits, keep watching the others.

The **merge allowance** is the launch prompt's permission to merge on a clean
gate ("merge each if all OK"). Ship decides clean, not you: at the gate, ask
the session with `--text` to run `run-file gate clean` for its run and report
the answer. Answer `--text merge` only on `clean: true` with no unmet criterion
in the summary; anything else is an escalation that quotes its `held_by`.

## Supervised ship runs

A supervised `/ship` is an **attended** run: you are the human present. Launch
it as `/ship <issue>`, leaving `--unattended` to the user alone, and answer its
hand-offs and questions the way the user would, by the escalation list.

## The report

When every session is at rest, report one row per session: its name, its task,
and its resting state (merged, at the merge gate, handed back, escalated and
waiting, or crashed), with the PR link where there is one. To answer "what is
`<name>` doing?" mid-run, `read` it, summarize, and handle what it shows as
step 5 would: that `read` acknowledges any event `watch` had not yet reported.

Leave every supervised tab open, so the user can read each transcript. Close
only a tab you created, and only when the user asks.
