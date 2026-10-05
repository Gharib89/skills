# Copilot instructions

This repo is the source of a set of shared agent skills written in bash and Markdown. There is no application code; the checks are `scripts/local-gate.sh`, the `bump-guard` workflow over the PR title, and your review.

Review against [docs/contributing/coding-standards.md](../docs/contributing/coding-standards.md), the one source of the rules here. Read its reviewer section whole, then the standards file it routes each path in the diff to; every rule a finding cites lives there, with its exceptions.

## What is not a finding

- **`.claude/skills/<name>/` duplicating `skills/<name>/`.** The second is the source; the first is install output from `npx skills add . --skill <name> --agent claude-code -y`, committed on purpose so a cloud session and a consumer repo find the skill. A PR that changes one and not the other is a finding; the duplication itself is not.
- **A second thread on the derived copy.** Anchor on `skills/<name>/`, never the derived copy: the two are byte-identical by gate, so one defect is one thread.
- **A mechanic that prints JSON and exits 1.** That is the local-gate and mechanic contract, not swallowed error handling. Evidence belongs on stderr, capped at 40 lines.
- **Markdown prose that reads like instructions to a machine.** These documents are consumed by agents, so imperative, unhedged prose is the house style.
