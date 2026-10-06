# Phases 1, 2 and 4: understand, implement, self-review (detail)

## Contents

- [Phase 2: classify, then implement test-first](#phase-2-classify-then-implement-test-first)
- [Phase 2: delegate execution, keep judgment](#phase-2-delegate-execution-keep-judgment)
- [Phase 2: adjacent finds](#phase-2-adjacent-finds)
- [Verify the spec's external-system claims before building on them](#verify-the-specs-external-system-claims-before-building-on-them)
- [Phase 1 detail: spec precedence](#phase-1-detail-spec-precedence)
- [Phase 1 detail: anchors the issue cites](#phase-1-detail-anchors-the-issue-cites)
- [Phase 1 detail: a criterion no mechanic can perform](#phase-1-detail-a-criterion-no-mechanic-can-perform)
- [Phase 4: triage and depth checks](#phase-4-triage-and-depth-checks)
- [Phase 4 evidence lines](#phase-4-evidence-lines)
- [Consult current docs](#consult-current-docs)

## Phase 2: classify, then implement test-first

Classify the change into one of three classes and **announce the class and the
skip path it implies** ("classified `docs`: skipping TDD and phase 3, straight
to the local gate"), so a wrong label is a visible decision now, not a silently
skipped verification later.

- **`docs`**: markdown, comments, manifest text with no logic. **Skip TDD**;
  do not manufacture a contrived test. Commit `docs:`.
- **`code`**: a feature or bugfix in behavior. Invoke the `tdd` skill
  **autonomously**: red, green, refactor **without pausing for plan approval**
  (you are intentionally overriding tdd's checkpoint; the merge gate is the
  review point). A new test goes where the repo's tests for that area live, and
  a new test file is registered wherever the runner discovers files, which the
  profile's `Small node:` syntax tells you.
- **`infra`**: tooling or a refactor where a strict red-green is awkward: the
  change *is* the build, CI, a fixture or the test harness. Extract the logic
  into a testable seam and unit-test its **observable behavior** there; the
  real run in phase 3 is the integration proof.

When in doubt between `code` and `docs`, treat it as `code` and write the test.

**Tripwires are not a class.** Whatever the class, the profile's `Tripwires:`
and `In-PR requirement:` land in the same change, or a later phase goes red with
no phase explaining why.

## Phase 2: delegate execution, keep judgment

**Judgment** (the classification, the lane keys, spec interpretation,
external-claim probes, design choices, the brief) stays in the main thread on
the judgment tier. **Execution** (the failing test, the green, the refactor,
from a settled plan) is mechanical-tier work: delegate it to ONE subagent when
the plan is settled and the edit spans files you have not opened; where you can
point at the files, execute inline. Keep it inline when the issue is
exploratory, the spec is still settling, or the change touches schema or
architecture: a plan-implement loop across a subagent boundary loses too much.

Hand the subagent the worktree path, its `execute` scratch directory, the plan,
the test command and the conventions the edit needs. Require back a diff
summary, the tests added or updated, and a **structured deviations list**,
which lands verbatim in the merge summary. Two hard rules in its prompt:

- Every Edit/Write path carries the **worktree prefix**; after its first edit,
  `git -C <main-checkout> status` must be clean.
- It runs only the **targeted test nodes**; the phase-5 gate stays with the
  orchestrator.

## Phase 2: adjacent finds

A find outside the issue takes one of three dispositions and no fourth, and
phases 4 and 7 send their own out-of-scope findings back here.

- **Fix it inline** and log the deviation, where an acceptance criterion names
  it, the fix lands in a file this PR already changes, or a reviewer of this PR
  would flag it.
- **`file-issue` it** with the profile's triage marker and leave it. The
  mechanic answers `filed: false` with candidates when an open issue's title
  shares three or more tokens with yours, and each candidate is **read**: the
  same finding is linked in the deviations log rather than refiled, and
  `comment-issue` posts any evidence this run adds to it; a different one is
  refiled with `--distinct-from`. A find citing a path this PR already changes
  is refused with `in_diff`, since it is the first disposition's;
  `--outside-scope "<reason>"` files it where the reason holds.
- **Stop `mis-specified`**, where the find shows the issue itself is wrong.

The merge summary lists every issue filed and every candidate linked.

## Verify the spec's external-system claims before building on them

When the issue asserts a *causal mechanism* about something outside this
repo's code (a library behavior, a platform's response, an OS path rule),
treat it as a **hypothesis**, and confirm it against the real thing with the
cheapest probe *before* writing the fix around it; the profile's `Claims to
probe:` lines are this repo's examples. A triage brief's root cause is
frequently a plausible guess. A probe that contradicts the brief is an early
`mis-specified` stop, not a phase-3 surprise.

## Phase 1 detail: spec precedence

A later triage brief or authoritative comment can *supersede* the issue body.
When they conflict (scope reduced, an option chosen, an axis dropped), the
latest authoritative spec wins and the body's original acceptance criteria no
longer bind. Note it in the deviations log, and expect a reviewer reading the
stale body to flag "missing" requirements; reject those in phases 4 and 7 with
the comment as evidence.

## Phase 1 detail: anchors the issue cites

An issue that names a file, a heading or a step number in another skill or
file records what its author believed when writing it. Grep each one in the
worktree before planning, because a run that builds on a wrong anchor spends
its reviewer rounds unwinding it. Where the tree contradicts one, the tree
wins:

1. Rewrite the issue section the anchor sits in to match the tree with
   `update-issue-body <issue> --section <name> --body-file <path>`, the
   original section kept below the rewrite in a column-0 `<details>` block. The
   mechanic carries that `<details>` record through every later write to the
   section, so a later file holds the new content alone. An anchor in
   the preamble, which the mechanic leaves alone, is restated in the section
   whose criteria build on it.
2. Build against the rewritten criteria, and log the substitution in the
   deviations log.

A contradiction that leaves the issue nothing to build is the `mis-specified`
stop instead.

## Phase 1 detail: a criterion no mechanic can perform

A criterion that asks for a host action no mechanic performs (a repo setting, a
branch protection, an installed app) is one the run cannot meet, and a line in
the merge summary saying so is how it gets lost. Unattended, rewrite it like an
anchor above, through `update-issue-body`, restated as what the run can deliver
(the file, or the instruction naming the action), the original kept in
`<details>` and the substitution in the deviations log. Attended, ask the human
which way before building.

## Phase 4: triage and depth checks

**Auto-triage** every finding: harden rather than rip out capability, verify
nits against the pinned versions, reject known non-issues, fix the valid ones,
and record a one-line disposition per finding. Two rails on rejecting: a claim
about **what exists in the repo** is checked against `origin/HEAD` rather than
the worktree, which may predate a merge; and a finding's **evidence and its
claim are separate**, so a reviewer citing the wrong commit for a real primitive
is still right. A valid finding outside the issue is an adjacent find.

Then read the diff yourself against the depth checks in the coding-standards
file the Standards axis reads, and the sub-files it routes to, by their leading
words: a vocabulary the change extends, a rule-shaped prose change, new
pattern-matching code, a new test run with its fix reverted, removed lines with
no new home, a fix landed after review, and any the repo adds beside them.
Reviewer rounds find these otherwise, serially, at the cost of most of a run's
wall time, and the reverted-fix one escapes them entirely.

## Phase 4 evidence lines

`run-file close 4` refuses until the Run file carries these lines, each with an
optional `- ` prefix, written as its check settles:

- **Reverted-fix**, one per test file the diff adds or changes:
  `Reverted-fix: <test path>: red`, once `revert-red <test> <path>...` exits 0
  (the test went red with the fix reverted; commit the test and the fix first,
  it reads committed state), or `Reverted-fix: <test path>: n/a: <reason>` where
  there is no fix to revert. Exit 1 means the test stayed green: it proves
  nothing, so fix the test.
- **Dropped**, one per block `dropped-lines` reports, removed lines in blocks of
  three or more with no matching added line anywhere in the diff:
  `Dropped: <file>:<line> re-homed at <path>`, or
  `Dropped: <file>:<line> dropped on purpose: <why>`.
- **Near-miss**, for each script whose added lines hold a new pattern matcher, a
  line per kind, the test path holding a case that must be refused:
  `Near-miss: <script>: <kind>: <test path>`. The kinds are `partial-token` (the
  token inside a longer word), `quoted`, `indented`, `unbalanced` (an opener
  with no closer) and `unreadable` (the input the matcher reads cannot be read).
  A kind with no case says why, `Near-miss: <script>: <kind>: n/a: <reason>`,
  and one `Near-miss: <script>: n/a: <reason>` covers all five.
- **Probe**, one per self-review decline `Declined: <ref>: <reason>` whose
  reason claims behaviour (already handled, already covered, can't happen, never
  happens, closes at merge): `Probe: <ref>: <command> => <output>`, the command
  you ran and the output it printed. A decline that claims no
  behaviour needs none.

## Consult current docs

While implementing or triaging findings (phases 2, 4 and 7), verify API claims
against **current** docs through the `find-docs` skill and the extra `Sources:`
the profile names. For every library on the profile's `Pinned:` line, read the
installed version from the repo's manifest and confirm the claim against that
version before acting on it; a remembered API the installed version lacks is a
regression.
