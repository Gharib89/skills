---
name: setup-harness
description: "Set up this repo's agent harness for Claude Code: one check entry point (scripts/check.sh), a pre-commit runner, the linters, formatters, typecheckers and tests it runs, and hooks that run them after every edit and at every turn end, each third-party tool pinned and passed through an install check. Independent of Ship; run it before /setup-skills. Re-run after adding a stack or tool."
disable-model-invocation: true
metadata:
  version: 1.0.0
  harness-schema: 1
---

# Setup harness

Give every Claude Code session in this repo a fast, measured way to check its own work: `scripts/check.sh` answers "is this change good" at three rungs, Claude Code hooks run the fast rungs on every edit and every stop, and the pre-commit runner holds the commit. Same shape as `setup-skills`: explore, present, confirm, write, prove. Nothing is written before the human confirms it as a diff, and nothing third-party is installed before it passes the install check.

Vocabulary: [CONTEXT.md](https://github.com/Gharib89/skills/blob/main/CONTEXT.md) of the source repo (agent harness, check entry point, rung, budget, stack, member, file kind, catalog, trust tier, install check, harness profile). "Verification" is Ship's word for a real-system check; never use it for anything here.

This version sets up the local ladder: the profile's `## Cloud` is written `Verdict: cloud-first`, `Setup: None.`, `Proof: unproven`, and no language server is wired. Say so in the report.

**Paths are contracts.** `scripts/check.sh`, `.claude/hooks/check-hook.sh` and `docs/agents/harness.md` are read by hooks, by `setup-skills` and by a re-run; write them at exactly those paths. Configuration is committed at project scope (`.claude/settings.json`, `.claude/hooks/`, the runner config); anything machine-specific goes to `.claude/settings.local.json`, and the report names it as such.

## Process

### 1. Preconditions: instruct and stop

On any failure print the exact command, then "then rerun `/setup-harness`", and stop.

1. **A git repo with tracked files**, on GitHub or Azure DevOps (`git remote get-url origin`). `curl` and `python3` on `PATH`: this skill's `scripts/pick-version.sh` needs both.
2. **A clean working tree** (`git status --porcelain` empty; else `git stash -u`), so the run's changes are the whole diff and a fix-mode tool rewrites nothing the human has not committed.
3. **Claude Code floor.** Skip this item entirely when `CLAUDE_CODE_REMOTE=true`. Read `claude --version`. Below **2.1.277** (the profile's `Floor:`), write nothing under `.claude/` in this run, print the upgrade command for the install method (`claude update`; Homebrew `brew upgrade claude-code`; npm `npm install -g @anthropic-ai/claude-code@latest`), and stop. The floor is the last release fixing a prompt-cache or context bug that hooks would trigger.
4. **Warn, do not stop**, in the report's header:
   - `claude doctor </dev/null` reports `Auto-updates:` other than `enabled`: name the switch doctor names (`DISABLE_AUTOUPDATER`, `DISABLE_UPDATES`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`) and the install method's own update command, since Homebrew, WinGet and apt installs do not self-update.
   - The installed version trails its channel's latest: `npm view @anthropic-ai/claude-code dist-tags --json` (`latest` and `stable`); name the channel, both versions and the update command.

### 2. The profile

Read `docs/agents/harness.md` if it exists; a repo without one is a first run.

- `Schema:` equal to this skill's `metadata.harness-schema`: read its choices (`## Budgets` overrides, `Local-only:` and `Declined:` lines) and honour them without re-asking.
- `Schema:` behind: the migration is the first, undroppable row of the confirm step, applied entry by entry from [harness-schema.md](harness-schema.md), `Schema:` rewritten last.
- `Schema:` ahead: stop. That repo was set up by a newer setup-harness; print `npx skills add Gharib89/skills --skill setup-harness --agent claude-code -y` and "then rerun `/setup-harness`".

### 3. Explore

Read-only. Collect, then present everything at once in step 4.

1. **Stacks, members and file kinds** per [reference/detection.md](reference/detection.md): read every `catalog/*.md` `## Signals` block first, then scan tracked files only. Read [catalog/README.md](catalog/README.md) once, then each detected entry's file.
2. **Tools per member and role** from the evidence, applying the catalog's yielding rules: the repo's tools are kept and only their gaps filled; a default fills only a role with no evidence.
3. **The pre-commit runner** git invokes, per [reference/runner.md](reference/runner.md), and any config that is present but not wired.
4. **Existing harness pieces**: `scripts/check.sh`, `.claude/hooks/`, the `hooks` in `.claude/settings.json` and `.claude/settings.local.json`, and a `### Harness` block in `CLAUDE.md`. An existing `check.sh` or hook is the repo's own: keep what it runs and propose only what it lacks.
5. **The install-check rows**: every package, hook repo or binary the plan adds or re-pins, per [reference/install-check.md](reference/install-check.md), with its version picked by this skill's `scripts/pick-version.sh` and its tier, publisher, provenance and glue read now.

### 4. Present

One message, in this order:

1. **Header**: skill version, the profile's `Schema:` (and what it migrates to), the Claude Code floor against the installed version (or `skipped: cloud session`), and the step-1 warnings.
2. **Detection** as detection.md's report lists it.
3. **Questions**, numbered, each with a recommendation: every candidate (root or ignored), every role with two tools and no caller, a runner choice where more than one config has no shim.
4. **The install-check table**, glue in full after it, then **Found, not installed** with each refusal's reason.
5. **The writes, as diffs**: runner config additions, the manifest line of each pinned dev dependency, config files a catalog `Constraints:` or `Traps:` line writes, the `scripts/check.sh` configuration block, `.claude/hooks/check-hook.sh`, the `.claude/settings.json` hook entries, `docs/agents/harness.md` and the `CLAUDE.md` block.

### 5. Confirm

One approval covers the batch: the human answers the questions and may drop rows or writes by number. A dropped row with a reason is recorded `Declined: <what>: <reason>` in the profile in the same batch; one dropped without a reason is proposed again next run. An ignored candidate is recorded the same way. Re-present only what an answer changed.

### 6. Write

In this order, each step's failure stopping the run with its output:

1. **Installs**: each approved unit at its exact pin, then the repo's own deps from its lockfile (`uv sync --frozen`, `pnpm install --frozen-lockfile`).
2. **The runner**: its config additions, its install command when git does not yet invoke it (`prek install`), then `prek run --all-files` (or the runner's equivalent). A failure here is the repo's code on a tool new to it: report the findings and ask whether to fix them in this run, leave them for the human, or drop the tool; leave and drop `git restore` the files its fixes rewrote. Never weaken the tool's config to pass.
3. **`scripts/check.sh`** from [templates/check.sh](templates/check.sh), configuration block filled per [reference/check-ladder.md](reference/check-ladder.md).
4. **Time the rungs** before any hook exists, per check-ladder.md's timing section: each twice, cold reported, warm judged against its budget. A warm `edit` or `turn` over budget gets the narrow / demote / override offer now, and its hook waits until one is applied.
5. **`.claude/hooks/check-hook.sh`** from [templates/check-hook.sh](templates/check-hook.sh) and the hook entries from [templates/settings-hooks.json](templates/settings-hooks.json), merged beside the repo's own, each `timeout` derived from its budget.
6. **`docs/agents/harness.md`** from [templates/harness-profile.md](templates/harness-profile.md): `Floor:` and `Location:` as written, every budget `default` unless the human gave an override with a reason, `## Cloud` as this version writes it, `Local-only:` and `Declined:` lines from the confirm step. Then run `scripts/harness-profile-check.sh docs/agents/harness.md` from this skill's directory; a violation is fixed before continuing.
7. **The `CLAUDE.md` block** from [templates/harness-block.md](templates/harness-block.md), replacing an existing `### Harness` block rather than adding a second.

### 7. Prove

1. **Report step 6's timings**; re-time only a rung a narrow, demote or override changed. An override is written `override <N>s: <reason>` in `## Budgets`, and the hook `timeout`s and wrapper deadlines are re-derived from it.
2. **The contract**: `scripts/check.sh full` prints one JSON line and exits 0, or its failures are reported as the repo's code, each `<rung>: fail (<check>)`.
3. **The profile** passes `harness-profile-check.sh`.

### 8. Report

1. The header from step 4.
2. What was written, one line per file, `.claude/settings.local.json` entries named machine-specific.
3. **Budgets**: one row per rung, cold, warm, budget, verdict (`within`, `over: narrowed`, `over: demoted to <rung>`, `over: override <N>s`, `not judged: fail (<check>)`).
4. **Not acted on**: unclaimed extensions and stacks, unwired tools, Found-not-installed units, anything "present, not wired".
5. **Standing choices**: every `Declined:` and override, and `cloud: unproven`: this version sets up the local ladder only.
6. **Next**: commit the harness files; hooks in `.claude/settings.json` load in new sessions, so start one (or review them in `/hooks`) before relying on them; then `/setup-skills` if the repo uses Ship.

## Re-run

A re-run is the same process. Existing harness files are the repo's own evidence: compare each written file against its current template by what it says, propose what the repo's copy lacks and keep its additions. A standing `Declined:` choice is listed, never re-asked; removing the line re-opens it.
