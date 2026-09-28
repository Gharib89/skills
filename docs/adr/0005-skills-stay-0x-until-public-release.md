---
status: accepted
---

# Skills stay 0.x until their public release

Amends 0003. No skill here has been publicly released, yet 0003's grades took `ship` to 11.1.4 and `setup-skills` to 8.1.1, because every breaking change was a major and every `.release/*.toml` carried `allow_zero_version = false`, which left no way to say "not released yet". A first public release at 11 reads as eleven broken contracts to a reader who never saw one of them.

So every skill is 0.x until the maintainer releases it. Each `.release/<skill>.toml` sets `allow_zero_version = true` and `major_on_zero = false`: while a skill is 0.x, a `!` or a `BREAKING CHANGE:` footer bumps the minor; `feat` and every other type grade as 0003 says. Only the major collapses onto the minor. A new skill arrives at `0.1.0`. Moving a skill to 1.0.0 is the maintainer's act at its public release, never a run's.

The existing numbers moved once, `M.m.p` to `0.M.p` (#369): `ship` 0.11.4, `cloud-ship` 0.2.0, `setup-skills` 0.8.1, `update-skills` 0.1.0, `setup-harness` 0.1.0. Keeping the major as the minor keeps each number in order with its changelog history, which stays as written. The old `<skill>-v*` tags were deleted, because python-semantic-release computes the next version from the highest tag matching `tag_format`: with `ship-v11.1.4` left in place, the next fix is 11.1.5 whatever `SKILL.md` says. Measured against 10.6.2, the workflow's pin, in a throwaway repo: both tags gave 11.1.5, the 0.x tag alone gave 0.1.1, and a breaking change on it gave 0.2.0. With no tag left, the workflow's baseline step tags each skill at the merge commit, the way it tags a new skill.

## Consequences

- The `version-lines` gate admits one move, `M.m.p` to exactly `0.M.p` with a non-zero `M`, and still refuses every other, including any bump inside 0.x.
- `ship`'s retired terms moved with the numbers (9.0.0 to 0.9.0), because `update-skills` applies a row whose version lies in `(installed, new]`. A consumer crossing the renumber, 11.1.4 to 0.11.4, reads an empty range, which loses nothing: every consumer had already crossed 0.9.0's rows as 9.0.0.
- `bump-guard` still holds a `!` title to the maintainer's `major` label, though in 0.x it grades a minor: a breaking change stays the maintainer's decision, whatever digit it moves.
