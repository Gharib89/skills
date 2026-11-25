# Setup

## Contents

- [Steps](#steps)
- [The guard hook](#the-guard-hook)
- [Cursor and Grok](#cursor-and-grok)
- [Fleet repo entries](#fleet-repo-entries)
- [Fleet keys the owner sets](#fleet-keys-the-owner-sets)
- [The super agent's own tier](#the-super-agents-own-tier)
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
   (`quota.sh`, then `route.sh --size XS --quota <file>`, `<file>` the saved
   quota read: its `instance_id`, `model`, `options`); on a first setup, use the
   first enabled Claude instance in the capabilities answer, its Sonnet model
   and effort low, as that answer names them. Its message is one line asking it
   to run the script below with `bash -s -- --json` and reply with its one JSON
   line and nothing else, then the full text of `scripts/probe.sh` in a code
   fence: that machine has no checkout of this repo. `t3_thread_wait` each, read
   its reply with `t3_thread_read` (`limit` 2), save it to a file, and settle
   the thread (`t3_thread_organize` action `settle`) as soon as its reply is
   read. A probe thread is no ledger entry and takes no slot. Measured
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
   which route skips an instance. Each Claude instance carries `models`, its
   `sonnet` and `opus` keys the exact model ids its capabilities row lists
   (for example `claude-sonnet-5-5`): route launches on these, and on the
   tier's alias only where `models` names none. A re-run keeps the file's own
   `models`, like every value already there, so after a model release edit
   `models` to the new ids.
4. Ask the owner to confirm or adjust it, the `work_week` set to their own
   working days (the morning report and the retro follow it). After the yes,
   run it again with `--write` and the same `--probe` flags, then apply the
   owner's adjustments by editing the written file.
5. Tell the owner to keep the fleet file in their dotfiles, so every machine a
   super agent may start on has it. Setup records this machine's `hostname` in
   its entry, and `launch` takes as `--machine` only the key whose entry holds
   the hostname of the machine it runs on (the key itself where an entry
   records none): any other key is a tooling error and launches nothing.
6. Read `home` in the `--write` answer ([the guard hook](#the-guard-hook)):
   tell the owner each of its `needs` lines and, unless `t3_project_list`
   already shows a project whose workspace is its `folder`, to create one
   there once, in full access. The next daily handover
   launches the super agent there.

## The guard hook

`setup.sh --write` and every daily handover rewrite the **super agent
folder**'s generated `.claude/settings.local.json` (`super-agent/home` under
`$XDG_STATE_HOME`, `~/.local/state` when unset): its PreToolUse entry is
the state guard, `scripts/guard.sh`, which refuses
a hand write to the ledger, fleet or quota file (an Edit, a Write, a
redirection or an `mv`) and names the script to use, and its Stop entry is the
watch guard, `scripts/watch-guard.sh`, which refuses a turn end once while
`watch.sh --ledger <ledger> --owed` says a watcher is owed and names the
command to run (it logs each block and pass to `watch-guard.jsonl` beside the
ledger). Its command ends `|| true`, since a Stop hook's exit 2 blocks the
stop and the guard's usage error must never do that. The file is generated
whole, so a hand edit there is lost on the next rewrite. A refusal means an
override has no flag yet: report it to the owner, never work around it. Only
the pinned thread runs in that folder, so the hook reaches no other session.

`scripts/guard.sh --status` reads that file: `installed` is `true` when it
holds the entry for this copy of the script, and `stale` lists each guard
entry an older install left in `~/.claude/settings.json`, the line the owner
removes there (it would fire in every session); `stale.unreadable` is true
when that file is no JSON object, so no entry could be checked. Each is also a
`needs` line in `home`. Run `--install` only when a `needs` line names the
missing hook: it adds the entry to the folder's file, or to the file
`--settings` names.

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

## Fleet repo entries

Setup does not write these; the owner adds them by hand. A `repos` object keys
each repo by `<owner/name>`, and an entry may hold, beside a machine pin
([placement](placement.md)):

- `max_ships`: a whole number of at least 1, the **ship cap**. At most this many
  tickets of the repo run at once, counting every open one, ship and triage, on
  every machine. 3 when unset. A launch over it waits, the cap in its reason; a
  value that is not a whole number at least 1 is a tooling error.

No line in the fleet file reaches a supervised thread: its launch message is the
invocation, a `/triage` thread's contract line and an optional note
([step-ins](step-ins.md#the-launch-message)).

## Fleet keys the owner sets

Each is optional: a fleet file without it keeps the default.

- `merge_gate_ruler`: `owner` (default) or `super-agent`, who rules on a
  merge-gate hold no standing waiver or ruling matches. Any other value is a
  tooling error from `launch.sh`, which launches nothing until it is fixed
  ([step-ins](step-ins.md#the-step-ins)).
- `notify`: `{command, delay}`, the alarm the wake timer runs when a wake
  draws no reconcile within the delay
  ([watching](watching.md#the-wake-timer) has its shape).
- `repos.<owner/name>.machine`: pins the repo to one machine key
  ([placement](placement.md#the-rules)). `machines.<m>.slots`: the machine's
  slot count. Edit both with `scripts/fleet.sh`, not by hand.

## The super agent's own tier

Run the super agent's own thread on Sonnet with high effort: it routes, reads
summaries and records, work that needs no larger tier. The owner sets it in T3
Code, in the model selection of the super agent thread (or when launching it);
a running super agent never changes its own model. Tell the owner this at the
end of setup. The status block's `Super agent on <instance>` line shows which
provider instance the thread runs on.

## Re-runs

Setup runs only here, on the super agent's machine. The owner edits the file by
hand for anything setup proposed (slots, thresholds, active repos, waivers,
`work_week`); a re-run keeps those edits for a machine probed before and
refreshes only the probed facts (`proposed_slots` shows what a fresh measure
would set), while a machine never probed takes the computed slots. One edit
is not kept: a `last-fix-after-cap` waiver still holding the old default text
gets the current one, since that waiver never covered ship's local review; any
other text stays, named in a warning. An
unreachable machine keeps its previous facts and is probed on the next setup
that finds it reachable. An `unavailable` provider, or an instance whose
`auth` is `failed`, is a fact to report, not an error: name it with its reason
and carry on. A recorded `failed` carries `auth_source` and `auth_checked`:
`quota.sh` honors only a T3-sourced one under 24 h old, so an instance that
signed back in routes again without a hand edit. Setup runs on Linux only
(GNU `nproc`, `free`, `timeout`).
