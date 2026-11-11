# Setup

## Contents

- [Steps](#steps)
- [Cursor and Grok](#cursor-and-grok)
- [Fleet brief lines](#fleet-brief-lines)
- [Re-runs](#re-runs)

The fleet file is defined in SKILL.md's `## Setup`; `scripts/` is under this
skill's base directory.

## Steps

1. Call `orchestrator_capabilities` and save its answer to a file, then run
   `scripts/setup.sh --propose --instances <file> --settings <settings>`;
   pass both to every later `--propose` and `--write` too. `<settings>` is T3's
   own `settings.json` in its userdata directory: a capabilities row has no
   home path, so each Claude instance's account directory is read from it.
   Its `to_probe` lists each reachable linked machine as `{machine,
   environment_id}`.
2. Launch one **probe thread** per `to_probe` row, all at once, with
   `t3_thread_launch`: `environmentId` set, `scratch: true`, no worktree, the
   cheapest tier. With a fleet file, take `modelSelection` from route
   (`quota.sh`, then `route.sh --size XS`: its `instance_id`, `model`,
   `options`); on a first setup, use the first enabled Claude instance in the
   capabilities answer, its Sonnet model and effort low, as that answer names
   them. Its message is one
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
   Sunday; proposed Monday to Friday), each of `instances` with its driver,
   instance id, quota source and auth result, each provider marked
   `unavailable` with its `reason` (a `cursor` or `grok` instance is `unknown`,
   not `unavailable`: no CLI prints its usage, `grok usage` points to `/usage`
   inside grok; grok's auth is read by grepping `grok models`; a `cursor`
   instance's is T3's row alone, empty `constraints` is `ok`, because `agent` on
   PATH can be the Grok binary),
   and every line of `warnings` (a reply that
   is no probe lands there; so does a Claude instance with no
   `env.CLAUDE_CONFIG_DIR`: with none it reads the default account, so each
   extra account needs its own).
   Each provider carries `weekly_weight` 1 and the file `five_hour_floor` 0.1
   and `weekly_reserve` 0.05. Ask the owner for each instance's weight: the
   number of times larger its weekly quota is than their smallest instance's
   (40% of a seat three times the size is more work than 60% of the small
   one), and whether to change the floor and the reserve, fractions under
   which route skips an instance.
4. Ask the owner to confirm or adjust it, the `work_week` set to their own
   working days (the morning report and the retro follow it). After the yes,
   run it again with `--write` and the same `--probe` flags, then apply the
   owner's adjustments by editing the written file.
5. Tell the owner to keep the fleet file in their dotfiles, so every machine a
   super agent may start on has it.

## Cursor and Grok

They are for side tasks (code review, focused research, probes), so an unnamed
launch never picks one unless the owner allows it. No CLI prints their usage, so
`route.sh` treats a signed-in `cursor` or `grok` instance whose fleet entry sets
`route: true` as a last resort for any launch: picked only when no Claude or
allowed Pi instance can launch. Without `route: true` it is off. The other way
in is the owner naming it (`--instance <id>`), which routes to it with `route`
unset. A null
`model` in its answer (also `wanted_model`, `options`) means omit that key from
`modelSelection` and launch on the instance's own default; map a tier to a
model in the fleet file's `models` to choose one.

## Fleet brief lines

Setup does not write these; the owner adds them by hand. A `repos` object keys
each repo by `<owner/name>`, and an entry holds two optional keys:

- `max_ships`: a whole number of at least 1, the **ship cap**. At most this many
  tickets of the repo run at once, counting every open one, ship and triage, on
  every machine. 3 when unset. A launch over it waits, the cap in its reason; a
  value that is not a whole number at least 1 is a tooling error.
- `brief`: an array of text lines every launch brief for that repo carries.

A machine entry takes the same `brief` array, carried by every launch placed on
that machine. A launch brief prints the lines that match its repo and machine
under `Lines for this repo and machine:`. A one-off ruling is scoped the same
way: `ledger.sh ruling <text> --brief --repo <r> --machine <m>`.

## Re-runs

Setup runs only here, on the super agent's machine. The owner edits the file by
hand for anything setup proposed (slots, thresholds, active repos, waivers,
`work_week`); a re-run keeps those edits for a machine probed before and
refreshes only the probed facts (`proposed_slots` shows what a fresh measure
would set), while a machine never probed takes the computed slots. An
unreachable machine keeps its previous facts and is probed on the next setup
that finds it reachable. An `unavailable` provider, or an instance whose
`auth` is `failed`, is a fact to report, not an error: name it with its reason
and carry on. A recorded `failed` carries `auth_source` and `auth_checked`:
`quota.sh` honors only a T3-sourced one under 24 h old, so an instance that
signed back in routes again without a hand edit. Setup runs on Linux only
(GNU `nproc`, `free`, `timeout`).
