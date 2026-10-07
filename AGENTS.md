# AGENTS.md

## Code Review Rules

Review a pull request adversarially: try to show it does not do what it claims.

- **Challenge the change against its contract**: the PR's stated intent and, where the PR links an issue, its acceptance criteria, plus the invariants this repo documents. Read the `## Reviewer section` of `docs/contributing/coding-standards.md` whole, then the sub-file it routes each path in the diff to; use the vocabulary in `GLOSSARY.md`, and cite each rule by its bold lead rather than restating it.
- **Skip what this repo has ruled is not a finding**: the list under `## What is not a finding` in `.github/copilot-instructions.md`.
- **Trace callers and seek a concrete counterexample** where the diff reaches it: shell quoting and word splitting, option and argument handling, a mechanic's JSON shape and exit codes, reviewer freshness (a round or check read off a head other than the PR's), and a skill's source under `skills/<name>/` changed without its derived copy under `.claude/skills/<name>/`.
- **Try to falsify each defect before reporting it**, against the surrounding code, the exceptions the Reviewer section lists, and the existing tests; report only what survives.
- **Report each finding with** the changed location, its severity, the condition that triggers it and the observable consequence, plus a reproduction or a concrete execution trace where practical.
- **A clean result is a valid result**: report only findings that survive falsification, even when that is none.
- **Report a defect duplicated in a source and its derived copy once**, on the source under `skills/<name>/`.
