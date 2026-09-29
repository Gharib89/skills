# Harness profile schema

One `## Schema N` entry per number, oldest first, each listing the structural changes from N-1. A setup-harness re-run reads this file to migrate a profile whose `Schema:` line trails the skill's `metadata.harness-schema`: apply every entry between the two numbers in order, leave the prose under existing headings to the human, and rewrite the `Schema:` line last.

Bump rule: a setup-harness PR that changes what the profile must contain (a heading or `Label:` line added, renamed or removed; a `Label:` vocabulary changed) adds an entry here, moves `metadata.harness-schema` in `SKILL.md`, the `Schema:` line in [templates/harness-profile.md](templates/harness-profile.md) and the `schema=` literal and grammar in [scripts/harness-profile-check.sh](scripts/harness-profile-check.sh), and is graded a setup-harness major.

Two lines are frozen across every schema, because `setup-skills` is to read them with no schema check: `Location:` under `## Check entry point` and `Setup:` under `## Cloud`. Renaming either is a major of both skills in one PR.

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

## Schema 2

A candidate the human marks a root is recorded, so a re-run reads it instead of asking again.

- A seventh `##` heading, `## Roots`, between `## Cloud` and `## Local-only`: `Root: <path>: <reason>`, repeatable, or `Root: None.`, each a lockless manifest the human marked a root.
- Migration: insert `## Roots` holding `Root: None.` before `## Local-only`. A Schema 1 profile never recorded its marked roots, so the first Schema 2 re-run asks each candidate once more, and its answers are the first `Root:` lines.
