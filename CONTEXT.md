# Skills

Ahmed Gharib's shared agent skills. Each skill is written once here and reaches a repo as a derived copy; a repo expresses its own differences through per-repo docs, never by editing its copy.

## Language

**Ship**:
The skill that drives one tracker issue from nothing to a merge-ready PR in a single unattended run, stopping at the merge gate.
_Avoid_: pipeline, deliver, autopilot

**Ship profile**:
The per-repo document (`docs/agents/ship.md`) that carries every repo-specific fact Ship needs, one section per axis. A repo without a profile cannot run Ship.
_Avoid_: ship config, ship settings, project instructions (that is CLAUDE.md)

**Profile schema**:
The integer a ship profile declares and Ship declares it reads, moved only when Ship's expectations of the profile change; a mismatch in either direction refuses the run and `setup-skills` re-run migrates. Separate from Ship's version, which moves on any Ship change.
_Avoid_: profile version, format version, compat level

**Axis**:
One dimension along which repos legitimately differ in how they ship: worktree layout, local gate, reviewers, verification kind, versioning, PR template. The small-lane floor is not an axis: it is the same in every repo.
_Avoid_: option, knob, setting

**Local gate**:
The repo-owned script that runs every check the repo's CI would run, locally, before a PR opens. The only Ship mechanic whose body is the repo itself; its verdict has one shape in every repo. Always includes the repo's secrets check, in every lane.
_Avoid_: pre-push checks, lint step, test step

**Verdict**:
The local gate's one answer: pass, fail, or unavailable, built from a status per check. A check is deferred to CI when the gate knows CI proves it and unavailable when the gate could not ask its question; a deferred check proceeds and is named at the merge gate, an unavailable one stops an attended run and hands back an unattended one. Local green never means less than CI green.
_Avoid_: result, report, gate output

**Generic mechanic**:
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: run-file, tooling, preflight, read-issue, manage-issue (take, release, hand back, close), isolate, base-fresh, open-pr, reflect, read-pr, poll-pr, request-review, comment-pr, reply-thread, update-pr-body, update-pr-title, resolve-thread, CI wait, merge, cleanup, file-issue, list-prs, select. Every host interaction in a Ship run goes through one of them; the agent never drives a host's CLI directly, and a missing operation is a Ship defect, not a prose fallback. Not every one reaches a host: `run-file` writes the run's own record and nothing else. Their reads speak one vocabulary on every host, and a failed write to a PR (its body, its title, a comment, a thread reply) answers with the HTTP status of the last attempt, `null` where the host reported none, so a run can tell a payload the host refused from a host that was briefly down. Every one of them answers `--help` with its usage line on stdout and exit 0, reaching no host: that is where a run reads a mechanic's flags.
_Avoid_: helper, util, raw `gh` or `az` call

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing, and stopping with the exact command when a prerequisite is missing. One per skill repo: `setup-skills` drafts the ship profile today and each later per-repo document as one more section, never a second setup skill.
_Avoid_: init, scaffold, bootstrap

**Composed skill**:
A skill Ship loads through the Skill tool at the phase that needs it rather than reimplementing: `tdd`, `writing-for-agents`, `code-review`, `show-me`, `find-docs`. Ship's `metadata.composes` line names each with the repo it installs from, and preflight refuses a run before the claim when one is absent from the consumer repo's `.claude/skills/`. Adding one is therefore a breaking change for installed consumers. The inverse of a sibling skill: Ship composes these, a sibling composes Ship.
_Avoid_: dependency, sub-skill, helper skill

**Sibling skill**:
A skill that composes Ship rather than reimplementing it. Today there is one: `cloud-ship`, which invokes Ship unattended from a cloud routine and relays its outcome. It adds nothing Ship could do for itself: the cloud bootstrap, the PR cap, the selection, the claim, the branch, the isolation, the hand-back and the merge summary are all Ship's. Only Ship claims an issue; a sibling never pre-claims, never writes to the tracker, and never calls a Ship script by path.
_Avoid_: wrapper, plugin, variant

**Fire**:
One `cloud-ship` run: one selected issue driven to one merge-ready PR, ending at the merge gate with no human present. A fire either reaches merge-ready or hands the issue back; it never leaves it claimed and spinning. Distinct from an unattended run, which is the Ship run inside a fire.
_Avoid_: run, invocation, job, tick, cycle

**PR cap**:
The count of open pull requests at which a fire stops before selecting anything, because the human merge-review queue is the bottleneck rather than the backlog. The rail is core in every repo; only the number is a profile fact.
_Avoid_: throttle, rate limit, concurrency limit

**Derived copy**:
The copy of a shared skill committed under a repo's `.claude/skills/`, installed from this repo and never edited in place. A repo's copy is what runs, in the attended and unattended lanes alike, and refreshing it is the repo owner's act. A shared skill is never installed for the machine instead, because a personal skill silently shadows a repo's.
_Avoid_: vendored fork, sync, symlink, snapshot

**Claim**:
The assignee on a tracker issue, set by Ship before any work. An assigned issue is in flight or awaiting merge and no run takes it; the same rule in every repo, not an axis.
_Avoid_: lock, agent-working, in-progress label

