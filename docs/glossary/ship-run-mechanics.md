### Ship run: host and test mechanics

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). Ship reads it off the repo's remote and the ship profile names it as a cross-check; every generic mechanic has one adapter per host inside the skill, selected from the ones it carries. A host's own words (label or tag, assignee or Assigned To, review thread or thread) stop at the mechanics, which translate them into Ship's own vocabulary.
_Avoid_: tracker (Boards is one part of a host), provider, platform

**Host fake**:
A third host adapter, beside the GitHub and Azure DevOps ones: `tests/host-fake.sh`, defining the same `host_*` functions and answering each call from a fixture, so a generic mechanic is tested as a script with no host behind it. Selected only by `SHIP_HOST_ADAPTER`, which `ship_load_host` reads and nothing else under `skills/` may; it lives under `tests/` and is never part of a derived copy. Its default answers carry exactly the key sets the `_lib.sh` host contract documents, which `tests/host-contract.test.sh` holds them to.
_Avoid_: mock, stub host, `host-stub` (the stub `gh` and `az` that fail any test reaching a real host)

**Fixture repo**:
A git repo a pre-merge live run drives a skill in, to prove one path through it on real state: synthetic (a standing repo reset by branching off a seed tag) or real (reverted afterwards).
_Avoid_: fixture (the host fake's canned answers), test repo, lab

**Live run**:
A real skill turn driven on a fixture repo to prove one path through the skill's prose, driven either by hand in a session the maintainer watches, or headless by a script.
_Avoid_: smoke test, smoke run, e2e, dry run

**Run file**:
The one file a Ship run keeps outside every checkout, in the user's state directory at `${XDG_STATE_HOME:-~/.local/state}/ship/<repo key>/ship-<issue>/run.md`, keyed by issue under a repo key hashed from the git common dir, so the main checkout and the run's worktree resolve the same path, two clones get different roots short of a CRC collision, a session isolated by `EnterWorktree` (whose guard, as Ship's context-discipline reference lists, refuses an Edit or Bash command naming a `.git` path, a write to the main checkout, and git it cannot prove targets the worktree) can still write it, and a wiped temp directory leaves it standing. It holds the ten-phase checklist with a clock stamp on every flip, the run's design and plan, each Verification's result, each Local gate verdict with the head it ran on, the run's `Grade:`, and the evidence lines `run-file close 4` and `close 7` refuse without (`Reverted-fix:` per test file the diff adds or changes, then a `Round:` per round and a `Stop:` per reviewer). The red `Reverted-fix:` line is produced, written by `run-file prove`; the rest are attested, written by the run with `run-file note`. The run's record, and the harness task list is its display: the source of truth for where the run is and the map back after a mid-run context summary, shown as one task per item, all ten created at `init` and each set to the `mirror` its flip returns; each stamp is read from the clock by the command that writes it, and the merge summary's timing is computed from those stamps. `cleanup <issue>` removes it after the merge; a free-text run (`cleanup none`) leaves its `ship-<slug>/` in place, and a run that stops before the merge gate leaves its record, which `init` then refuses to overwrite without `--rebuild`.
_Avoid_: task list, scratch file, plan file, todo

**Scratch directory**:
The directory a Ship run names in every subagent prompt as the one place that subagent writes scratch of its own: `${XDG_STATE_HOME:-~/.local/state}/ship/<repo key>/scratch-<issue>/<role>/`, keyed by issue (or slug), so two runs with different keys never read each other's leftovers, `<role>` being that subagent's job in the run, and where that subagent writes its Report file. Edits to the repo are separate, and go under the worktree prefix. A sibling of the Run file's directory rather than a child, so a path a subagent invents below the one it was given still lands clear of the run's record. Passed at every dispatch the way the model tier is, and removed by `cleanup <issue>` with the Run file, except that a free-text run (`cleanup none`) leaves its `scratch-<slug>/` in place and a run that stops before the merge gate leaves its directory.
_Avoid_: scratch file (that names the Run file, and is avoided there too), temp directory, workspace

**Report file**:
The file a phase-4 pass writes its report to (a subagent's, where one was dispatched), at the path named in the producing role's Scratch directory, `<scratch>/<role>/<role>-report.md`, `<scratch>` being the directory `run-file init` printed, a subagent handing back only the path and a summary of at most five lines: one per `code-review` axis, and one for the `writing-for-agents` pass where it fired. A later round of the Self-review loop writes `<scratch>/standards/standards-report-<n>.md`, so no round overwrites another's, and phase 7's local review writes `<scratch>/standards/standards-report-local.md`. No file there at hand-back is a report that failed to arrive. A report held in context alone is taken by a compaction, so the file is what a disposition and the merge summary's `Self-review` item are read from; a report whose file is no longer on disk reads `unverified`.
_Avoid_: axis output, review log, findings dump

**Self-review loop**:
Ship's phase-4 self-review, repeated while it still finds work, because refactoring belongs to review rather than to the red-to-green loop. Round 1 runs both `code-review` axes over the whole diff, with the `writing-for-agents` pass where it fired and the depth checks; each later round runs the Standards axis alone over the previous round's fix-only diff. The loop stops at the first round whose dispositions change no file, recorded `tree unchanged` even at the cap, or at the round the profile's `Self-review cap:` allows (3 where the line is absent) with that round's fixes unread, recorded `cap at <sha>`, `<sha>` the commit holding those fixes: the clean gate holds on it until a host reviewer's last stop reads them: `tree unchanged` at a head covering the final head, or any stop stamped at that commit or a descendant. Every lane runs it, so a clean small-lane run stops after round 1. Distinct from phase 7's reviewer rounds, which a host reviewer runs on the opened PR.
_Avoid_: re-review, second pass

**Adjacent find**:
A problem outside the claimed issue that Ship meets while working it, whether the agent spotted it or a reviewer raised it. Folded into the PR, and named in its body, when it fits inside what the PR is about and does not raise its release grade; filed for triage when it is not; just noted when it is trivial. Filing goes through `file-issue`, which answers with an existing open issue rather than creating a second one for the same find. Distinct from a deviation, which is the claimed issue's own work departing from its plan.
_Avoid_: drive-by fix, scope creep, nit, out-of-scope finding

**Candidate**:
An open issue whose title shares three or more tokens with an adjacent find the run is about to file, found by `file-issue` before it creates anything. The mechanic reports candidates and files nothing; the run reads each one and either links it in the deviations log as the same find, or refiles past it with `--distinct-from`. A report, not a verdict: the judgement of same-or-different is the run's.
_Avoid_: duplicate, match, near-miss, collision

**Ship defect**:
A gap in Ship itself that broke or misled a run: a gating call no generic mechanic performs, or a mechanic or prose whose wrong answer the run acted on. It never holds a clean gate on its own. Reported by name in the merge summary with a drafted issue for the source repo, which Ship files there only on the human's word at the merge gate, printing the command where the run cannot reach the source repo's host; never a hand-rolled call. A gap in the ship profile rather than in Ship is a profile defect: an adjacent find of the consumer repo, filed there. In Ship's own source repo the run is already upstream, so a Ship defect is also an adjacent find and takes its dispositions, and is still named under the merge summary's `Ship defects`.
_Avoid_: tooling gap, missing helper, upstream bug, profile defect (that is the consumer repo's)

**Ship note**:
Friction in Ship that a run worked around by judgment, such as a rule that did not fit the case or prose that left the run guessing. One line on the merge summary and in the PR body, with no drafted issue.
_Avoid_: minor defect, nit
