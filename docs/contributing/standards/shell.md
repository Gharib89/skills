# Standards: shell scripts

Shell scripts: a mechanic, a host adapter, a template a skill lands, a script
under `scripts/` or `tests/`. The index's portability scope and quoting
exceptions bound these rules.

## The mechanic contract

- **Mechanics print JSON and nothing else on stdout.** Evidence goes to stderr,
  capped at the last 40 lines, with the message of every exit-1 and exit-2
  error. Exit 0 success, 1 the operation failed, 2 tooling. The one call that
  prints something else is `--help`, which every mechanic answers, on stdout,
  with its usage line then its header's `stdout:` block and exit 0 through
  `ship_help`, called before `ship_load_host` so the answer reaches no host.
  What a run makes of all this is
  [skills/ship/reference/mechanics.md](../../../skills/ship/reference/mechanics.md);
  the `contract` gate enforces it.
- **No host CLI outside a named mechanic.** In this repo's code, `gh` and `az`
  are called only from `skills/ship/scripts/host/<host>.sh`; a host write or
  gating read no mechanic performs is a ship defect, not a prose fallback. A run
  itself may make an informational read no mechanic covers through the host's
  REST form, listed in its Run file's `## Direct reads`, and that is no
  violation of this rule. One documented exception: a CI template under
  `skills/setup-skills/reviewers/`, and this repo's own copy of one under
  `.github/workflows/`, calls `gh` directly. It runs on a runner in a consumer
  repo that has no mechanics checked out, so there is nothing to route through.
  A second: `update-skills`' `heads` reads GitHub's public REST API with `curl`,
  whatever the checkout's host, because the upstreams it reads are GitHub repos
  and an Azure DevOps checkout has no GitHub adapter or credentials to route
  through. A third: `scripts/check-pr-body.sh` reads each `Closes #N` title with
  `gh` as printed evidence, which decides nothing, and it runs in the
  `bump-guard` leg, which loads no adapter.
- **A host create posts once, through create-then-verify.** A 5xx can be the
  response lost on the way back from a POST that landed, so a create is never
  sent through a retrying wrapper: it re-reads before it retries, the way
  `_gh_create_verify` in the GitHub adapter does. A list endpoint whose whole
  set decides the answer is paged until it ends, because one page truncates the
  list with no error. A path variable (a branch, a ref, a file path) is
  URI-encoded, because a `/` or `#` in it otherwise addresses another resource.
  A read that needs only the newest items, the verify read after a create, sorts
  and bounds its page instead.
- **A failed read is never a verdict.** A read that fails (a missing tool, a
  nonzero exit, empty or unparseable output) exits 2 or answers `unavailable`;
  it is never compared, graded or passed on as data. Write the status check
  before the parse: keep the exit status apart from the parsed output rather
  than reading both out of one pipeline, give every `case $?` a failing `*)`
  arm, and use `jq -e` where the value decides the answer. Every instance is a
  silent pass: jq missing makes both sides of a comparison print nothing, and
  `cmp` of two empty outputs exits 0.
- **A mechanic's header is its contract.** The header comment of a mechanic or
  gate script lists its output keys and exit meanings, and each moves in the
  same hunk as the code that changes it. A header that drifted is what the next
  author reads instead of the code.
- **Moving a default or deleting a guard lists every call path that relied on
  it.** Under the PR body's `## Special things to note`, name each caller that
  reached the old default or guard and what it gets now. A PR promising no
  behaviour change keeps that promise only on the paths someone listed.

## Bash

- **Everything under `skills/` targets Bash 3.2.** A mechanic and its host
  adapter reach a consumer machine as a derived copy and run in whatever shell
  that machine provides, macOS's system Bash included: no `mapfile` or
  `readarray`, no `declare -A`, no `${var,,}` or `${var^^}`. The failure mode is
  why it is a rule rather than a preference: the mechanics run
  `set -uo pipefail` with no `set -e`, so on Bash 3.2 `mapfile` prints
  `command not found`, execution continues, and the mechanic answers on whatever
  the failed call left behind, which is nothing. A silent pass, where a
  portability nit would be a loud one. The other constructs fail differently
  (`declare -A` reports an invalid option, `${var,,}` is a bad substitution that
  aborts the script), and none of them is caught by reading the diff on a
  machine running Bash 5. **Precedent for a mechanic comes from `skills/`
  alone**, whatever idiom a repo-local script uses. The `contract` gate fails on
  the four constructs named here; the rule is wider than the grep, so a Bash 4
  feature it does not name is still a violation.
- **Every executed script sets `-u` and `-o pipefail`.** A mechanic sets `set
  -uo pipefail` and no `-e`, so a failed step reaches the code that turns it
  into a JSON answer; a script with no such answer to give, such as the Cloud
  bootstrap script setup-skills lands, may add `-e`. A file only ever sourced
  (`_lib.sh`, a host adapter, `tests/lib.sh`, a fake) inherits its caller's
  options and sets none, so it does not change them under the caller.
- **Quote every expansion Bash would split or glob.** An unquoted `$var` in a
  command's arguments splits on whitespace and expands `*`, so a path with a
  space becomes two arguments. The places Bash never splits are the index's
  quoting exceptions.
- **Every `mktemp` is paired with a trap.** `trap 'rm -f "$f"' EXIT` at script
  top level, `trap 'rm -f "$f"; trap - RETURN' RETURN` for a file created inside
  a function. An interrupted run between the `mktemp` and the `rm -f` otherwise
  leaves the file in the system temp directory. The RETURN trap clears itself
  because bash leaves it armed after the function returns, so it would fire
  again in the caller, where the callee's `local` is out of scope and `set -u`
  aborts the mechanic. The one exception is a function called from another
  function that already holds a RETURN trap: a RETURN trap set in the callee
  REPLACES the caller's rather than nesting under it, so arming one disarms the
  caller's cleanup. The callee then takes an explicit `rm -f` instead, and only
  where it has a single exit path for that `rm` to sit on; the comment says
  which caller's trap it is protecting.

## Matching and comparing

- **New pattern-matching code is tested against adversarial inputs.** Delimiters
  inside the field, option groups, field-versus-line anchoring, and the path
  where the tooling itself fails; and the inputs reviewers keep finding: an
  empty value, a sentinel equal to another sentinel, an argument with spaces,
  `..` or an absolute path, a prerelease version, a GFM table's alignment row, a
  title prefix a human can type, and decoy text outside the block being
  validated. Ten lines of regex read as correct and answer wrong on the input
  nobody wrote a case for. Ship's `run-file close 4` holds a script whose
  added lines match a regex to a `Near-miss:` table (the evidence lines in
  `skills/ship/reference/implement.md`).
- **Both sides of a comparison pass through one normalising step.** An identity
  (a login's case, a `[bot]` suffix) or a timestamp (`Z` against `+00:00`,
  fractional seconds) read from two sources goes through the same function on
  each side before it is compared, rather than one side being reshaped to match
  the other's format. Otherwise the comparison fails on format while the values
  agree, or passes on a format both sides lost.