**Hand-back**:
Releasing the claim after a blocked stop and marking the issue for a human, never returning it to the agent queue.
_Avoid_: requeue, unclaim, release (release alone is the claim coming off; hand-back adds the human marker)

**Attended run**:
A Ship run a human invoked, locally or in the cloud, and is present for. Admits `ready-for-agent` and `ready-for-human` issues; any needed human action stops and asks.
_Avoid_: local run, interactive mode

**Unattended run**:
A Ship run a cloud routine invoked through `cloud-ship`. Admits `ready-for-agent` issues only; a blocked stop hands back.
_Avoid_: cloud run, headless, autopilot

**Merge gate**:
The hard stop at the end of a Ship run where a human reads the summary and says merge or not. Ship never merges on its own.
_Avoid_: approval, sign-off, review

**Small lane**:
The collapsed form of a Ship run for a change the whole team would call trivial; revocable mid-run. It drops planning breadth, never a check: the floor is the same in every repo and is worktree isolation, the local gate's small floor (the repo's security check plus the one regression test proving the change), the self-review, the PR, CI plus every reviewer per its trigger, and the merge gate. The self-review never collapses, whether or not a reviewer exists, because it is the only check that reads the diff against the issue.
_Avoid_: fast path, quick mode, hotfix

**Reviewer**:
One automated review bot the ship profile names for a repo, with its login, its trigger, whether it is gating (a required check that can block the merge), and the reviewer it is a fallback for. A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate. Preflight parses the blocks and refuses four shapes before the claim: a fallback that is not on-request, one naming a reviewer nobody listed, an on-request reviewer with no cap, and a `Cap:` that is neither a number nor `None.`. One reviewer fact the blocks cannot settle themselves comes from the host instead: whether a Copilot reviewer's `Trigger:` matches the `copilot_code_review` ruleset that drives it.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push, on-request delivers one review per explicit request, and where the host still posts an opening round on its own, the loop polls for that free round and takes it as round 1 rather than spending a request on it. Convergence and mechanics follow the trigger, never the bot's brand. The profile's `Cap:` is a budget for the rounds **ship drives**, which is every round only where ship starts them: a reviewer the host re-runs on its own keeps posting past the number.
_Avoid_: mode, kind of bot

**Fallback reviewer**:
A reviewer driven only when the reviewer it names exits degraded, for any degraded reason; never a second opinion on a converged primary. Always on-request, because a reviewer that fires on every push cannot be withheld. When the primary converges, the fallback still reports, as not invoked, so the human sees it exists.
_Avoid_: backup bot, secondary reviewer, second opinion

**Request transport**:
How an on-request reviewer is asked for a round, named by its `Request:` line and never by its brand. Two of them: the host's own request-a-reviewer call, for a reviewer the host can add to the PR, and the comment transport, `comment <phrase>`, which posts the phrase as a PR comment for a reviewer that is a comment-triggered workflow. Either way the request is read back off the host and the time it reports is what the since rule takes, so it is the host's clock and never this machine's.
_Avoid_: request method, trigger phrase (that is the workflow's own setting)

**Landing rule**:
Which reviews `poll-pr` accepts as the round it is waiting for, reported as `landed_by`. The head rule, its default, takes only a review on the current head, because an on-push reviewer earns a fresh one per push. The since rule, `--since <iso>`, takes a review submitted at or after a time on any head, because an on-request or auto-once reviewer posts one round per request and a later push would otherwise strand it. The reviewer's trigger picks the rule. Neither rule takes a row that is not substantive: an empty body (a reviewer's reply to one thread) or a body that is only a quota or rate-limit notice, which refuses the round rather than delivering it.
_Avoid_: landing check, freshness rule

**Round clip**:
The 2000-character cap `poll-pr` puts on every review body, marked `...[truncated]` where it bites, so one poll cannot flood the run's window. `--full <id>` lifts it for the rows it names and nothing else. A reviewer that opens with a preamble pushes its findings past the cap, and a round that comes back clipped is one phase 7 has not read.
_Avoid_: truncation, body limit

**Converged**:
The phase-7 exit where CI is green and every reviewer is settled per its trigger: auto-once threads all dispositioned; on-push quiet on the current head with every thread dispositioned and resolved; on-request latest round nothing actionable and every thread dispositioned. Silence on the current head is never quiet.
_Avoid_: approved, clean, passed

**Degraded exit**:
A phase-7 exit that is not converged but still proceeds to the merge gate on green CI, named by one reason per reviewer: never-queued, blocked, silent, infra-error, cap-hit, unreachable. Never a hand-back on its own; the human reads it and decides.
_Avoid_: failure, timeout, skipped review

**Not invoked**:
The phase-7 exit belonging to a fallback reviewer whose primary converged: it was never requested, so it has no rounds and no findings. Neither converged nor degraded, and never a stop. It is reported anyway, in the PR body and the merge summary, so a reader sees a reviewer that exists and was deliberately not spent rather than one nobody configured.
_Avoid_: skipped, not needed, n/a

