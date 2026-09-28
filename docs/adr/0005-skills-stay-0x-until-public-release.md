---
status: accepted
---

# Skills stay 0.x until their public release

Amends 0003. No skill here has been publicly released, yet 0003's grades took `ship` to 11.1.4 and `setup-skills` to 8.1.1, because every breaking change was a major and every `.release/*.toml` carried `allow_zero_version = false`, which left no way to say "not released yet". A first public release at 11 reads as ten broken contracts to a reader who never saw one of them.

So every skill is 0.x until the maintainer releases it. Each `.release/<skill>.toml` sets `allow_zero_version = true` and `major_on_zero = false`: while a skill is 0.x, a `!` or a `BREAKING CHANGE:` footer bumps the minor, and `feat` and every other type grade as 0003 says. A new skill arrives at `0.1.0`. Moving a skill to 1.0.0 is the maintainer's act at its public release: a PR setting `major_on_zero = true` in that skill's toml, titled with `!` under the `major` label, from which the release run cuts 1.0.0.

The existing numbers moved once, `M.m.p` to `0.M.p` (#369): `ship` 0.11.4, `cloud-ship` 0.2.0, `setup-skills` 0.8.1, `update-skills` 0.1.0, `setup-harness` 0.1.0. Carrying the old major into the minor keeps each skill's number in step with its last major; the changelogs keep their old headings as written, under a note after the `<!-- version list -->` marker naming the renumber, so every 0.x entry the release run writes lands above it (probed: a fix on 0.11.4 wrote v0.11.5 there). The old `<skill>-v*` tags are deleted at the merge gate, immediately before the merge, because python-semantic-release computes the next version from the highest tag matching `tag_format`: with `ship-v11.1.4` left in place, the next fix is 11.1.5 whatever `SKILL.md` says. With no tag left, the workflow's baseline step tags each skill at the merge commit with its 0.x number, and that push releases nothing.

Measured against 10.6.2, the workflow's pin, in a throwaway repo:

- Tagged `x-v11.1.4` and `x-v0.1.0`, a fix gave 11.1.5. With `x-v0.1.0` alone, a fix gave 0.1.1 and a breaking change 0.2.0.
- Tagged `x-v0.11.4` at HEAD: "No release will be made". A fix on top gave 0.11.5 and a breaking change 0.12.0. The same breaking change under `major_on_zero = true` gave 1.0.0.

## Consequences

- The `version-lines` gate admits the renumber alone: one version line out and one in, `M.m.p` with `M` at least 1 to exactly `0.M.p`, in the diff that flips that skill's `allow_zero_version` to true. The flip happens once, so no later diff qualifies, a move from 1.x back to 0.x included.
- `ship`'s retired terms moved with the numbers (9.0.0 to 0.9.0), and `update-skills`' plan reads an installed `M.m.p` above the new version as `0.M.p`, the one move down a refresh makes, because it applies a row whose version lies in `(installed, new]`. Consumers sat at ship 1.1.0, 1.2.3, 5.2.1, 8.0.0 and 11.x at #369: one at 5.2.1 reads `(0.5.1, 0.11.4]` and still plans 0.9.0's rows, where the raw range would be empty.
- While a skill is 0.x its number no longer separates additive from breaking: a minor can be either, so a consumer crossing one reads that release's changelog entry.
- `bump-guard` still holds a `!` title to the maintainer's `major` label, though in 0.x it grades a minor: a breaking change stays the maintainer's decision, whatever digit it moves.
