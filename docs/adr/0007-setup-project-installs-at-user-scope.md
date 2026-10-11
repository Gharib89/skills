---
status: accepted
---

# setup-project installs at user scope

Every other shared skill is installed at repo scope, because a personal skill silently shadows the repo's derived copy. `setup-project` is the one exception: it installs with `-g`, and it installs everything else into the repo at project scope. Its job is to put the derived copies in place, so it must run in a repo holding none of them yet, where a project-scope skill cannot exist. No consumer repo it sets up carries a `setup-project` copy for the personal one to shadow. The source repo differs: it keeps a derived copy like every skill it writes, so its derived-copies gate needs no special case, and the personal copy shadowing it is harmless because both come from the same source.

## Considered options

- Project scope like every other skill: cannot run before the repo has skills, which is the case it exists for.
- User scope for `setup-project` only, project scope for everything it installs (chosen, 2026-10-11).
