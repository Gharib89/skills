# Placement

## Contents

- [Launch's answer](#launchs-answer)
- [The rules](#the-rules)

`scripts/` is under this skill's base directory.

## Launch's answer

- a launch: `record.machine` is where it runs. Its `args.environmentId` is
  absent for this machine and set for a remote one. When the ticket needs a CLI
  (bun, say), check that machine's `clis` in the fleet file first, and rerun
  with `--exclude <machine>` when it lacks one.
- `need_reading`: the next candidate has no live reading. Run a probe thread
  there ([setup](setup.md#steps) step 2), save `{<machine>:
  {load1, free_gb}}` from its reply to a file, and rerun with
  `--readings <file>`.
- `waiting`: nothing fits now, and the ledger's `waiting` list already holds
  the ticket; the block's `Waiting` row says so.

## The rules

Place tries this machine first, skips an unreachable machine or one without
the GPU or gh login asked for, and keeps each machine's `reserve` slot for the
owner's messages. Different repos run side by side; two tickets of one repo do
only with no blocking edge and no overlapping areas, so a ticket with no
`--area` waits for the other to finish. A repo runs at most its **ship cap**
at once: the fleet file's `repos.<owner/name>.max_ships`, 3 when unset, counting
every open ticket of the repo, ship and triage, on every machine; a launch over
it waits, the cap named in its reason. A repo the fleet file pins
(`repos.<owner/name>.machine`) runs only on that machine: every other machine is
skipped as `pinned`, and the ticket waits when the pinned machine is down or
full. Pin a repo, unpin it, or set a machine's slots with `scripts/fleet.sh
--fleet <fleet> pin <owner/name> <machine>`, `unpin <owner/name>` or `slots
<machine> <n>`, after a probe thread there says the machine is ready
([setup](setup.md#steps) step 2); the machine must be in the fleet file and
`<n>` above its `reserve`. Reach a machine only through its T3
environment id the owner already linked: no host, user, key or SSH.

