# Harness profile

Schema: 3

Written by `/setup-harness`, which reads it back on a re-run. Facts sit on `Label:` lines; prose under a heading is yours and nothing parses it. A budget override reads `override <N>s: <reason>`.

## Claude Code

Floor: 2.1.277

## Check entry point

Location: scripts/check.sh

## Budgets

Edit: default
Turn: default
Commit: default
Full: default
Cloud setup: default

## Cloud

Verdict: cloud-first
Setup: .claude/hooks/cloud-setup.sh
Allowlist: None.
Proof: 2feca7bfc75121cd7266074b2a8fce112328e544

## Excluded

Excluded: tests/fixtures/: catalog-trial fixtures, deliberately bad or byte-exact inputs scripts/catalog-trial.sh reads, not code this repo ships

## Roots

Root: None.

## Local-only

Local-only: None.

## Declined

Declined: shfmt: its default tab indent rewrites every indented line of this repo's two-space scripts, a change across the skills this repo writes; no Go toolchain on the maintainer's machine
Declined: markdownlint-cli2: 264 findings over the skills' prose (MD024 fires on the catalog's repeated tool headings by design); adopting it is its own ticket, and house-style and prose-budget already hold these files
Declined: Prettier on Markdown: rewrites 40 files across the skills this repo writes; its own ticket, as markdownlint-cli2
Declined: *.md *.markdown in EDIT_GLOBS: house-style is a whole-repo check that #518 placed at the commit rung, so a Markdown edit does not pay it on every write
