---
name: ship
description: >-
  Drive one tracker issue to a merge-ready PR in a single run, stopping only at
  the human merge gate. Use when the user wants to ship an issue, or to run the
  unattended lane.
argument-hint: "[issue-number] [--unattended]"
metadata:
  version: 4.1.0
  profile-schema: 2
  composes: mattpocock/skills:tdd mattpocock/skills:writing-for-agents mattpocock/skills:code-review upstash/context7:find-docs humanlayer/skills:show-me
---

# ship

Drive one issue from nothing to a **merge-ready PR**, hands-off, stopping only
at the merge gate. The human runs `/ship <issue>`, walks away, and comes back to
a PR implemented test-first, verified against the real thing the repo
integrates with, self-reviewed, reviewed by every reviewer the repo names, and
CI-green, with every decision summarized for a ten-second approve.

This skill is **generic**. It knows how to ship; it knows nothing about the
repo. Every repo fact comes from the **ship profile**, `docs/agents/ship.md`.
The copy under `.claude/skills/ship` is a **derived copy**:
never edit it in place; the repo's `### Ship` block in CLAUDE.md carries the
refresh command.

**Version.** Print `ship <version>` in the run header, the first line of the
first reply, and again in the merge summary, so every PR records which ship
produced it. The harness strips this file's frontmatter on load, so the version
is not in your context: read it once, at the start of the run, with
`sed -n 's/^  version: //p' <base directory>/SKILL.md`.

## Argument and flags

`$ARGUMENTS`:

- `<issue>`: the issue number (work item id on Azure DevOps). Omitted with no
  flag: ask which issue.
- Free text instead of a number: treat it as the task spec directly. No issue
  fetch, no claim, no `Closes`, no reflect; everything else runs. `none` is the
  issue argument these five mechanics accept: `preflight none`,
  `isolate none <type> <slug>`, `open-pr none ...`, `merge <pr> none` and
  `cleanup none`. The three that cannot take it (`read-issue`, `manage-issue`,
  `reflect`) have no meaning without an issue.
- `--unattended`: the **unattended run**. No human is present: a blocked stop
  hands back instead of asking, the sandbox clone is the isolation, and the
  merge gate posts the summary as a PR comment and returns. It starts with
  `tooling --install`, because the cloud sandbox image lacks the host's CLI.
  With no `<issue>` it runs the whole unattended lane (tooling, bootstrap, PR
  cap, select) before the pipeline:
  [reference/unattended.md](reference/unattended.md).

Without `--unattended` the run is **attended**: any needed human action stops
and asks, and the claim holds while it waits.

## The ship profile

Load `docs/agents/ship.md` **once, whole, at preflight**, the way a session
loads `docs/agents/issue-tracker.md`. It has fourteen fixed `##` headings, every
one always present; a defaulted axis reads `None.` or `Default.`. Facts sit on
`Label:` lines; the prose under a heading explains, and never carries a fact.
You read the profile and pass its facts to the mechanics as arguments; no script
parses markdown.

Two more repo docs feed a run and are read the same way: triage roles
(`ready-for-agent`, `ready-for-human`, `needs-triage`) are canonical role names
whose label strings come from `docs/agents/triage-labels.md`, and the tracker's
mechanics come from `docs/agents/issue-tracker.md`.

**Profile schema.** Directly under the `# Ship profile` title, before the first
`##`, the profile carries `Schema: N`. This skill declares the schema it reads as
`metadata.profile-schema` in the frontmatter above. The number is separate from
`metadata.version`: it moves only when ship's expectations of the profile change
(a heading or `Label:` line added, renamed or removed; a `Label:` vocabulary
changed), always with a ship major bump, never for a behaviour change that
leaves the profile alone. Preflight compares the two and refuses a mismatch in
either direction, in both lanes, never claimed; the detail names both numbers
and the fix.

A profile older than ship is refused even where ship could default the missing
axis: a defaulted axis reads `None.`/`Default.` explicitly, never an omitted
heading.

