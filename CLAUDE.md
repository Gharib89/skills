## Agent skills

### Issue tracker

Issues are tracked as GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus at most one Kind, one Size and one Priority dimension label per issue. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Ship

`/ship` drives one issue to a merge-ready PR. This repo's ship profile: `docs/agents/ship.md`. Without that file ship refuses: run `/setup-skills`.

Every skill under `.claude/skills/` is a derived copy, changed at its source and refreshed here; `skills-lock.json` records each one's source. This repo is the source of `ship`, `cloud-ship`, `setup-skills`, `update-skills`, `setup-harness` and `grill-with-artifact`, so its copies are installed from itself; the skills ship composes come from `mattpocock/skills`, `upstash/context7` and `humanlayer/skills`. Refresh at project scope, without `-g`; ship's refresh chains its preflight, so a profile the refreshed ship no longer reads is reported now, not on the next `/ship`:

```sh
npx skills add . --skill ship --skill cloud-ship --skill setup-skills --skill update-skills --skill setup-harness --skill grill-with-artifact --agent claude-code -y \
  && .claude/skills/ship/scripts/preflight.sh none
```

**A change to `skills/<name>/` is not finished until the refresh line has run and both trees are in the same commit.** `.claude/skills/` is what actually executes, so an unrefreshed change means the run is exercising the previous version. Run the refresh at the end of the implementation phase, before the self-review: the run's remaining phases then invoke the new mechanics, while changed `SKILL.md` prose is proven by the next run, because the skill was loaded into context at run start. The `derived-copies` gate in `scripts/local-gate.sh` fails when the two trees differ.

### Harness

`scripts/check.sh` is this repo's check entry point: `edit <file>...` lints and formats (ShellCheck on scripts; actionlint, zizmor and Prettier on workflows); `turn` typechecks and runs the affected tests of every uncommitted change, which here is nothing, since this repo has no stack member, so it answers `skipped`; and `full` answers for the whole repo: the runner on every file, `tests/run.sh`, and the repo's own checks that need no base. `full` takes about three minutes and runs in the background, and a probe of the check contract uses a throwaway repo from the template with stub `FULL_ROWS`. It prints one JSON line and exits 0 pass, 1 fail, 2 unavailable, 3 over budget. Hooks in `.claude/settings.json` run `edit` after every Edit or Write and `turn` at every stop, and the pre-commit runner is the commit rung. Harness profile: `docs/agents/harness.md`. Re-run `/setup-harness` after adding a stack, a member or a tool. Ship's gate, `scripts/local-gate.sh`, calls `full` and adds `secrets` and `version-lines`, which need a base ref.
