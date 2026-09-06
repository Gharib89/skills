# Skills

Ahmed Gharib's shared agent skills, installed globally into every repo the same way the mattpocock skills are. Each skill is written once here; a repo expresses its own differences through per-repo docs, never by forking the skill.

## Language

**Ship**:
The skill that drives one tracker issue from nothing to a merge-ready PR in a single unattended run, stopping at the merge gate.
_Avoid_: pipeline, deliver, autopilot

**Ship profile**:
The per-repo document (`docs/agents/ship.md`) that carries every repo-specific fact Ship needs, one section per axis. A repo without a profile cannot run Ship.
_Avoid_: ship config, ship settings, project instructions (that is CLAUDE.md)

**Axis**:
One dimension along which repos legitimately differ in how they ship: claim mechanism, worktree layout, local gate, review-bot topology, verification kind, versioning, PR template, small-lane floor.
_Avoid_: option, knob, setting

**Local gate**:
The repo-owned script that runs every check the repo's CI would run, locally, before a PR opens. The only Ship mechanic whose body is the repo itself.
_Avoid_: pre-push checks, lint step, test step

**Generic mechanic**:
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: preflight, claim and release, isolate, CI wait, merge, reflect.
_Avoid_: helper, util

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing. `setup-ship` drafts the ship profile.
_Avoid_: init, scaffold, bootstrap

**Sibling skill**:
A skill that composes Ship or hands work to it rather than reimplementing it: `cloud-ship`, `merge-gate`, `agy-ship`, `powerbi-ship`.
_Avoid_: wrapper, plugin, variant

**Merge gate**:
The hard stop at the end of a Ship run where a human reads the summary and says merge or not. Ship never merges on its own.
_Avoid_: approval, sign-off, review

**Small lane**:
The collapsed form of a Ship run for a change the whole team would call trivial; keeps a fixed floor of checks and is revocable mid-run.
_Avoid_: fast path, quick mode, hotfix
