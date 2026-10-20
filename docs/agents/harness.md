# Harness profile

Schema: 3

Written by `/setup-harness`, which reads it back on a re-run. Facts sit on `Label:` lines; prose under a heading is yours and nothing parses it. A budget override reads `override <N>s: <reason>`.

## Claude Code

Floor: 2.1.277

## Check entry point

Location: scripts/check.sh

The turn rung has a repo-root `shell` row for `*.sh`, added by hand to `check.sh`'s configuration block (the setup-harness shell catalog entry has no test runner, and a re-run keeps what was added). Its command, `scripts/shell-turn-tests.sh`, maps each edited file to the `tests/*.test.sh` that name its basename (ship's `_lib.sh` and its `lib/` pieces map to the tests naming `_lib.sh`, and a `<script>.d/` piece to the tests naming `<script>.sh`) and runs them through `tests/run.sh`, so the host stub stays in front of PATH. A fan-out past the turn budget reports `over-budget`.

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
Excluded: .claude/skills/: derived skill copies, refreshed from skills/ and pinned by skills-lock.json; the runner already skips them, and without this a refresh reports a new root on every turn

## Roots

Root: None.

## Local-only

Local-only: None.

Ship's local gate rests on this: with no `full` check tied to this machine, `scripts/local-gate.sh` runs only `secrets` and `version-lines`, which need the base ref, and reports every `full` check `deferred-to-ci`, since CI's `check-full` leg runs `full` on each PR head of this public repo.

## Declined

Declined: shfmt: its default tab indent rewrites every indented line of this repo's two-space scripts, a change across the skills this repo writes; no Go toolchain on the maintainer's machine
Declined: markdownlint-cli2: 264 findings over the skills' prose (MD024 fires on the catalog's repeated tool headings by design); adopting it is its own ticket, and house-style and prose-budget already hold these files
Declined: Prettier on Markdown: rewrites 40 files across the skills this repo writes; its own ticket, as markdownlint-cli2
Declined: house-style at the edit rung: it is a whole-repo check that #518 placed at the commit rung, so a Markdown edit does not pay it on every write; `EDIT_RUN`'s `--skip house-style` keeps it there while `*.md` rides `EDIT_GLOBS` for prose-budget
Declined: skills/explainer-video npm ci in DEPS_ROWS: its dependencies (hyperframes, onnxruntime-node) are the per-user tool cache's payload, which setup.mjs installs there and never in the skill's own folder; its tests run on a fake backend and need none of them
Declined: ESLint on skills/explainer-video: the default adds eslint and @eslint/js to a manifest setup.mjs installs with npm ci into every user's tool cache, and moves the lock hash that keys that cache
