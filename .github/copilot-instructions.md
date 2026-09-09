# Copilot instructions

This repo is the source of a set of shared agent skills written in bash and Markdown. There is no application code and no CI; the checks are `scripts/local-gate.sh` and your review.

Review against [docs/contributing/coding-standards.md](../docs/contributing/coding-standards.md). Read it: the rules below are only the ones a reviewer most often gets wrong here.

## What is not a finding

- **`.claude/skills/<name>/` duplicating `skills/<name>/`.** The second is the source; the first is install output from `npx skills add . --skill <name> --agent claude-code -y`, committed on purpose so a cloud session and a consumer repo find the skill. A PR that changes one and not the other is a finding; the duplication itself is not.
- **A mechanic that prints JSON and exits 1.** That is the local-gate and mechanic contract, not swallowed error handling. Evidence belongs on stderr, capped at 40 lines.
- **Markdown prose that reads like instructions to a machine.** These documents are consumed by agents, so imperative, unhedged prose is the house style.

## What is worth flagging

- A change to `skills/<name>/` with no matching change under `.claude/skills/<name>/`, or no `metadata.version` bump in that skill's `SKILL.md`.
- A change to what `ship` expects of a ship profile with no `metadata.profile-schema` bump and no new `## Schema N` entry in `skills/setup-skills/profile-schema.md`.
- `gh` or `az` called from anywhere but `skills/ship/scripts/host/github.sh` or `skills/ship/scripts/host/ado.sh`.
- Unquoted expansions, missing `set -uo pipefail`, and `mktemp` without a `trap` that removes it.
- Terms that contradict the glossary in [CONTEXT.md](../CONTEXT.md), including the synonyms each entry says to avoid.
- Em dashes, anywhere.