Missing file: stop `profile missing`, naming `docs/agents/ship.md` and
`/setup-skills`. Missing or misordered headings: stop `profile invalid`, naming
them. A fact the current run needs that reads `None.` where it cannot be none is also
`profile invalid`; a fact the run will not touch is never checked. The reviewer
blocks are the exception, checked whatever the run touches, because preflight
parses them: an on-request reviewer with no `Cap:`, a `Fallback-for:` on a
reviewer that is not on-request, and a `Fallback-for:` naming a reviewer the
profile does not list are all refused there, before the claim.

**Re-validate an edited profile with `preflight none`.** A run that changes the
profile, or refreshes the ship copy that reads it, proves the new pair with the
issueless call, whose verdict is about the profile and the host alone. Do not
re-run `preflight <issue>` for this: after the claim it always answers
`already claimed` plus `worktree exists` and exits 1, so the profile never
appears in `reasons` whether it is valid or not, and reading it green out of
that is elimination, not an answer.

## Generic mechanics: the only way to touch the host

`scripts/` holds one executable per deterministic step. Each prints one JSON
verdict on stdout, a failing step's last 40 log lines on stderr, and exits
`0` ok, `1` the mechanic's own not-ok answer, `2` tooling. A malformed
invocation is tooling, never exit 1: a missing or empty positional, a flag where
a positional belongs and a flag without its value all print
`{"error": "<usage>"}` and exit 2, as an unknown flag does. Exit 1 is an
answer, not always a fault: `nothing-ready` from `select`, a not-actionable
`preflight` and a `poll-pr` window that closed are all exit 1 and none is red.
Read the JSON, then decide. When a phase names a mechanic, run it
instead of re-deriving what it wraps; it is the single source of truth for that
step, including the host adapter it sources (`scripts/host/github.sh` or
`scripts/host/ado.sh`, chosen from the `origin` remote).

**You never run `gh` or `az` yourself in a ship run.** Every host interaction
goes through a named mechanic, and a missing operation is a **Ship defect**:
report it on the merge summary's `Ship defects:` row for the human to carry
upstream, never hand-roll the call, and never file it to another repo.
Reads come back in one vocabulary on both hosts: checks
`pending|success|failure`, mergeable `clean|conflict|unknown`, review
`approved|changes|comment`, and threads as `resolved: true|false` per thread, or
the whole `threads` field as the string `"unavailable"` when the state could not
be read.

