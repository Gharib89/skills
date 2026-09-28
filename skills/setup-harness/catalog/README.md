# Catalog

One file per stack or file kind. Detection reads only each file's `## Signals` block; a detected entry's whole file is read when the run needs its tools. These shared rules are read once per run. The catalog is closed at run time: a stack with no entry is `unclaimed`, with a pointer to file an issue on [Gharib89/skills](https://github.com/Gharib89/skills/issues), and an entry changes only by PR.

## Contents

- [Entry format](#entry-format)
- [Label vocabulary](#label-vocabulary)
- [Tier rule](#tier-rule)
- [Version rule](#version-rule)
- [Yielding to the repo](#yielding-to-the-repo)
- [Affected tests](#affected-tests)
- [Check targets](#check-targets)
- [Entry trials](#entry-trials)

## Entry format

The profile grammar: fixed headings, facts on `Label:` lines, `None.` where a label has nothing to say. `scripts/contract-check.sh` in the source repo fails an entry that breaks it.

```
# <Stack or file kind>

## Signals
Kind: stack | file kind
Manifest: <file names>                 (stack only)
Lockfile: <file names>                 (stack only)
Workspace: <where a workspace is named> (stack only)
Extensions: <.ext ...>
Shebangs: <interpreters> | None.
Runtime version: <files, in precedence order> (stack only)

## <role>
### <tool>        (default first, then known alternatives)
Publisher: <registry identity the install check matches>
Tier: <n>: <source URL>
Evidence: <config files, [tool.x] tables, dependency names>
Rung: edit | turn | full
Run: `<command>`
Hook: local | <vendor hook repo URL>
Pin: <pin kind> <registry> <name>
Route: `<install command>`; Blocked: <routes that 403> | None.
Constraints: <needs / breaks with> | None.
Unavailable: <reason>                  (only when it applies)
Local-only: <reason>                   (only when it applies)
Traps: <one line each> | None.
```

Roles, as `##` headings, from this set only: `lint`, `format`, `typecheck`, `test runner`, `affected tests`, `language server`, `browser`, `public API`. A file-kind entry carries `lint` and `format` only and never `Rung: turn`: a file kind has no project to typecheck or test. `browser` and `public API` are `Rung: full` only.

## Label vocabulary

- **Rung.** `edit` takes one file and must fit the 5 s edit budget: formatters and most linters, run through the pre-commit runner, fix mode on. `turn` is project-scoped: typecheckers and tests, run by `check.sh` per member. `full` runs only on `check.sh full`.
- **Run.** One command, in backticks. `{files}` stands for the file list and `{member}` for the member's directory; a `turn` command runs in the member's directory. A `lint` or `format` command is the runner hook's `entry`, in fix mode where the tool has one. A command names the tool's own binary; where the tool is a dev dependency, the written hook entry or turn row prefixes the stack's exec command (`uv run`, `pnpm exec`, `npx --no-install`).
- **Hook.** `local` means a `repo: local` runner hook with `language: system`, calling the binary the repo pins, so the commit rung runs the same version as the edit and turn rungs. A vendor hook repo is used only for a tool the repo does not pin, `rev` frozen to a full SHA through the install check.
- **Pin.** The kind names the install check's pin table: `package <npm|pypi|go|crates|nuget> <name>`, `apt <name>`, `hook-repo <url>`, `download <url>`. A package is an exact dev dependency in the repo's manifest and lockfile when the stack has one, else an exact version in the install command.
- **Route.** The install that passes in a cloud sandbox, in backticks, with `{version}` for the version the run picks; `Blocked:` names the routes a cloud sandbox refuses, so a run never proposes them. Route serves the cloud sandbox and the entry trials; a local install follows the install check's pin table.

Each stack's commands, by its lockfile:

| Lockfile | Exec | Exact dev add | Frozen install |
|---|---|---|---|
| `uv.lock` | `uv run --frozen` | `uv add --dev <t>==<v>` | `uv sync --frozen` |
| `poetry.lock` | `poetry run` | `poetry add --group dev <t>==<v>` | `poetry sync` |
| `pdm.lock` | `pdm run` | `pdm add -dG dev <t>==<v>` | `pdm sync` |
| `pnpm-lock.yaml` | `pnpm exec` | `pnpm add -D -E <t>@<v>` | `pnpm install --frozen-lockfile` |
| `package-lock.json` | `npx --no-install` | `npm install -D -E <t>@<v>` | `npm ci` |
| `yarn.lock` | `yarn run` | `yarn add -D -E <t>@<v>` | `yarn install --immutable` (Yarn 1: `--frozen-lockfile`) |
| `bun.lock` | `bun run` | `bun add -d --exact <t>@<v>` | `bun install --frozen-lockfile` |

## Tier rule

A tool's tier is its publisher's: tier 2 for the tool's own vendor. A packaged tool named by tier-1 glue (an Anthropic plugin) takes tier 1. No trust by stars, downloads or recency. Every tool still passes the install check on every run: a resolved package whose publisher or repository does not match its `Publisher:` is refused.

## Version rule

Entries carry no versions. The run picks each one: the newest non-prerelease whose registry publish time is at least 7 days old (npm `time`, PyPI `upload_time`, the Go proxy's `.info`, crates.io, NuGet), installs that exact version on every route, and lets the package manager resolve peer caps. `scripts/pick-version.sh` in the skill is that rule. apt is exempt: its versions are the distribution's.

## Yielding to the repo

- Evidence of a tool the entry lists (default or alternative) keeps that tool; only its gaps (wiring, pin, rung) are filled.
- Evidence of a tool the entry does not list keeps it, wired only through the repo's own invocation (a `package.json` script, a make or just target), else reported `unwired: <tool> (<evidence path>)`.
- A default applies only to a role with no evidence, written once at the stack root and inherited by every member without evidence of its own. A member's own evidence wins for that member. A `typecheck` or `test runner` default also needs its target (tsc a `tsconfig.json`, a test runner one test file); without it the field stays empty and the role is reported under Not acted on, since an empty suite exits nonzero and would start the turn rung red.
- Two tools in one role: the one the runner config or CI calls is active, the other "present, not wired"; asked only when both or neither are called. Never both wired.

## Affected tests

The member is the selection unit. A runner that selects natively gets the member's test command. Vitest `related` and Jest `--findRelatedTests` are used whenever that runner is present. pytest-testmon is offered as a gap proposal through the install check, and may be declined. A runner with name filters only (bats, node:test), or a declined selector, runs the affected members' whole suites. No file-name heuristics.

## Check targets

A repo's own check target, when present, is kept and called by `check.sh full`: `package.json` script `check`, `make check` (a `check:` target in `Makefile`), `just check` (a `check` recipe in `justfile`).

## Entry trials

`scripts/catalog-trial.sh <entry>|all` in the source repo proves an entry in a cloud session, on the seed tree `tests/fixtures/catalog/<entry>/clean/`: per tool, pick the version by the version rule, install by `Route:`, then run `Run:` on the clean tree, which must pass without changing a seed file, and on a copy with `tests/fixtures/catalog/<entry>/bad/<tool>/` laid over it, which must fail or change a seed file. `<tool>` is the `###` heading, lower-cased, with each run of other characters turned into `-`. A tool with `Unavailable:` is not tried. Every entry is tried before it merges and on any later PR touching it.
