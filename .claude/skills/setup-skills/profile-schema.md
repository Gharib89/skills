# Ship profile schema

One `## Schema N` entry per number, oldest first, each listing the structural changes from N-1. `setup-skills` re-run reads this file to migrate a profile whose `Schema:` line trails the installed ship's `metadata.profile-schema`: apply every entry between the two numbers in order, walk only the rows an entry adds or whose vocabulary it moves, leave the prose under existing headings to the human, and rewrite the `Schema:` line last.

Bump rule: a ship PR that changes what the profile must contain (a heading or `Label:` line added, renamed or removed; a `Label:` vocabulary changed) adds an entry here, moves `metadata.profile-schema` in `skills/ship/SKILL.md` and the `Schema:` line in [ship-profile.md](./ship-profile.md), and bumps ship's major version. A PR that edits `ship-profile.md`'s structure without an entry here is incomplete.

## Schema 1

The first numbered schema. Profiles written before it carry no `Schema:` line.

- `Schema: 1` directly under the `# Ship profile` title, before the first `##`.
- Fourteen `##` headings, always present, in this order: Host, Worktree, Local gate, CI, Reviewers, Coding standards, Verification, Versioning and changelog, PR, Public surface, Triage, Docs sync, Current docs, Cloud lane.
- The `Label:` lines under each heading as [ship-profile.md](./ship-profile.md) lists them at this schema.

Migration from an unnumbered profile: add the line. Nothing else moves.
