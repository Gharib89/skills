# Standards: tests

Tests: anything under `tests/`. The kinds of test this repo runs, and how each
is driven, are listed once, in the ship profile's `## Local gate` section in
[docs/agents/ship.md](../../agents/ship.md); a new kind adds its line there. The
index's clock exception bounds the clock rule below.

## Proving a test

- **A behavioural claim about a mechanic or gate script earns a case in the
  suite.** A PR that adds or changes what a script does adds the case that
  shows it, under `tests/`, where it survives the run that made it; a
  scratchpad probe does not.
- **A new test is run once with the fix reverted, and confirmed red.** A test
  written to prove a fix proves nothing until it has failed for the reason it
  exists: revert the hunk, watch the case fail, restore it, watch it pass. A
  case can stay green with its fix reverted because an earlier step it drives
  fails first, and it survives until someone happens to mutate it. Neither
  reviewer can see this from a diff: a vacuous assertion reads exactly like a
  sound one, so the proof is the author's and belongs before the push.
  `skills/ship/scripts/revert-red.sh <test> <path>...`, Ship's mechanic, runs
  that revert and exits 0 only when the test goes red; commit the test and the
  fix first, since it reads committed state. `run-file close 4` refuses without
  a `Reverted-fix:` line per test file the diff adds or changes.
- **A negated fixture accompanies a test that asserts on prose.** Assert on a
  word the change introduced, and run the assertion once against the sentence
  with its meaning negated: it must fail. An assertion on a word the old text
  already held stays green whatever the change did.
- **A test asserts exactly what its name claims.** A case named for a refusal
  asserts the refusal's exit code and reason, not only that something failed;
  a name that claims more than the assertion checks reads as coverage that is
  not there.
- **A validator gets a negative control.** Beside the inputs it must accept, a
  validator's test carries one it must refuse, because a validator that accepts
  everything passes every positive case.
- **Folding or deleting a test names what each removed case uniquely covered.**
  Under the PR body's `## Special things to note`, list each case removed and
  the case that now covers what it alone covered, or say the coverage is
  dropped and why. A refactor of the suite otherwise drops coverage with every
  test still green.

## Fixtures, fakes and stubs

- **A fixture holds exactly one violation.** A failing fixture carrying two lets
  the case pass while only one of the checks it is named for works; a passing
  fixture beside it holds none.
- **A Host fake default is an answer some real adapter returns.** A default
  shape no host sends proves the mechanic against nothing, and the mechanic then
  meets the real shape for the first time in a consumer's run.
- **A stub that is asserted on records to a file on disk.** Any `$( )`, pipe or
  `&` on the path between the code under test and the stub runs the stub in a
  subshell, where `LAST_PATH=$1` dies with it and the assertion reads empty
  whatever the function did: a test that fails on correct code, the expensive
  direction. `pathlog=$(mktemp)`, paired with its trap, then
  `api() { printf '%s\n' "$1" > "$pathlog"; ...; }` and assert on
  `$(cat "$pathlog")`. Check how the code calls the stub before writing the
  recorder.
- **A test that asserts on a time reads the clock only through a stub it
  controls.** A fixture whose result depends on the time of day is a defect
  rather than a flake, so put a `date` stub on PATH and assert against the time
  that stub returns. A fixture that hardcodes a late hour, or computes now plus
  two minutes, goes red when the run crosses midnight.
- **A test that makes a file unreadable skips under root.** `chmod 000` does not
  stop root from reading the file, and a Cloud sandbox runs as root, so guard
  the case on `[ "$(id -u)" -ne 0 ]` and report it skipped there rather than
  letting it fail for the wrong reason.