**Carried file**:
An untracked, gitignored file the ship profile names to be copied into the run's worktree when it is isolated, never copied back. A run that changes one stops.
_Avoid_: env file (one kind of carried file), secrets, worktree setup

**Verification**:
One check the ship profile names that proves a change against the real thing the repo integrates with (a live org, a browser, a database in a container), scoped to what the change touched and run where the issue was reported. A repo lists zero or more; each names what it proves, when it applies, how to run it, what it needs, what Ship does without that, and which CI leg also proves it. A run's result for one is `pass`, `fail`, `deferred-to-ci`, `unavailable`, or `unexercised`, the last meaning its prerequisites held but every applicable path lacked a subject to drive, the subject being one another actor creates.
_Avoid_: e2e, integration test, smoke test, live test (kinds of verification), phase-3 hook

**Hand-off**:
An attended stop where Ship prints the exact command and setup, waits for the human to run or confirm it, and resumes. The claim holds. In an unattended run a hand-off becomes a hand-back.
_Avoid_: pause, wait-state, hand-back (that releases the claim)

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). Ship reads it off the repo's remote and the ship profile names it as a cross-check; every generic mechanic has one adapter per host inside the skill, selected, never generated. A host's own words (label or tag, assignee or Assigned To, review thread or thread) never reach Ship's prose: the mechanics translate them.
_Avoid_: tracker (Boards is one part of a host), provider, platform

**Run file**:
The one file a Ship run keeps outside the repo, in the session's scratchpad, holding the ten-phase checklist with a clock stamp on every flip and the run's design and plan. The run's record, and the harness task list is its display: the source of truth for where the run is and the map back after a mid-run context summary, mirrored into the task list on every flip; each stamp is read from the clock by the command that writes it, and the merge summary's timing is computed from those stamps.
_Avoid_: task list, scratch file, plan file, todo

**Scratch directory**:
The directory a Ship run names in every subagent prompt as the one place that subagent writes scratch of its own: `<scratchpad>/scratch/<role>/`, `<role>` being that subagent's job in the run, and where the run writes that subagent's Report file. Edits to the repo are separate, and go under the worktree prefix. A sibling of the Run file's directory rather than a child, so a path a subagent invents below the one it was given still lands clear of the run's record. Passed at every dispatch the way the model tier is.
_Avoid_: scratch file (that names the Run file, and is avoided there too), temp directory, workspace

**Report file**:
The verbatim copy of a phase-4 report a Ship run writes into the producing role's Scratch directory, `<scratchpad>/scratch/<role>/<role>-report.md`, before dispositioning one of its findings: one per `code-review` axis, and one for the `writing-for-agents` pass where it fired. The report reaches the run in context alone, where a compaction takes it, so the file is what a disposition and the merge summary's `Self-review` rows are read from; a row whose file is no longer on disk reads `unverified`.
_Avoid_: axis output, review log, findings dump

**Shape**:
The compressed code-form view of a change that opens a PR's Summary: a call tree, file tree, control flow, pseudocode or component tree, written as a `diff` fence so the before and the after sit in one view. One per PR, about 15 lines or fewer, every node a real symbol and every root node carrying its file path. A change that moves no logic and no layout says so in a `Shape: none, mechanical (<kind>).` line rather than omitting it silently.
_Avoid_: diagram, visual, picture, mermaid, sketch

**Body preamble**:
Everything in a PR body above its first `## ` heading: the closing reference, and the Shape where no template gives a `## Summary`. The half of a body no section rewrite reaches, and `update-pr-body --preamble` is what rewrites it, carrying over a closing line the new content lacks so a rewrite that says nothing about closing keeps the link to the issue; content carrying its own closing line is left as written, whichever issues it names.
_Avoid_: header, intro, top of the body

**Adjacent find**:
A problem outside the claimed issue that Ship meets while working it, whether the agent spotted it or a reviewer raised it. Filed for triage and left alone, unless an acceptance criterion names it, its fix lands in a file the PR already changes, or a reviewer of the PR would flag it, in which case it is fixed inline and logged as a deviation. Filing goes through `file-issue`, which answers with an existing open issue rather than creating a second one for the same find. Distinct from a deviation, which is the claimed issue's own work departing from its plan.
_Avoid_: drive-by fix, scope creep, nit, out-of-scope finding

**Candidate**:
An open issue whose title shares three or more tokens with an adjacent find the run is about to file, found by `file-issue` before it creates anything. The mechanic reports candidates and files nothing; the run reads each one and either links it in the deviations log as the same find, or refiles past it with `--distinct-from`. A report, not a verdict: the judgement of same-or-different is the run's.
_Avoid_: duplicate, match, near-miss, collision

**Ship defect**:
A gap in Ship itself met during a run: a host operation no generic mechanic performs, or prose that promises what a mechanic does not do. Reported by name in the merge summary and carried upstream by the human; never hand-rolled around in the run, and never filed to another repo. In Ship's own source repo the run is already upstream, so a Ship defect is also an adjacent find and takes its dispositions, and is still named on the summary's row.
_Avoid_: tooling gap, missing helper, upstream bug
