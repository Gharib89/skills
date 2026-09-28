# Harness profile schema

One `## Schema N` entry per number, oldest first, each listing the structural changes from N-1. A setup-harness re-run reads this file to migrate a profile whose `Schema:` line trails the skill's `metadata.harness-schema`: apply every entry between the two numbers in order, leave the prose under existing headings to the human, and rewrite the `Schema:` line last. A profile whose `Schema:` is ahead of the skill stops the run with the refresh line: that repo was set up by a newer setup-harness.

Bump rule: a setup-harness PR that changes what the profile must contain (a heading or `Label:` line added, renamed or removed; a `Label:` vocabulary changed) adds an entry here, moves `metadata.harness-schema` in `SKILL.md`, the `Schema:` line in [templates/harness-profile.md](templates/harness-profile.md) and the check in [scripts/harness-profile-check.sh](scripts/harness-profile-check.sh), and is graded a setup-harness major.

Two lines are frozen across every schema, because `setup-skills` is to read them with no schema check ([#367](https://github.com/Gharib89/skills/issues/367) adds that reader): `Location:` under `## Check entry point` and `Setup:` under `## Cloud`. Renaming either is a major of both skills in one PR; `scripts/contract-check.sh` fails when the template stops carrying them.

## Schema 1

The first schema.

- `# Harness profile`, then `Schema: 1` before the first `##`.
- Six `##` headings, always present, in this order: Claude Code, Check entry point, Budgets, Cloud, Local-only, Declined.
- `## Claude Code`: `Floor: <major>.<minor>.<patch>`, the lowest Claude Code the harness hooks are written for.
- `## Check entry point`: `Location: <path>`, the check entry point's repo-relative path.
- `## Budgets`: `Edit:`, `Turn:`, `Commit:`, `Full:`, `Cloud setup:`, each `default` or `override <N>s: <reason>`.
- `## Cloud`: `Verdict: cloud-first | local-only: <reason>`, `Setup: <path> | None.`, `Allowlist: <hosts> | None.`, `Proof: <sha> | unproven`.
- `## Local-only`: `Local-only: <part>: <reason>`, repeatable, or `Local-only: None.`
- `## Declined`: `Declined: <proposal>: <reason>`, repeatable, or `Declined: None.`
