---
name: drive-session
description: >-
  Supervise Claude sessions in Herdr tabs and answer what they ask. Use when
  the user wants sessions driven in Herdr: a batch of `/ship` runs, or a skill
  smoke test in another checkout. Needs HERDR_ENV=1.
metadata:
  version: 0.5.0
---

# drive-session

You are the **supervisor**: the main agent driving the run. Each **supervised
session** is one claude agent in a Herdr tab you created, beside your own tab
in your workspace. The **roster** is the file listing them.

Herdr is this skill's subject: the skill needs herdr 0.9.3 or newer.

## The scripts

They live in `scripts/` under this skill's base directory, and each answers
`--help` with its flags and the JSON it prints. Every script but `frontier`
takes the roster by `--roster <file>`. Read, wait on and answer a roster session
through `spawn`, `watch`, `read` and `answer` alone: each keeps the row's
sequence number, which is what tells Herdr's stale `done` from a new turn.

- `spawn` opens the tab without focus, starts claude, sends the task and adds
  the row.
- `watch` blocks until one session has an **event**, prints it and exits:
  `done`, `idle` or `blocked` past its `seen_seq`, or `gone` (the agent exited
  or its pane closed).
- `read` prints the session's last 40 lines and acknowledges its event. When
  they open mid-message (a summary or question cut at the top), read again
  with `--lines 200`. `--rest` also marks the row at rest (see The merge
  allowance below).
- `answer` sends a prompt with `--text`, or presses keys into a dialog with
  `--keys`.
- `frontier --parent <n>` prints a spec parent's sub-issues, lowest number
  first, each with its `repo`, state, assignees and open blockers, a blocker
  carrying its `repo` and marked `inside` when it is another sub-issue of the
  same parent. Run it from the spec's checkout, or with `GH_REPO=<owner/name>`:
  it reads the parent from that repo. It reads GitHub alone (an Azure DevOps
  checkout has no spec batch), so it takes no roster and runs outside Herdr.

## The run

1. **Roster.** One per run, in your scratchpad:
   `<scratchpad>/drive-session/roster.json`. Read it back after a compaction.
2. **Spawn** each session. Name it after its task (`ship-541`), the name
   doubling as the tab label. `--cwd` is a folder Claude Code already trusts:
   in any other, claude stops on the trust dialog, `spawn` answers
   `"prompted": false`, and `watch` reports the dialog as `blocked`. Answer it
   with keys, and once `watch` reports the session `idle`, send the task as
   `answer` text. `--model` takes the user's choice: a cheap model for a smoke
   test, the default for a ship run.
3. **Watch.** Run `watch --roster <file> --timeout 1500000` with the Bash
   tool's `run_in_background`, then end your turn. Its exit wakes you; a poll
   or a sleep of your own spends context on nothing. The timeout keeps it under
   the background command's own time limit: a `timeout` answer, or an exit
   with no output, means start step 3 again. A timeout lists each live
   session's `status` and `still_s`, the seconds its sequence number stood
   still during that watch, then each row marked at rest as `at-rest`. One
   `working` or `unknown` with `still_s` over 1200
   (of the 1500 s timeout) gets a `read`, handled as step 5 would, before the
   next watch.
