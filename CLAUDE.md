## Agent skills

### Issue tracker

Issues are tracked as GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus at most one Kind, one Size and one Priority dimension label per issue. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Ship

`/ship` drives one issue to a merge-ready PR. This repo's ship profile: `docs/agents/ship.md`. Without that file ship refuses: run `/setup-skills`.

Every skill under `.claude/skills/` is a derived copy, changed at its source and refreshed here; `skills-lock.json` records each one's source. This repo is the source of `ship`, `cloud-ship` and `setup-skills`, so its copies are installed from itself; the skills ship composes come from `mattpocock/skills`, `upstash/context7` and `humanlayer/skills`. Refresh at project scope, without `-g`; ship's refresh chains its preflight, so a profile the refreshed ship no longer reads is reported now, not on the next `/ship`:

```sh
npx skills add . --skill ship --skill cloud-ship --skill setup-skills --agent claude-code -y \
  && .claude/skills/ship/scripts/preflight.sh none
```

**A change to `skills/<name>/` is not finished until the refresh line has run and both trees are in the same commit.** `.claude/skills/` is what actually executes, so an unrefreshed change means the run is exercising the previous version. Run the refresh at the end of the implementation phase, before the self-review: the run's remaining phases then invoke the new mechanics, while changed `SKILL.md` prose is proven by the next run, because the skill was loaded into context at run start. The `derived-copies` gate in `scripts/local-gate.sh` fails when the two trees differ.
