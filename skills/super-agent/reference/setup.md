# Setup

## Contents

- [Steps](#steps)
- [Re-runs](#re-runs)

The fleet file is defined in SKILL.md's `## Setup`; `scripts/` is under this
skill's base directory.

## Steps

1. Run `scripts/setup.sh --propose`. Its `to_probe` lists each reachable
   linked machine as `{machine, environment_id}`.
2. Launch one **probe thread** per `to_probe` row, all at once, with
   `t3_thread_launch`: `environmentId` set, `scratch: true`, no worktree, the
   cheapest tier (`modelSelection` `{instanceId: <claude instance>, model:
   <sonnet>, options: [{"id":"effort","value":"low"}]}`). Its message is one
   line asking it to run the script below with `bash -s -- --json` and reply
   with its one JSON line and nothing else, then the full text of
   `scripts/probe.sh` in a code fence: that machine has no checkout of this
   repo. `t3_thread_wait`
   each, read its reply with `t3_thread_read` (`limit` 2), save it to a file,
   and settle the thread (`t3_thread_organize` action `settle`) as soon as its
   reply is read. A probe thread is no ledger entry and takes no slot. Measured
   2026-11-06: one replied in 15 to 20 s.
3. Run setup again with `--propose` and one `--probe <environment id>=<reply
   file>` per machine, and show the owner its proposal: each machine's slots,
   the thresholds, the `work_week` (weekday numbers in week order, 0 is
   Sunday; proposed Monday to Friday), each provider marked `unavailable`
   with its `reason`, and every line of `warnings` (a reply that is no probe
   lands there).
4. Ask the owner to confirm or adjust it, the `work_week` set to their own
   working days (the morning report and the retro follow it). After the yes,
   run it again with `--write` and the same `--probe` flags, then apply the
   owner's adjustments by editing the written file.
5. Tell the owner to keep the fleet file in their dotfiles, so every machine a
   super agent may start on has it.

## Re-runs

Setup runs only here, on the super agent's machine. The owner edits the file by
hand for anything setup proposed (slots, thresholds, active repos, waivers,
`work_week`); a re-run keeps those edits for a machine probed before and
refreshes only the probed facts (`proposed_slots` shows what a fresh measure
would set), while a machine never probed takes the computed slots. An
unreachable machine keeps its previous facts and is probed on the next setup
that finds it reachable. An `unavailable` provider is a fact to report, not an
error: name it with its reason and carry on.
