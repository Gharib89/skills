---
status: accepted
---

# Ship's scripted live run drives a real fixture repo

A change to Ship's prose (`SKILL.md` and its references) is proven by a headless `claude -p` run that drives `/ship` on a standing GitHub fixture repo, reset off a seed tag. It uses the real `gh` and real host state, not the host fake that every other Ship test runs against. This repo's ship profile names the run as a Verification, and the maintainer can also start it by hand. The scope is Ship only: the happy path to the merge gate, plus one early stop.

The host fake answers the n-th call to a function from a canned file and keeps no state, so a label Ship adds never reads back. A model that re-checks state after a write would then stop for the fake's reasons, not the prose's, and the run would fail on runs where nothing regressed. Pointing git at a local bare origin would also defeat host detection, since `ship_detect_host` reads `git remote get-url`, and that command expands `insteadOf`. Working around it would need a new test-only seam inside `skills/`.

## Considered options

- Formalize the Herdr consumer drive already used for new skills. It found real prose defects on #314, but it is run by hand and only for new skills, so an edit to Ship's phase rules still ships unproven.
- The host fake plus a local bare origin: no network is needed, but there is no state, and the git seam described above is still missing.
- Create and delete a real repo on every run: a clean slate each time, but deleting needs the `delete_repo` scope.
- A standing GitHub fixture repo (chosen). Decided in the #608 grilling session on 2026-10-12.
