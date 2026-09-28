# The check ladder: check.sh, the hooks and the budgets

## Contents

- [The rungs](#the-rungs)
- [Writing check.sh](#writing-checksh)
- [Writing the hooks](#writing-the-hooks)
- [Budgets](#budgets)
- [Timing the rungs](#timing-the-rungs)

## The rungs

| Rung | Runs | Trigger | Budget (deadline / hook `timeout`) |
|---|---|---|---|
| `edit` | lint and format, fix mode, through the pre-commit runner on the edited file | `PostToolUse` on `Edit\|Write` | 5 s / 15 s, per file invocation |
| `turn` | typecheck plus affected tests of each member the uncommitted changes touch | `Stop` | 60 s / 75 s |
| commit | the runner's own git hook | `git commit` | 30 s, measured only |
| `full` | runner on every file, every member's typecheck and whole suite, the repo's check target | a human, CI, Ship's local gate | 10 min, measured only |

The linter set is defined once, in the runner config; `check.sh` calls a linter directly only when the runner cannot take a file list (lint-staged). Typecheck and tests live in `check.sh`. There is no `commit` subcommand: the commit rung is the runner's git hook.

The contract every caller parses: stdout is one JSON line `{"rung","verdict","checks":{<name>:<status>}}`, status `pass | fail | unavailable | skipped | over-budget`; stderr carries each failing check's last 40 lines; exit 0 pass, 1 fail, 2 unavailable or tooling, 3 over budget. `CHECK_DEADLINE=<epoch s>` makes `check.sh` stop at that time, mark the check running at that time `over-budget` (none, when the deadline fell between checks) and the rest `skipped`, and exit 3; without it exit 3 never occurs. A failure outranks an over-budget check, so a real failure still blocks.

## Writing check.sh

Copy [templates/check.sh](../templates/check.sh) to `scripts/check.sh`, executable, and fill only the block between `# >>> setup-harness configuration` and `# <<< setup-harness configuration`:

- `EDIT_GLOBS`: shell globs on the file name for every extension the runner config covers (`'*.py *.pyi *.ts *.tsx *.sh'`), plus the basename of each extensionless file detection claimed by shebang (`deploy`). A file matching none is `skipped` fast, so the `PostToolUse` entry needs no per-extension `if`.
- `EDIT_RUN`: the runner on a file list, `prek run --files {files}` (or `pre-commit run --files {files}`, `lefthook run pre-commit --file {files}`). `check.sh` runs it twice when the first run fails: the first run's fixes fail it, and only what the fixes leave fails the second.
- `FULL_RUN`: the runner on every file, `prek run --all-files`.
- `TURN_ROWS`: one row per member, `<path prefix>|<member>|<globs>|<typecheck>|<tests>|<affected tests>`. The prefix ends in `/` (`api/`, `packages/web/`), or is empty for a member at the repo root. Globs are the stack's extensions plus its manifest names, so a manifest change re-checks the member. Commands run in the member's directory, prefixed with the stack's exec command (`uv run --frozen mypy .`, `pnpm exec tsc --noEmit`). `<affected tests>` takes `{files}` relative to the member (`pnpm exec vitest related --run {files}`); leave it empty to run `<tests>`, the member's whole suite. An empty typecheck or tests field is no check.
- `FULL_ROWS`: extra checks on `full` only, `<name>|<command>` from the root: the repo's own check target (`check-target|make check`).

A changed file matching some row's globs under no row's prefix reports `new-root: unavailable` with "re-run setup-harness": a stack root appeared that this file has no row for. A repo's existing check target is kept and called from `FULL_ROWS`, never replaced.

## Writing the hooks

Copy [templates/check-hook.sh](../templates/check-hook.sh) to `.claude/hooks/check-hook.sh`, executable, and fill its configuration block: `CHECK` is the profile's `Location:`; `EDIT_BUDGET` and `TURN_BUDGET` are the deadlines in seconds from the profile's `## Budgets` (`default` is 5 and 60, `override <N>s: ...` is N). Then merge [templates/settings-hooks.json](../templates/settings-hooks.json) into `.claude/settings.json`, each `timeout` set to the deadline plus max(10 s, deadline / 4): 15 and 75 at the defaults. Every entry carries a `timeout`: a hook that times out passes silently, and the default is 600 s.

Merge beside what the repo has: keep every existing hook entry, add these two, and never duplicate one already present. Hooks live in `.claude/hooks/`, never in a plugin: a cloud session does not install repo-enabled plugins.

What the wrapper does, so the report can say it:

- `edit` reads `tool_input.file_path` from the hook's stdin and runs `check.sh edit <file>` under the edit deadline.
- `turn` fingerprints the working tree with a throwaway index (`git write-tree`, milliseconds, the real index untouched) and skips the check when the tree matches the last one checked, stored under `.git/`. A tree unchanged since a failing check lets the stop through and tells the human, continuation (`stop_hook_active`) or not, so Claude never loops on a failure it has not touched.
- `check.sh` exit 1 becomes hook exit 2 with the failure output on stderr, capped under Claude Code's 10k-character limit, which is the one failure Claude reads. Exit 2 (a tool missing) and exit 3 (over budget) become a `systemMessage` to the human and never block.

## Budgets

The defaults are the table's. The profile overrides one rung only with the human's reason, `override <N>s: <reason>`; the skill never raises a budget on its own, and a budget measured per repo is not a thing it offers. The edit budget covers one invocation: sync `PostToolUse` hooks run one after another, so a batch of N edits costs N times the edit time.

## Timing the rungs

Time with the wrapper's own clock, whole seconds (`start=$(date +%s)`; Bash 3.2 has no sub-second clock and macOS no `timeout`). Run each rung twice: the first is cold, reported; the second is warm, judged against the budget.

- `edit`: the largest tracked file per extension `EDIT_GLOBS` covers, one invocation each. Fix mode on a clean file writes nothing.
- `turn` and commit: the files of the last commit that touched a member's source, `scripts/check.sh turn <files>` and the runner's hook on those files (`prek run --files <files>`).
- `full`: one run of `scripts/check.sh full`.

A rung that fails while timing is the repo's code, not the harness: report `<rung>: fail (<check>)` with its time "not judged".

A warm time over budget gets three offers, in order, each with a recommendation: **narrow** the check to the file set where its tool allows; **demote** it to the next rung (a slow linter to `turn`, a slow typecheck to `full`); **override** the budget with the human's reason. No hook is written for a rung over its budget until one of the three is applied, and the rung is timed again after. Commit and `full` are measured only: over budget is reported `over`, with no offer.
