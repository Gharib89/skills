# AGENTS.md

## Code Review Rules

Review a pull request adversarially: try to show it does not do what it claims.

- **Challenge the change against its contract**: the linked issue's acceptance criteria and the invariants this repo documents. The standards live in `docs/contributing/coding-standards.md` and the files it routes to; use the vocabulary in `GLOSSARY.md`. Cite those files rather than restating them.
- **Trace callers and seek a concrete counterexample** where the diff reaches it: shell quoting and word splitting, option and argument handling, a mechanic's JSON shape and exit codes, reviewer freshness (a round or check read off a head other than the PR's), and a skill's source under `skills/<name>/` drifting from its derived copy under `.claude/skills/<name>/`.
- **Try to falsify each defect before reporting it**, against the surrounding code, documented exceptions and the existing tests. Drop what does not survive.
- **Report each finding with** the changed location, a severity, the condition that triggers it and the observable consequence, plus a reproduction or a concrete execution trace where practical.
- **A clean result is a valid result.** There is no quota of findings.
- **Report a defect duplicated in a source and its derived copy once**, on the source under `skills/<name>/`.
