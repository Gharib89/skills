# Copilot instructions

This repo is the source of a set of shared agent skills written in bash and Markdown. There is no application code; the checks are `scripts/local-gate.sh`, the `bump-guard` workflow over the PR title, and your review.

Review against [docs/contributing/coding-standards.md](../docs/contributing/coding-standards.md). Read it: the rules below are only the ones a reviewer most often gets wrong here.

## What is not a finding

- **`.claude/skills/<name>/` duplicating `skills/<name>/`.** The second is the source; the first is install output from `npx skills add . --skill <name> --agent claude-code -y`, committed on purpose so a cloud session and a consumer repo find the skill. A PR that changes one and not the other is a finding; the duplication itself is not.
- **A mechanic that prints JSON and exits 1.** That is the local-gate and mechanic contract, not swallowed error handling. Evidence belongs on stderr, capped at 40 lines.
- **Markdown prose that reads like instructions to a machine.** These documents are consumed by agents, so imperative, unhedged prose is the house style.

## What is worth flagging

- A change to `skills/<name>/` with no matching change under `.claude/skills/<name>/`, or a PR title whose Conventional-Commit type under-grades the public-surface change. The title is the grade: the release run on main writes `metadata.version` from the squash subject, so a bump in the diff is a finding the other way and `scripts/version-line-check.sh` already refuses it.
- A change to what `ship` expects of a ship profile with no `metadata.profile-schema` bump and no new `## Schema N` entry in `skills/setup-skills/profile-schema.md`.
- `gh` or `az` called from any script in this repo but `skills/ship/scripts/host/github.sh` or `skills/ship/scripts/host/ado.sh`. A run's direct informational read (CONTEXT.md **Informational read**) is not a script and is not this finding.
- Unquoted expansions, missing `set -uo pipefail`, and `mktemp` without a `trap` that removes it.
- Terms that contradict the glossary in [CONTEXT.md](../CONTEXT.md), including the synonyms each entry says to avoid.
- A PR body missing any of the seven sections `## Why the change`, `## Change outline`, `## Special things to note`, `## Needs attention`, `## Verification`, `## Review` and `## Attribution`, or whose `## Change outline` carries neither a Shape (a `diff` fence over a call tree, control flow, pseudocode or component tree) nor a `Shape: none, mechanical (<kind>).` line.
- A `Shape: none, mechanical (<kind>).` line on a change whose reviewer has to ask what something now does, rather than only whether the text changed correctly. The diff being comments or prose does not settle it.
- Em dashes, anywhere.
