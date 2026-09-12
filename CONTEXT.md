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
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: tooling, preflight, read-issue, manage-issue (take, release, hand back), isolate, base-fresh, open-pr, reflect, poll-pr, request-review, comment-pr, reply-thread, update-pr-body, update-pr-title, resolve-thread, CI wait, merge, file-issue, list-prs, select. Every host interaction in a Ship run goes through one of them; the agent never drives a host's CLI directly, and a missing operation is a Ship defect, not a prose fallback. Their reads speak one vocabulary on every host.
_Avoid_: helper, util, raw `gh` or `az` call

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing, and stopping with the exact command when a prerequisite is missing. One per skill repo: `setup-skills` drafts the ship profile today and each later per-repo document as one more section, never a second setup skill.
_Avoid_: init, scaffold, bootstrap

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
One automated review bot the ship profile names for a repo, with its login, its trigger, and whether it is gating (a required check that can block the merge). A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push and its rounds are free, on-request delivers one review per explicit request and is capped. Convergence and mechanics follow the trigger, never the bot's brand.
_Avoid_: mode, kind of bot

**Landing rule**:
Which reviews `poll-pr` accepts as the round it is waiting for, reported as `landed_by`. The head rule, its default, takes only a review on the current head, because an on-push reviewer earns a fresh one per push. The since rule, `--since <iso>`, takes a review submitted at or after a time on any head, because an on-request or auto-once reviewer posts one round per request and a later push would otherwise strand it. The reviewer's trigger picks the rule.
_Avoid_: landing check, freshness rule

**Converged**:
The phase-7 exit where CI is green and every reviewer is settled per its trigger: auto-once threads all dispositioned; on-push quiet on the current head with every thread dispositioned and resolved; on-request latest round nothing actionable and every thread dispositioned. Silence on the current head is never quiet.
_Avoid_: approved, clean, passed

**Degraded exit**:
A phase-7 exit that is not converged but still proceeds to the merge gate on green CI, named by one reason per reviewer: never-queued, blocked, silent, infra-error, cap-hit, unreachable. Never a hand-back on its own; the human reads it and decides.
_Avoid_: failure, timeout, skipped review

**Carried file**:
An untracked, gitignored file the ship profile names to be copied into the run's worktree when it is isolated, never copied back. A run that changes one stops.
_Avoid_: env file (one kind of carried file), secrets, worktree setup

**Verification**:
One check the ship profile names that proves a change against the real thing the repo integrates with (a live org, a browser, a database in a container), scoped to what the change touched and run where the issue was reported. A repo lists zero or more; each names what it proves, when it applies, how to run it, what it needs, what Ship does without that, and which CI leg also proves it.
_Avoid_: e2e, integration test, smoke test, live test (kinds of verification), phase-3 hook

**Hand-off**:
An attended stop where Ship prints the exact command and setup, waits for the human to run or confirm it, and resumes. The claim holds. In an unattended run a hand-off becomes a hand-back.
_Avoid_: pause, wait-state, hand-back (that releases the claim)

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). Ship reads it off the repo's remote and the ship profile names it as a cross-check; every generic mechanic has one adapter per host inside the skill, selected, never generated. A host's own words (label or tag, assignee or Assigned To, review thread or thread) never reach Ship's prose: the mechanics translate them.
_Avoid_: tracker (Boards is one part of a host), provider, platform

**Run file**:
The one scratch file a Ship run keeps outside the repo, in the session's scratchpad, holding the ten-phase checklist with a clock stamp on every flip and the run's design and plan. The source of truth for where the run is and the map back after a mid-run context summary; the merge summary's timing is read off its stamps. The harness task tools, when a run finds them, are a mirror of it, never the record.
_Avoid_: task list, scratch file, plan file, todo

**Adjacent find**:
A problem outside the claimed issue that Ship meets while working it, whether the agent spotted it or a reviewer raised it. Filed for triage and left alone, unless an acceptance criterion names it, its fix lands in a file the PR already changes, or a reviewer of the PR would flag it, in which case it is fixed inline and logged as a deviation. Filing goes through `file-issue`, which answers with an existing open issue rather than creating a second one for the same find. Distinct from a deviation, which is the claimed issue's own work departing from its plan.
_Avoid_: drive-by fix, scope creep, nit, out-of-scope finding

**Candidate**:
An open issue whose title shares three or more tokens with an adjacent find the run is about to file, found by `file-issue` before it creates anything. The mechanic reports candidates and files nothing; the run reads each one and either links it in the deviations log as the same find, or refiles past it with `--distinct-from`. A report, not a verdict: the judgement of same-or-different is the run's.
_Avoid_: duplicate, match, near-miss, collision

**Ship defect**:
A gap in Ship itself met during a run: a host operation no generic mechanic performs, or prose that promises what a mechanic does not do. Reported by name in the merge summary and carried upstream by the human; never hand-rolled around in the run, and never filed to another repo. In Ship's own source repo the run is already upstream, so a Ship defect is also an adjacent find and takes its dispositions, and is still named on the summary's row.
_Avoid_: tooling gap, missing helper, upstream bug
