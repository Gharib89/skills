# Ship profile

Schema: 1

Every repo-specific fact `/ship` needs, one section per axis. Vocabulary: [CONTEXT.md](../../CONTEXT.md).

This repo is both the **source** of the shared skills and a **consumer** of them: `skills/<name>/` is the source of truth and `.claude/skills/<name>/` is the derived copy that actually runs. A change to a skill is not shipped until both carry it.

## Host

Host: github

## Worktree

Carry: None.
Bootstrap: None.

Nothing here is gitignored and nothing needs installing: the mechanics are bash, and the gate's only download is `npx -y shellcheck`, cached per machine.

## Local gate

Location: scripts/local-gate.sh
Small node: the path of the changed script, e.g. `skills/ship/scripts/merge.sh`
Tripwires: None.

Every gate is repo-wide and takes seconds, so the small lane records the node and narrows nothing. There is no CI, so no gate is ever `deferred-to-ci`: the gate is the whole automated check on a diff, alongside the reviewer.

`derived-copies` is the drift gate. It fails when `.claude/skills/<name>/` differs from `skills/<name>/` for `ship`, `cloud-ship` or `setup-skills`, which is what makes the refresh below non-optional rather than a habit.

## CI

Legs: None.
No-checks legal: yes, this repo has no workflows at all
Push policy: Default.

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot] posts the review; Copilot posts the inline comments
Trigger: on-push
Request: None.
Cap: None.
Resolve: resolve-thread
Gating: no
Instructions: .github/copilot-instructions.md

Enabled by the repository ruleset **Copilot code review** on the default branch, with `review_on_push: true`. That setting, not the brand, is what makes the trigger `on-push`: every push to an open PR draws a fresh round, so rounds are free and convergence needs the bot quiet on the current head with every thread dispositioned and resolved. Flipping `review_on_push` to `false` in the ruleset makes it `auto-once`, and this block must move with it.

## Coding standards

docs/contributing/coding-standards.md

## Verification

### github-mechanics

Proves: a changed generic mechanic or the GitHub adapter performs its host call against a real issue, PR, thread or merge.
Applies when: the change touches `skills/ship/scripts/`, on any path the GitHub adapter reaches.
Run: drive the changed mechanic by hand against a scratch issue on this repo, the way issues #30 and #31 were used.
Needs: `gh` signed in with push permission on `Gharib89/skills`.
Without it: hand-off
Also proven by CI: None.
Claims to probe: the REST response shapes and api-versions the adapter reads, and whether the call is one GitHub still serves.

### ado-mechanics

Proves: a changed Azure DevOps adapter performs its host call against a real work item, PR, thread or completion.
Applies when: the change touches `skills/ship/scripts/host/ado.sh`.
Run: drive the changed mechanic by hand against the `ship-ado-lab` repo in the `AI_And_Data_Practice` project.
Needs: `az login` with Entra (the PAT path has known gaps, issue #29) plus the `azure-devops` extension.
Without it: blocked
Also proven by CI: None.
Claims to probe: the api-version each call pins, and the work-item type and closed state the lab's tracker template declares.

## Versioning and changelog

Tooling: manual
Reads: `metadata.version` in each skill's `SKILL.md`; `metadata.profile-schema` in `skills/ship/SKILL.md`
In-PR requirement: a change to a skill bumps that skill's `metadata.version` in the same PR; a change to what `ship` expects of a profile also bumps `metadata.profile-schema` and adds the matching `## Schema N` entry to `skills/setup-skills/profile-schema.md`
Subject constraints: conventional-commit prefix scoped to the skill, e.g. `fix(ship):`

## PR

Template: .github/pull_request_template.md

## Public surface

Everything a consumer repo depends on, all of it under `skills/`:

- each skill's name, `description` and `argument-hint`, which decide when an agent reaches it
- `ship`'s flags and its stop-reason vocabulary
- every generic mechanic's CLI signature and the shape of the JSON it prints
- the local-gate contract: the flags, the gate statuses, the verdict
- the ship profile's fourteen headings, their `Label:` lines, and the schema number
- the `### Ship` CLAUDE.md block `setup-skills` writes
- the `setup-skills` templates, which land verbatim in consumer repos

## Triage

File as an issue labelled `needs-triage`.

This repo is Ship's own source, so a run here is already upstream and a **Ship defect** met during the run is an adjacent find: it takes phase 2's dispositions, through `file-issue` and its duplicate check, and is still named on the merge summary's `Ship defects:` row. ADR 0001 stands, because the write still goes to the repo the run is in, which here is the repo the defect belongs to.

## Docs sync

Targets: CONTEXT.md, docs/adr/, docs/agents/, skills/setup-skills/profile-schema.md, .out-of-scope/
Agent-facing: all of them, plus skills/ and .claude/skills/

Every file this repo ships is read by an agent, so `writing-for-agents` applies to the whole diff, not to a subset of it.

## Current docs

Sources: context7
Pinned: None.

The skills CLI (`npx skills@latest`) is unpinned and its behaviour is load-bearing: it decides what a derived copy is and what `skills-lock.json` records. Check its `--help` rather than assuming a flag.

## Cloud lane

PR cap: 3
Bootstrap: None.
