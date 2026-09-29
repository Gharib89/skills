<!-- setup-harness: written inside the `## Agent skills` block of CLAUDE.md (a new one at the end when there is none), this comment removed. With no CLAUDE.md, the file this creates opens with `# CLAUDE.md` above that block, so a markdown linter's first-line-heading rule passes; an existing CLAUDE.md keeps its own first line. -->

### Harness

`scripts/check.sh` is this repo's check entry point: `edit <file>...` lints and formats, `turn` typechecks and runs the affected tests of every uncommitted change, and `full` answers for the whole repo. It prints one JSON line and exits 0 pass, 1 fail, 2 unavailable, 3 over budget. Hooks in `.claude/settings.json` run `edit` after every Edit or Write and `turn` at every stop, and the pre-commit runner is the commit rung. Harness profile: `docs/agents/harness.md`. Re-run `/setup-harness` after adding a stack, a member or a tool.