4. **Read** the session it names with `read`, every time, before deciding.
5. **Decide**, by the event:
   - `done` or `idle`: the turn ended and the session waits at its prompt
     (Herdr reports a finished turn as either). Judge from the output whether
     the task is at rest (a smoke test's verdict) or wants a next prompt. A
     ship run's merge summary, a hand-off, or a question ending the turn is a
     stop: take it to the escalation list below.
   - `blocked`: a dialog. A **permission dialog** is titled by a tool
     (`Bash command`), shows the call, and asks "Do you want to proceed?" over
     Yes and No options; a **question dialog** (AskUserQuestion-style) shows
     the session's own question and its options. Answer a question dialog
     from the session's context and the user's rules (CLAUDE.md,
     `~/.claude/rules/`), and take any other to the escalation list below.
   - `gone`: record it as crashed.
6. **Answer** with `answer`: `--keys` for a dialog (a numbered option such as
   `1`, then `Enter`; `esc` to back out), `--text` at a prompt (`--text=<t>`
   for text opening with `-`). Text that starts no turn (a local slash
   command such as `/rename`, or an Enter that did not register) comes back
   from `answer` or `spawn` as a not-ok answer with `code`
   `agent_prompt_stalled` or `timeout`. The text reached the pane, and `watch`
   will not report the session until something starts a turn, so `read` it:
   text still in the input box gets `--keys Enter`; a session back at its
   prompt gets its next `--text`.
7. **Loop** from step 3 while any session is running. A session waiting on an
   escalation is idle but not marked at rest; once you relay the user's reply,
   it runs again, so start step 3 again. When `watch` exits 1 on no live
   session, every session is gone or marked at rest: report.

## Escalation

An **escalation** forwards a session's question or stop to the user, whether
it came as a dialog (`blocked`) or a turn ending on it (`done`, `idle`).
Escalate exactly these, and answer everything else yourself:

- a merge gate, unless the launch prompt granted the merge allowance and the
  gate is clean or held only by reviewer rules the merge allowance answers;
- an approval for a destructive or irreversible command;
- every permission dialog (step 5; the startup trust dialog of step 2 is not
  one): the session's own permission system held that call for the owner, and
  approving it with keys would launder that permission through you;
- a fork in scope, schema or architecture.

An escalation names the session, quotes its question, and carries your proposed
answer, so the user can reply in one word. Relay the reply with `answer` to that
session. While it waits, keep watching the others.

The **merge allowance** is the launch prompt's permission to merge on a clean
gate, or one held only by the reviewer rules below ("merge each if all OK"). A
ship profile's `Merge: on-clean-gate` is not a
merge allowance: a run stopped at its gate there is any other merge gate. A
run whose summary reports the PR merged is at rest, with nothing left to
answer: read it with `--rest`, so `watch` stops waking on its idle compaction
and a timeout still lists it. Use `--rest` on a finished task (a merged PR, a
smoke test's verdict) and never on a session waiting on an escalation, which
runs again once you relay the reply. Ship decides clean, not you: at the gate,
ask the session with `--text` to run `run-file gate clean` for its run and
report the answer. Answer `--text merge` on `clean: true` with no unmet
criterion in the summary.

A gate that is not clean is still yours to decide when the summary names no
unmet criterion and every `held_by` entry is one of these three, and no other
`reviewer <x>:` entry (`not landed`, `no dispositioned round`, a stale `tree
unchanged`) qualifies:

- `reviewer <x>: past cap <n>, local review read <sha>, no host reviewer read
  it`: a reviewer capped, and a local review read the final head and stopped on
  `tree unchanged`. Answer `--text merge`.
- `reviewer <x>: small lane`: a host round read an earlier head. Ask the session
  with `--text` for one more host round on the final head, and answer
  `--text merge` once it stops on `tree unchanged`.
- `reviewer <x>: cap` (several such entries may stand together, one per
  reviewer): the same one more host round, and the same answer.

A round that stops on findings or on cap again, any other `held_by` entry, and
every unmet criterion are escalations that quote the `held_by`: a criterion
waiver comes from the owner, and the auto-mode classifier refuses one the
supervisor relays.

## Supervised ship runs

A supervised `/ship` is an **attended** run: you are the human present. Launch
it as `/ship <issue>`, leaving `--unattended` to the user alone, and answer its
hand-offs and questions the way the user would, by the escalation list.

After every merge, `git status` the main checkout, then `git pull --ff-only`
there before the next spawn: sessions start there, and its `.claude/skills/`
is what runs, so a stale main runs the previous skills and branches from old
code. On a dirty tree or a refused pull, spawn nothing: tell the user what
`git status` or the pull printed, and wait for their word.

## Spec batch

A **spec batch** drives one spec parent's sub-issues (its **slices**, joined
by native blocking edges) to merge, each as a supervised ship run. The launch
line names the parent and any merge allowance
(`spec batch #<parent>, merge each if all OK`).

1. **Launch turn.** Run `frontier --parent <n>` and post its frontier, a slot
   plan (which slices run side by side, which wait, and why; it names each
   run-alone timing slice with its reason), and, when a slice
   has a blocker outside the spec, one question proposing to add the blocker's
   spec to the batch. Then end the turn: spawn nothing until the user's go. On
   a yes, run `frontier` on that spec's parent too and plan both together. On
   a "no", those slices stay blocked, the parent stays open, and both go in the
   report.
2. **Slots.** At most two ship runs at once. Take open, unblocked slices
   lowest number first, skipping one assigned with no run of yours in the
   roster (another run's claim), and pair two only when no blocking edge joins
   them and the areas their agent briefs name do not overlap: a skill
   directory, the repo's scripts, its tests, the glossary, its docs. That call
   is yours, from reading each agent brief. A slice whose agent brief names no
   area runs alone: it starts only when no other run holds a slot. A slice
   whose acceptance criteria require a timing series (repeated A/B runs, a
   median and range) also runs alone: a second run beside it widens the range.
   It starts only once no other run holds a slot and no triage tab that runs
   the local gate is still running; until it is at rest no second slot is taken
   and no triage tab that runs the local gate is spawned (a triage tab that
   runs no local gate may still spawn; the local gate is the repo's own full
   check, the one a ship run makes before it opens its PR). A slot frees only
   when its run is at rest (merged, handed back or crashed): a run waiting on
   an escalation keeps it. The gate slice, blocked by every other slice,
   starts once all of them are closed. Before spawning a slice, list the PRs
   merged to main since its agent brief was posted (the brief comment's
   `created_at`, then `gh pr list --state merged --base main --limit 1000
   --search "merged:>=<date>"`, a full 1000 rows being truncated: narrow the
   date) and compare their changed files with the areas the brief names: on an
   overlap, the spawn prompt gains one line telling the run to re-check the
   brief against main in phase 1, naming those PRs, since a brief written
   before a merge can describe code that has moved.
3. **Merges.** The launch line's merge allowance covers every PR in the spec,
   on Ship's own `run-file gate clean` and the reviewer-rule holds the merge
   allowance answers, as Escalation says. After
   each merge, fast-forward main as above, then re-run `frontier`.
   Once no slice is open, close the parent as completed with a comment naming
   each slice and its PR: ship closes only the issue its PR names.
4. **Batch log.** `<scratchpad>/drive-session/batch-log.md`, beside the
   roster and read back with it after a compaction. A **find** is anything a
   run surfaced beyond its own task: an escalation, a reviewer quirk, a
   classifier refusal, a gate gap. Write one line per find as it surfaces,
   before the next `watch`, naming the run, what happened, and whether it would
   recur in the runs still to come. File a recurring find as an issue, spawn a
   `/triage <n>` tab on it (a triage tab takes no slot), then ship it as the
   next run in a free slot, before any slice it would hit.
5. **End.** When every reachable slice is at rest, report one row per slice
   (resting state and PR link), in place of The report's rows, plus each slice
   left blocked and why. Then draft the rest of the batch log as one retro
   spec, a parent with PR-sized sub-issues, show it, and file it only on the
   user's word.

Wake only on The run's background `watch`, never on `/loop` or a schedule.

## The report

When every session is at rest, report one row per session: its name, its task,
and its resting state (merged, at the merge gate, handed back, escalated and
waiting, or crashed), with the PR link where there is one. To answer "what is
`<name>` doing?" mid-run, `read` it, summarize, and handle what it shows as
step 5 would: that `read` acknowledges any event `watch` had not yet reported.

Leave every supervised tab open, so the user can read each transcript. Close a
tab only when the user asks.