| Mechanic | Phase |
|---|---|
| `preflight <issue \| none> [--unattended]` | 0 |
| `read-issue <issue>` | 0 |
| `isolate <issue \| none> <type> <slug> [--carry <file>...] [--in-place]` | 0 |
| `manage-issue <issue> take \| release \| handback "<reason>" \| close` | 1; any stop after the claim; 3, to close a scratch issue a verification created; 9 |
| `file-issue --title --body-file --label <marker> [--distinct-from <n>[,<n>]]` | 2, 4, 7 |
| `base-fresh` | 5, and after every conflict resolution |
| `<Location:>` from the profile `[--small <node>] [--base <ref>]` | 5 (the repo's own local gate) |
| `open-pr <issue \| none> --title --body-file` | 6 |
| `reflect <issue> <pr>` | 6 |
| `update-pr-title <pr> --title` | 6, 9 |
| `read-pr <pr>` | 6 and 7, reading a PR back after a title or body write |
| `poll-pr <pr> [--brief] [--await-review <login>] [--since <iso>] [--full <id>[,<id>]] [--timeout <s>] [--interval <s>]` | 7, 8 |
| `request-review <pr> <login> [--comment <phrase>]` | 7 |
| `comment-pr <pr> --body-file` | 7, 9 |
| `reply-thread <pr> <thread> --body-file` | 7 |
| `update-pr-body <pr> --section Review --body-file` | 7 |
| `resolve-thread <pr> <thread>` | 7 |
| `ci-wait <pr> [--timeout <s>] [--interval <s>]` | 8 |
| `merge <pr> <issue \| none> --worktree <path>` | 9, on approval |
| `cleanup <issue \| none>` | 9, after merge |
| `tooling [--install]`, `list-prs --open` and `select` | unattended lane |

Run mechanics **inline**: they project their own output, so a subagent there
burns budget to relay what an exit code already says. Poll loops are bounded
and foreground; reaching the bound is never permission to proceed. Re-run to
extend, or pass a wider `--timeout` up front when the profile's `Legs:` names a
leg you know is slower than the bound.

## The autonomy contract

One guaranteed stop, the **merge gate**: merging is effectively irreversible,
so a human says merge. Ship never merges on its own and never uses an
auto-merge flag. Two conditional pauses in an attended run: the `ambiguous`
stop (phase 1, the issue is too vague to plan) and a **hand-off** (phase 3, a
verification's prerequisite is missing and its disposition says so). Everything
else, triaging your own findings, fixing, re-running, is autonomous. Before
ending a turn, check your last paragraph: if it states a plan, a next step or an
intention ("I'll re-run the poll") rather than having done it, do it now with a
tool call instead of stopping. That clause is about a plan, never about a wait:
while a composed skill's subagents are out, ending the turn *is* the action, per
[reference/context-discipline.md](reference/context-discipline.md).

**Never proceed on red.** Any failure before the merge gate gets a bounded
self-fix-and-retry, about two attempts. Still red, or the failure says the
approach is wrong: **stop and report** with the concrete evidence and, if
cheap, a verified-working alternative, so the report is a fast yes.

**Every stop has a name** and a claim action. Report the name verbatim; a
sibling maps it, a human reads it.

| Stop | Reason | Claim |
|---|---|---|
| Profile missing or invalid, host unreachable | `profile missing`, `profile invalid: <detail>`, `host-unreachable` | never claimed |
| A skill ship composes is not installed | `skill missing: <skill>; run <install line>` | never claimed |
| Preflight not actionable | `closed`, `is a pull request`, `already claimed`, `existing PR`, `existing branch`, `worktree exists`, `not triaged: run /triage first`, `ready-for-human: attended only` | never claimed |
| Issue too vague to plan | `ambiguous` | never claimed |
| Change outgrows one PR, or needs a redesign the issue never scoped | `needs-split` | attended: ask; unattended: hand back |
| A find shows the issue is mis-specified | `mis-specified` | attended: ask; unattended: hand back |
| Verification prerequisite missing | `hand-off` (attended waits, claim holds) / `blocked-verification` | attended: hold; unattended: hand back |
| Local gate verdict `unavailable` | `local gate unavailable: <gates>` | attended: ask; unattended: hand back |
| Carried file changed | `carried file modified: <file>` | attended: ask; unattended: hand back |
| Red after retries | `red-after-retry: <what>` | attended: ask; unattended: hand back |
| The branch fell behind its base before the merge | `stale-base: behind <n> on <base>` | attended: holds while you rebase; unattended: hand back |
| The PR is closed at the merge gate | `pr-closed: <state>` | attended: ask; unattended: hand back |
| Cloud-lane `Bootstrap:` failed | `bootstrap-failed` | never claimed |
| Open PRs at or above the profile's `PR cap:` | `pr-queue-full` | never claimed |
| No issue passes selection | `nothing-ready` | never claimed |
| The host's blocker query exists and failed | `blockers-unavailable` | never claimed |
| Merge gate reached | none: the run's success | holds until merge |

Hand-back is `manage-issue <issue> handback "<reason>"`: unassign, drop
`ready-for-agent`, add `ready-for-human`, comment the reason. In an attended run
you stop and ask; only if the human says stop do you hand back. Never hand back
to the agent queue: that loops forever. A hand-back that prints
`claim: released` and still exits 1 did release the claim; read `handed_back`
and report which label is missing rather than a clean stop. One that prints
`{"error": ...}` instead failed before the unassign landed: the claim is still
held and the stop is unresolved.

## Consult current docs

While implementing (phase 2) or triaging findings (phases 4 and 7), verify API
claims against **current** docs through the `find-docs` skill and the extra
`Sources:` the profile names, never memory. For every library on the profile's
`Pinned:` line, read the installed version from the repo's manifest and confirm
the claim against that version before acting on it; a remembered API the
installed version lacks is a regression.

## Model tiers

Use the cheapest model that fits; reserve the strong tier for judgment. Tag
every subagent with a model explicitly, never default-inherit.

| Work | Model |
|---|---|
| Investigation and mapping | haiku |
| Phase-2 **execution** from a settled plan; mechanical edits and fixes; the docs-sync pass on human prose; the `code-review` skill's **Spec** axis | sonnet |
| Phase-2 **judgment** (classification, plan, design, the implementation brief); triage of every finding; the `writing-for-agents` pass; the `code-review` skill's **Standards** axis | opus |

When you invoke `code-review`, tier its two axes yourself. Fall back to the
nearest available tier rather than running everything on one model.

## Working standards

These bind every edit a run makes, in every repo, regardless of a personal
`~/.claude/CLAUDE.md`, `~/.claude/rules/` or personal skills:

- **Simplest shape that solves the problem.** No speculative features,
  configurability or abstraction for single-use code. If the diff could be a
  third the size, rewrite it.
- **Surgical.** Touch only what the issue needs; every changed line traces to
  it or to a logged deviation. Match existing style. Leave adjacent code,
  comments and formatting alone.
- **Root cause, not symptom.** No temporary patches, no swallowed errors, no
  `TODO` standing in for the fix. If the real fix is out of scope, say so and
  file it.
- **Comments record the why.** Document public APIs and non-obvious
  constraints, invariants and workarounds. Skip narrative comments on
  internals.
- **Concise PR body, always the why.** State what changed and why; the reader
  has the diff for the how. The merge summary is exempt: write it uncompressed
  per [reference/merge-gate.md](reference/merge-gate.md).

## The lanes

Every run is **full lane** until the change proves it **small**: all three keys
hold, asserted by you at phase 2 and announced with the class, never confirmed
with anyone. When unsure, it is not small.

1. **No public-surface change.** The public surface is the profile's
   `## Public surface`; `Default.` means the exported or published API, CLI
   flags and exit codes, config schema, file formats and documented behavior.
2. **Provable without the real thing.** A unit or regression test fully proves
   it, or the class is `docs` and there is no behavior to test; either way no
   verification in the profile's `## Verification` applies.
3. **Single-concern.** No new dependency, none of the profile's `Tripwires:`
   fired, no new logic branch beyond the fix itself.

Behavior change is allowed: a bugfix is one. Small means narrow, locally
provable and invisible to the public surface. Small: read
[reference/small-lane.md](reference/small-lane.md) before continuing. Its
floor is the same in every repo, and the lane revokes one way only.

## The pipeline

Work the phases in order, keeping the main thread on orchestration and
decisions. **First**, read
[reference/context-discipline.md](reference/context-discipline.md): the
delegation rule, the levers that keep a long run from bloating the window, and
your **required first action, the Run file** holding the ten-item checklist.
Phase 0 starts once the Run file exists.

**Compose, don't reinline.** Load `tdd` (phase 2), `writing-for-agents`
(phase 4, agent-facing docs), `code-review` (phase 4), `show-me` (phase 6, the
Summary's Shape) and `find-docs` (any API claim) through the Skill tool when
their moment comes; never hand-roll their logic. Any skill you compose that
has an unattended mode is told the run is unattended explicitly; it has no
other way to know. The frontmatter's
`composes` line is this same list with each skill's source repo, and is what
phase 0 checks: a skill added here is added there too, or the run still fails
at the phase that loads it.

**0 · Isolate.** Run `preflight <issue>`, adding `--unattended` in an unattended
run, which is what turns a `ready-for-human` issue into the
`ready-for-human: attended only` stop; a bare call admits it. It proves tooling
and identity, and **push permission first where the host can answer it** (every
read-only call succeeds for an account that cannot push, so a wrong account
stays invisible until the merge answers 404). Azure DevOps has no cheap push
probe: preflight returns `unknown`, warns on stderr and continues, so read the
warning before trusting `ok: true` and name the unproven check in the merge
summary. It cross-checks `## Host` against the remote, loads and validates the
profile headings, confirms every skill on ship's `composes` line is installed
under this checkout's `.claude/skills/`, one `skill missing` reason per absent
skill, prunes worktrees whose PR is merged or closed, and collects every
not-actionable reason. Admission: `ready-for-agent` always; `ready-for-human` in an
attended run only; anything else is `not triaged`.
An assignee, including your own identity, is `already claimed`; stale-claim
recovery is a human unassigning by hand. `existing PR` means a live PR whose
body **closes** this issue or whose head branch ends in `-<issue>`; PRs that
merely mention it come back as `mentions[]`, context for phase 1, never a stop,
alongside a `mentioned_by[]` row per live cross-reference, open issues and
open or merged PRs both, naming its `kind` and `state`.

Then `read-issue <issue>`: the branch `<type>` and `<slug>` are derived from the
issue.

Now isolate. Attended: `isolate <issue> <type> <slug>` with the profile's
`Carry:` files. It resolves the main checkout through `--git-common-dir`,
fetches, branches from `origin/HEAD`, creates the sibling worktree
`<parent>/<repo>.worktrees/<slug>-<issue>`, copies the carried files in one
way, and prints the path. Unattended: `isolate ... --in-place`, because the
sandbox clone is the isolation; same fetch and branch, no worktree, no carry.
Work from the printed worktree path; every edit uses an absolute path under it.
Never `EnterWorktree` or a bare `git worktree add`: only `isolate` lands the
worktree at the path and branch preflight checks, with the `Carry:` files copied
in. Branch `<type>/<slug>-<issue>`, `<type>` matching the
issue (`feat`, `fix`, `docs`, ...); the `-<issue>` suffix is what preflight
greps. Every edit, commit and the PR happen from this branch. **Commit as you
go**: the PR needs real commits. The branch type is a label; the squash
subject, not the branch, is what release tooling reads. A `Bootstrap:` under
`## Worktree` runs once here, after isolate.

**1 · Understand.** Work from phase 0's `read-issue` result: title, body,
labels, assignee, state, comments, open blockers. Derive what success looks
like. A later authoritative comment supersedes the body (**spec precedence**,
detailed in [reference/implement.md](reference/implement.md)). Too vague to
plan: stop
`ambiguous`, unclaimed. Otherwise **claim before any work**:
`manage-issue <issue> take`, idempotent, which assigns you and posts the fixed
comment `🤖 Claimed by a ship run: implementation in progress.` The claim
holds until merge; every stop after this point follows the stop table.

**2 · Implement.** Classify `docs` / `code` / `infra`; **announce the class,
the skip path it implies, and whether the three lane keys hold**; announce the
applicable verifications from `## Verification` (their `Applies when:` lines
are prose you judge here) or the skip. Then implement test-first per class:
classes, the TDD override, external-claim probes, and the judgment/execution
split in [reference/implement.md](reference/implement.md). The profile's
`Tripwires:` and `In-PR requirement:` apply whatever the class: a bundle
rebuild or a version bump CI enforces lands in this change, or phase 8 goes red
with no phase explaining why. Keep a **deviations log** from the first edit:
whenever the territory forces a departure from the issue, brief or plan,
resolve it by the conservative option, log what and why, keep going; the log
lands verbatim in the PR body and the merge summary. An **adjacent find** has
three dispositions and no fourth. **Fix it inline** and log the deviation when
any of three hold: an acceptance criterion names it, the fix lands in a file
this PR already changes, or a reviewer of this PR would flag it. Otherwise
**`file-issue` it** with the profile's triage marker and leave it; the mechanic
answers `filed: false` with candidates when an open issue's title shares three
or more tokens with yours. Read each candidate: the same finding is linked in
the deviations log rather than refiled, a different one is refiled with
`--distinct-from`. Or the find shows the issue is **mis-specified**, so stop
`mis-specified`. The merge summary lists every issue filed and every candidate
linked. If the core work balloons (the diff outgrows one PR, or the fix
demands a redesign the issue never scoped), stop `needs-split` with a split
proposal. Phase 2 is done
when the applicable tests are green (red first, per class), `Tripwires:` and
`In-PR requirement:` have landed, the deviations log is current, and every
adjacent find carries one of the three dispositions.

**3 · Verify.** For each applicable verification, run its `Run:` line scoped
to what you touched, on the environment the issue was reported against; green
elsewhere is not fixed. Result words: `pass | fail | deferred-to-ci |
unavailable | unexercised`. Prerequisite (`Needs:`) missing: follow
`Without it:`. `hand-off` prints the exact command and setup and waits
(attended) or hands back (unattended); `defer-to-ci` continues only because
`Also proven by CI:` names the leg you will watch in phase 8, and is the only
unattended-safe disposition; `blocked` stops `blocked-verification`.
`unexercised` is the one result no `Without it:` covers: phase 5 admits it, an
unattended run proceeds on it, and the merge summary names the subject that did
not exist, for the human to weigh. Noisy runs go to a cheap-tier subagent returning the result plus
failing lines. `docs` class and the small lane skip this phase. Detail in
[reference/implement.md](reference/implement.md).

**4 · Sync docs, then self-review.** Docs first, so the review reads the docs
edits as part of the diff. **Docs-sync fires only when the public surface or
observable behavior changed**: bring the profile's `Targets:` in line, folding
the edits into this change. Skip the step for internal refactors, a bugfix
restoring documented behavior, test-only or tooling changes, and comments; when
you skip, say so in one line at the merge gate.

**The `writing-for-agents` pass has a trigger of its own**, and skipping
docs-sync never skips it: it fires whenever the diff touches a target on the
profile's `Agent-facing:` line, at the judgment tier, over every agent-facing
file in the diff. Human prose in the diff takes the mechanical pass.

**Self-review**, unconditional in every lane: invoke `code-review` against the
diff since `origin/HEAD`, its Standards axis reading the profile's
`## Coding standards` path, its Spec axis reading the issue. **Triage waits for
both axes.** An axis whose report never arrives is `red-after-retry: <axis>`
after the bounded retry, never a disposition written from memory of what it
would have said. **Auto-triage** every finding: harden rather than rip out
capability, verify nits against the pinned versions, reject known non-issues;
fix the valid ones; record a one-line disposition per finding. Two rails on
rejecting: a claim about **what exists in the repo** is checked against
`origin/HEAD`, never the worktree, which may
predate a merge; and a finding's **evidence and its claim are separate**, so a
reviewer citing the wrong commit for a real primitive is still right. A valid
finding outside the issue is an adjacent find: phase 2's three dispositions.
Then read the diff yourself against the four depth checks in the
coding-standards file the Standards axis reads, by their leading words: a
vocabulary the change extends, a rule-shaped prose change, new
pattern-matching code, a fix landed after review. Reviewer rounds find these
otherwise, serially, at the cost of most of a run's wall time.
This self-review plus green CI is the review gate; reviewers in phase 7 are a
second pair of eyes on top, never a substitute.

**5 · Local gate.** *Precondition:* every applicable verification is `pass`,
`deferred-to-ci` or `unexercised`, or the class is `docs`, **and** every
phase-4 finding carries a disposition; otherwise you skipped one, go back.
Running the gate while `code-review` is still out is not parallelism: a finding
fixed afterwards pays for a second gate run and a second pass of whatever the
profile's `Tripwires:` names. Run `base-fresh` first: it proves the branch has seen every commit on its base,
the one thing CI cannot (CI tests the merge ref, so a branch that predates a
merge still goes green while every "does this exist?" answer you took from the
worktree was pre-merge). Behind: rebase, re-run, then continue. Confirm every
`Carry:` file still matches the main checkout's copy; a difference is
`carried file modified`, because ship has no business editing untracked
secrets. Then run the gate at the profile's `Location:` from the worktree,
inline. Small lane:
`--small <node>` with the node written in the profile's `Small node:` syntax.
The gate owns dependency install and every check CI runs; its verdict is one
JSON object: `verdict` `pass|fail|unavailable`, per-gate statuses
`pass|fail|deferred-to-ci|unavailable`, `gates.secrets` present in every lane.
Unparseable output or a missing `secrets` key reads as `unavailable`. `fail`:
fix loop. Any `deferred-to-ci`: proceed, and the merge summary names each
deferred gate. `unavailable`: stop `local gate unavailable`; never open the PR.

**6 · Open PR.** `open-pr <issue> --title --body-file`, **non-draft** (drafts
may not trigger a reviewer). Title: a Conventional-Commit subject derived from
the issue, honouring `Subject constraints:`; it becomes the squash subject that
release tooling reads, and a title that later proves wrong is fixed with
`update-pr-title <pr> --title`. Body: the repo's template per `## PR`, filled
honestly (never a raw body that bypasses it); with no template, a plain body.
Every variant carries `Closes #<issue>` on its own line **above the first
`## ` heading** (the mechanic translates it for the host, and puts it there
itself when the body arrives without one), where no section rewrite reaches
it; a **Deviations from plan** section (the log verbatim, `None` only if the
plan held); a `## Verification` section holding one line per applicable
verification, read from the phase-3 results in the merge summary's
`Verification` row format, or `None applicable: <reason>` where none applied
(`class docs` and `small lane` skip the phase; a full-lane change where no
`Applies when:` line matches is the third reason, and a profile listing zero
verifications is that case); and a `## Review` section holding
one placeholder line per reviewer, filled at phase-7 exit. Where the
environment provides an attribution footer for pull request descriptions, it is
part of **the body file this call is handed**, never a later write: the body
**ends** with it, under a `## ` heading of its own that ship adds, no template
carrying one (`## Attribution`), placed after every section a later phase
rewrites. The footer is therefore in the body from open, and no second call
creates the section. The placement is what keeps it there: a rewrite replaces
everything from its own heading to the next one, so a footer left loose at the
end of the last section is inside that section and the phase-7
`update-pr-body --section Review` write drops it. Ship never names the footer's
lines; it only says where it sits.

**Every title or body write to an open PR ends with `read-pr <pr>`.** After a
body write, check the `## ` headings of the body it returns against the ones
the body is supposed to carry: a section the rewrite swallowed is missing from
them, and that is the only place a swallowed `## Attribution`
shows while the PR is still open. `update-pr-body` answers with a `sections`
list, which is that same check one write earlier. Read the headings the way the
slice does, fence-aware: the fence trap is a Shape fence over a markdown change
carrying `## ` lines of its own, which are example text and not sections.

**The Summary opens with a Shape.** Draw it from the diff here, not from
phase 2's design; a redraw is not a deviation. It is the first thing under
`## Summary`, above the prose, and where no template gives that heading the
plain body opens with it instead. It is a `diff` fence over a call tree, file
tree, control flow, pseudocode or component tree. Text forms only, never
mermaid and never HTML: Azure DevOps renders neither, and the `diff` fence is
the one form that shows the before and the after in a single view. One shape,
about 15 lines or fewer; a change that needs two is a PR spanning two
concerns. Every node is a real symbol, each tree's root node carries its file
path, and no line carries a line number: the first review-round push rots them
and nothing rewrites the Summary. A change that moves no logic and no layout
(a rename, a constant, a config value, docs alone) opens with the visible line
`Shape: none, mechanical (<kind>).` instead, so the self-review and the
reviewer can dispute the call. The small lane takes no exemption: a one-line
behaviour fix is where four lines of control-flow diff pay for themselves.
`show-me` supplies the form; these constraints are ship's, and its menu of
other uses is not.

Then `reflect <issue> <pr>` so a human reading the issue sees the PR.

**7 · Reviewers.** For each reviewer under `## Reviewers`, drive it to
convergence. Each reviewer's `Trigger:` (`auto-once`, `on-push`, `on-request`)
fixes its loop and its convergence test, its `Request:` fixes how a round is
asked for, and the profile's `Cap:` bounds its rounds; the brand fixes nothing.
Zero reviewers: skip the phase. **Order: every reviewer whose `Fallback-for:`
reads `None.` first, then the fallbacks**, because a fallback's whole input is
how the reviewer it names exited. A fallback is requested once, for any degraded
reason, and then driven as an ordinary on-request reviewer under its own `Cap:`;
where its primary converged it is not requested at all and exits
`not invoked: <primary> converged`; its own degraded exit triggers nothing
further, so the chain is one deep. Batch fixes into one push per round, then
answer each thread with `reply-thread` (`fixed in <sha>`, or the decline and
its reason), reading the round itself from its row in `poll-pr`'s output, where
its findings sit in the body rather than in threads: `rounds[]` under `--brief`,
`reviews.on_head[]` or `reviews.all[]` in the full shape, the head rule and the
since rule selecting the same rows either way. A body ending
`...[truncated]` is a round you have not read: re-poll with `--full <id>` for
that row before dispositioning it. `resolve-thread` runs per
thread once every thread carries a disposition. Exits: `converged`,
`converged, override needed` (a gating reviewer's declined finding, cited with
evidence), `degraded: <reason>` from
the fixed vocabulary `never-queued | blocked | silent | infra-error | cap-hit |
unreachable`, or, for a fallback whose primary converged,
`not invoked: <primary> converged`. Degraded proceeds to the merge gate on green CI and never hands
back on its own. `--brief` is how a round is read: it projects the same poll down
to the rounds and open threads, with the run's own replies dropped, so the loop
reads the findings rather than the whole fetch. At exit,
`update-pr-body <pr> --section "Deviations from plan" --body-file <path>` where
the rounds grew the log, then
`update-pr-body <pr> --section Review --body-file <path>` with one status line
per reviewer. **Each body file carries the section's content and not its
heading**: the mechanic writes the `## ` line itself. Then read the body back
per the rule at phase 6, while the PR is still open. Read
[reference/review-loop.md](reference/review-loop.md) for convergence per
trigger, the substantive-round test, `Instructions:` handling and degraded
detection.

**8 · CI.** CI runs from PR-open and overlaps phase 7; `ci-wait <pr>` covers
it, reading the profile's `Legs:`. `conflict`: a conflicted PR has no merge
ref, so checks sit pending forever; fetch, rebase onto the base, resolve,
re-run `base-fresh` and the local gate, push. `no-checks` is fine only where
`No-checks legal:` says so. A red leg named on a verification's
`Also proven by CI:` line is that verification failing: back to phase 2.
Red after reviewers converged: fix, push, proceed on green; a lint or flake fix
earns no new on-request round, and an on-push reviewer re-reads it on its own,
so wait for its quiet again. Honour `Push policy:`; a push spends CI minutes
and review quota, so push when the tree changed.

**9 · Merge gate.** **Hard stop.** Write the summary per
[reference/merge-gate.md](reference/merge-gate.md), uncompressed. Attended:
post it in the conversation and wait for an explicit "merge": the word is
exact, and a near miss is asked back rather than read as merge. On approval run
`merge <pr> <issue|none> --worktree <path>` then `cleanup <issue|none>`; any
`false` in their JSON is finished by hand before reporting done. `merge` reads
the PR first and refuses `pr-closed: <state>` for one that is neither open nor
already merged, merging nothing: a human says "merge" about a PR, and a closed
one is not it. Then it proves
the branch fresh against its base and refuses `stale-base` when the base
moved since phase 5: rebase, re-run the local gate, and come back to this gate. Unattended:
`comment-pr <pr> --body-file` with the summary, and return. The claim holds in
both lanes until the merge releases it.
