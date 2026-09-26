# Skills

Ahmed Gharib's shared agent skills. Each skill is written once here and reaches a repo as a derived copy; a repo expresses its own differences through per-repo docs, leaving its copy as installed.

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
The local gate's one answer: pass, fail, or unavailable, built from a status per check. A check is deferred to CI when the gate knows CI proves it and unavailable when the gate could not ask its question; a deferred check proceeds and is named at the merge gate, an unavailable one stops an attended run and hands back an unattended one. Local green means at least as much as CI green.
_Avoid_: result, report, gate output

**Generic mechanic**:
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: run-file, prepare, tooling, preflight, read-issue, manage-issue (take, release, hand back, close), isolate, base-fresh, open-pr, reflect, read-pr, poll-pr, request-review, comment-issue, comment-pr, reply-thread, update-pr-body, update-pr-title, update-issue-body, resolve-thread, CI wait, merge, cleanup, file-issue, list-prs, select. Every host write and every gating read in a Ship run goes through one of them, and a missing one is a Ship defect, not a prose fallback; an informational read no mechanic covers is the one host call a run may make directly. Not every one reaches a host: `run-file` writes the run's own record and nothing else. Their reads speak one vocabulary on every host, and a failed write to a PR (its body, its title, a comment, a thread reply) or to an issue (a comment, its body) answers with the HTTP status of the last attempt, `null` where the host reported none, so a run can tell a payload the host refused from a host that was briefly down. Every one of them answers `--help` with its usage line on stdout and exit 0, reaching no host: that is where a run reads a mechanic's flags.
_Avoid_: helper, util, raw `gh` or `az` call (for a write or a gating read)

**Gating read**:
A host read a phase's `Done when:` or a stop row depends on, such as preflight's admission, poll-pr's round, CI wait's legs or base-fresh's answer. It stays a generic mechanic, so the same host state always gives the same verdict.
_Avoid_: check, probe

**Informational read**:
A host read no phase or stop branches on, made for context alone. Where no mechanic covers it, a run may make it directly through the host's REST form, which the cloud sandbox admits, and lists it in the Run file's `## Direct reads`; one made directly in two runs is a candidate mechanic. Verification scaffolding (a scratch issue or scratch review thread set up by hand) is neither kind of read and sits outside the rule.
_Avoid_: side read, ad-hoc call

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing, and stopping with the exact command when a prerequisite is missing. One per skill repo: `setup-skills` drafts the ship profile today and each later per-repo document as one more section of that same skill.
_Avoid_: init, scaffold, bootstrap

**Dimension label**:
A label on one of the three dimensions a repo's tracker carries beside the five triage roles: kind, size and priority, at most one label per dimension on an issue, stamped at triage time. `setup-skills` seeds the vocabulary, creating the labels on the host and writing the `## Dimension labels` section into a `docs/agents/triage-labels.md` that has none; the repo owns the section from then on. Implementation order is derived from priority, size and blocking edges and is never one of them: a rank label rots the moment a higher issue ships.
_Avoid_: tag, rank label, severity, t-shirt size

**Composed skill**:
A skill Ship takes a phase's logic from at the phase that needs it, rather than reimplementing it: `tdd`, `writing-for-agents`, `code-review`, `find-docs` and `show-me`. Ship loads each through the Skill tool, except `show-me`, which it reads as a file because its upstream disables model invocation. Ship's `metadata.composes` line names each with the repo and pinned ref it installs from, and preflight refuses a run before the claim when one is absent from the consumer repo's `.claude/skills/`, or its `skills-lock.json` records it at another ref. Adding one, or moving its pin, is therefore a breaking change for installed consumers. `setup-skills` composes `triage` the same way, so it counts as one wherever composed skills are pinned and checked. The inverse of a sibling skill: Ship composes these, a sibling composes Ship.
_Avoid_: dependency, sub-skill, helper skill

**Sibling skill**:
A skill that composes Ship rather than reimplementing it. Today there is one: `cloud-ship`, which invokes Ship unattended from a cloud routine and relays its outcome. It adds nothing Ship could do for itself: the cloud bootstrap, the PR cap, the selection, the claim, the branch, the isolation, the hand-back and the merge summary are all Ship's. Only Ship claims an issue: a sibling leaves the claim and every tracker write to Ship, and reaches it through the Skill tool rather than by a script path.
_Avoid_: wrapper, plugin, variant

**Fire**:
One `cloud-ship` run: one selected issue driven to one merge-ready PR, ending at the merge gate with no human present. A fire ends at one of two resting states, merge-ready or handed back, so the issue always ends up somewhere a human can act on. Distinct from an unattended run, which is the Ship run inside a fire.
_Avoid_: run, invocation, job, tick, cycle

**PR cap**:
The count of open pull requests at which a fire stops before selecting anything, because the human merge-review queue is the bottleneck rather than the backlog. The rail is core in every repo; only the number is a profile fact.
_Avoid_: throttle, rate limit, concurrency limit

**Derived copy**:
The copy of a shared skill committed under a repo's `.claude/skills/`, installed from this repo and left as installed, every change going to the source. A repo's copy is what runs, in the attended and unattended lanes alike, and refreshing it is the repo owner's act. A shared skill is installed at repo scope, because a personal skill silently shadows a repo's.
_Avoid_: vendored fork, sync, symlink, snapshot

**Source repo**:
This repo, `Gharib89/skills`: where Ship, `cloud-ship` and `setup-skills` are written, and where the versions of their composed skills are tested. Every derived copy of those three is installed from it.
_Avoid_: upstream (that is a composed skill's own repo), skills repo, origin

**Consumer repo**:
Any repo holding derived copies installed from the source repo, the source repo included, since it installs its own. A consumer repo owns its per-repo docs and never edits its copies.
_Avoid_: derived repo, client repo, target repo

**Pinned ref**:
The upstream commit of a composed skill that the source repo tested Ship against: the one version of it any consumer repo installs. It moves only when the source repo refreshes that skill on purpose.
_Avoid_: tested version, locked version, hash (the lock's `computedHash` is the folder's content hash, not the ref)

**Upstream drift**:
A composed skill whose upstream has moved past its pinned ref. Reported to the source repo, never acted on in a consumer repo: a consumer that installed the new upstream would run Ship against a version nobody tested.
_Avoid_: outdated skill, stale dependency

**Refresh**:
Re-installing a consumer repo's derived copies, and its composed skills at their pinned refs, then running Ship's preflight so a profile the new Ship no longer reads is reported at once. The repo owner's act, which `update-skills` performs.
_Avoid_: sync, upgrade, update (the CLI's `update` ignores pinned refs)

**Claim**:
The assignee on a tracker issue, set by Ship before any work. An assigned issue is in flight or awaiting merge and no run takes it; the same rule in every repo, not an axis.
_Avoid_: lock, agent-working, in-progress label

**Hand-back**:
Releasing the claim after a blocked stop and marking the issue for a human: to the human queue, never the agent queue, which loops forever.
_Avoid_: requeue, unclaim, release (release alone is the claim coming off; hand-back adds the human marker)

**Attended run**:
A Ship run a human invoked, locally or in the cloud, and is present for. Admits `ready-for-agent` and `ready-for-human` issues; any needed human action stops and asks.
_Avoid_: local run, interactive mode

**Unattended run**:
A Ship run a cloud routine invoked through `cloud-ship`. Admits `ready-for-agent` issues only; a blocked stop hands back.
_Avoid_: cloud run, headless, autopilot

**Cloud sandbox**:
The container any cloud session runs in, attended or unattended, reaching hosts only through the session proxy. Its image, network policy and refusals (GitHub GraphQL among them) are facts Ship adapts to, not settings a repo owns. The lane decides which issues a run admits; the sandbox decides what the run must prepare before it can work.
_Avoid_: cloud env, default env, container

**Merge gate**:
The hard stop at the end of a Ship run where a human reads the summary and says merge or not. Ship merges on that word alone, and never on its own.
_Avoid_: approval, sign-off, review

**Small lane**:
The collapsed form of a Ship run for a change that is narrow, locally provable, invisible to the public surface and inside the size cap, which is counted on the diff, never estimated; revocable mid-run. It drops planning breadth and keeps every check: the floor is the same in every repo and is worktree isolation, the local gate's small floor (the repo's security check plus the test proving the change, or the full gate where more than one test proves it), the self-review, the PR, CI plus every reviewer per its trigger, and the merge gate. The self-review runs at full width in every lane, whether or not a reviewer exists, because it is the only check that reads the diff against the issue.
_Avoid_: fast path, quick mode, hotfix

**Reviewer**:
One automated review bot the ship profile names for a repo, with its login, its trigger, whether it is gating (a required check that can block the merge), and the reviewer it is a fallback for. A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate. Preflight parses the blocks and refuses eight shapes before the claim: a fallback that is not on-request, one naming a reviewer nobody listed, an on-request reviewer with no cap, a `Cap:` that is neither a number nor `None.`, a `Request: comment` with no phrase for the transport to post, a comment transport with no `Workflow:` naming the file its round comes from, a `Workflow:` on a block no comment transport drives, and a `Workflow:` naming a file the checkout does not carry. One reviewer fact the blocks cannot settle themselves comes from the host instead: whether a Copilot reviewer's `Trigger:` matches the `copilot_code_review` ruleset that drives it.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push, on-request delivers one review per explicit request, and where the host still posts an opening round on its own, round 1 is polled from PR creation, so that round is round 1, and one already landed takes no request. The loop and mechanics follow the trigger alone; the bot's brand decides nothing. The profile's `Cap:` is a budget for the rounds **ship drives**, which is every round only where ship starts them: a reviewer the host re-runs on its own keeps posting past the number.
_Avoid_: mode, kind of bot

**Fallback reviewer**:
A reviewer driven only when the reviewer it names exits not reviewed, for any reason; a primary that reviewed leaves it unspent. Always on-request, because a reviewer that fires on every push cannot be withheld. When the primary reviewed, the fallback still reports, as not invoked, so the human sees it exists.
_Avoid_: backup bot, secondary reviewer, second opinion

**Request transport**:
How an on-request reviewer is asked for a round, named by its `Request:` line alone, whatever its brand. Two of them: the host's own request-a-reviewer call, for a reviewer the host can add to the PR, and the comment transport, `comment <phrase>`, which posts the phrase as a PR comment for a reviewer that is a comment-triggered workflow. Either way the request is read back off the host, and the since rule takes its timestamp from that read-back, so the clock is the host's.
_Avoid_: request method, trigger phrase (that is the workflow's own setting)

**Landing rule**:
Which reviews `poll-pr` accepts as the round it is waiting for, reported as `landed_by`. The reviewer's `Trigger:` picks the rule, which `poll-pr --reviewer` derives from its block. The head rule takes only a review on the current head, because an on-push reviewer earns a fresh one per push. The since rule takes a review submitted at or after the `--since <iso>` instant on any head, because an on-request or auto-once reviewer posts one round per request and a later push would otherwise strand it; that instant is the one value the poll cannot derive. Neither rule takes a row that is not substantive; a quota or rate-limit notice refuses the round rather than delivering it.
_Avoid_: landing check, freshness rule

**Substantive**:
A review row that counts as a round: one with text that is not wholly a quota or rate-limit notice, or a bodiless verdict (approved or changes). Ship grades it above the host, never in an adapter.
_Avoid_: real review, meaningful round

**Round clip**:
The 2000-character cap `poll-pr` puts on every review body, marked `...[truncated]` where it bites, so one poll cannot flood the run's window. `--brief --full <id>` lifts it for the rows it names and nothing else, and `--full` without `--brief` is refused. It covers review bodies alone: a `--brief` thread row's `lead` carries the same marker at 200 characters, which no flag lifts, and the full shape's `threads[]` is where that comment is read whole. A reviewer that opens with a preamble pushes its findings past the cap, and a round that comes back clipped is one phase 7 has not read.
_Avoid_: truncation, body limit

**Reviewed**:
A reviewer's phase-7 exit where at least one of its rounds landed and every finding in it carries a disposition, whether or not a later round landed. A gating reviewer's declined finding is still reviewed, cited at the merge gate as the override the human decides on.
_Avoid_: converged, approved, clean, passed

**Not reviewed**:
A reviewer's phase-7 exit where no round of it landed, or one did and its threads could not be read (unreachable), named by the cause a mechanic observed: poll-pr's `not_reviewed` (unreachable, blocked, never-queued, infra-error, silent) or request-review's exit 1 (never-queued). It still proceeds to the merge gate on green CI, the human's call there rather than a hand-back.
_Avoid_: degraded, failure, timeout, skipped review

**Not invoked**:
The phase-7 exit belonging to a fallback reviewer whose primary reviewed: it went unrequested, so it has no rounds and no findings. Neither reviewed nor not reviewed, and the run carries on past it. It is reported anyway, in the PR body and the merge summary, so a reader sees a reviewer that exists and was deliberately not spent rather than one nobody configured.
_Avoid_: skipped, not needed, n/a

**Carried file**:
An untracked, gitignored file the ship profile names to be copied into the run's worktree when it is isolated, and left there. A run that changes one stops.
_Avoid_: env file (one kind of carried file), secrets, worktree setup

**Verification**:
One check the ship profile names that proves a change against the real thing the repo integrates with (a live org, a browser, a database in a container), scoped to what the change touched and run where the issue was reported. A repo lists zero or more; each names what it proves, when it applies, how to run it, what it needs, what Ship does without that, and which CI leg also proves it. A run's result for one is `pass`, `fail`, `deferred-to-ci`, `unavailable`, or `unexercised`, the last meaning its prerequisites held but every applicable path lacked a subject to drive, the subject being one another actor creates.
_Avoid_: e2e, integration test, smoke test, live test (kinds of verification), phase-3 hook

**Hand-off**:
An attended stop where Ship prints the exact command and setup, waits for the human to run or confirm it, and resumes. The claim holds. In an unattended run a hand-off becomes a hand-back.
_Avoid_: pause, wait-state, hand-back (that releases the claim)

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). Ship reads it off the repo's remote and the ship profile names it as a cross-check; every generic mechanic has one adapter per host inside the skill, selected from the ones it carries. A host's own words (label or tag, assignee or Assigned To, review thread or thread) stop at the mechanics, which translate them into Ship's own vocabulary.
_Avoid_: tracker (Boards is one part of a host), provider, platform

**Host fake**:
A third host adapter, beside the GitHub and Azure DevOps ones: `tests/host-fake.sh`, defining the same `host_*` functions and answering each call from a fixture, so a generic mechanic is tested as a script with no host behind it. Selected only by `SHIP_HOST_ADAPTER`, which `ship_load_host` reads and nothing else under `skills/` may; it lives under `tests/` and is never part of a derived copy. Its default answers carry exactly the key sets the `_lib.sh` host contract documents, which `tests/host-contract.test.sh` holds them to.
_Avoid_: mock, stub host, `host-stub` (the stub `gh` and `az` that fail any test reaching a real host)

**Run file**:
The one file a Ship run keeps outside the repo, in the session's scratchpad, holding the ten-phase checklist with a clock stamp on every flip and the run's design and plan. The run's record, and the harness task list is its display: the source of truth for where the run is and the map back after a mid-run context summary, mirrored into the task list on every flip; each stamp is read from the clock by the command that writes it, and the merge summary's timing is computed from those stamps.
_Avoid_: task list, scratch file, plan file, todo

**Scratch directory**:
The directory a Ship run names in every subagent prompt as the one place that subagent writes scratch of its own: `<scratchpad>/scratch/<role>/`, `<role>` being that subagent's job in the run, and where that subagent writes its Report file. Edits to the repo are separate, and go under the worktree prefix. A sibling of the Run file's directory rather than a child, so a path a subagent invents below the one it was given still lands clear of the run's record. Passed at every dispatch the way the model tier is.
_Avoid_: scratch file (that names the Run file, and is avoided there too), temp directory, workspace

**Report file**:
The file a phase-4 pass writes its report to (a subagent's, where one was dispatched), at the path named in the producing role's Scratch directory, `<scratchpad>/scratch/<role>/<role>-report.md`, a subagent handing back only the path and a summary of at most five lines: one per `code-review` axis, and one for the `writing-for-agents` pass where it fired. No file there at hand-back is a report that failed to arrive. A report held in context alone is taken by a compaction, so the file is what a disposition and the merge summary's `Self-review` rows are read from; a row whose file is no longer on disk reads `unverified`.
_Avoid_: axis output, review log, findings dump

**Shape**:
The compressed code-form view of a change, sitting under a PR body's `## Change outline`: a call tree, control flow, pseudocode or component tree, written as a `diff` fence so the before and the after sit in one view. **One behavioural fence per PR**, about 15 lines or fewer, every node a real symbol and every root node carrying its file path; a carrier file tree may follow it, and only where the same edit lands in more than two files. The `Shape: none, mechanical (<kind>).` line replaces the fence only where the reviewer's question is "did the text change correctly", never where it is "what does X now do", and omitting both silently is a finding.
_Avoid_: diagram, visual, picture, mermaid, sketch

**Body preamble**:
Everything in a PR body above its first `## ` heading, which is the closing reference and nothing else. The half of a body no section rewrite reaches, and `update-pr-body --preamble` is what rewrites it, carrying over a closing line the new content lacks so a rewrite that says nothing about closing keeps the link to the issue; content carrying its own closing line is left as written, whichever issues it names.
_Avoid_: header, intro, top of the body

**Adjacent find**:
A problem outside the claimed issue that Ship meets while working it, whether the agent spotted it or a reviewer raised it. Filed for triage and left alone, unless an acceptance criterion names it, its fix lands in a file the PR already changes, or a reviewer of the PR would flag it, in which case it is fixed inline and logged as a deviation. Filing goes through `file-issue`, which answers with an existing open issue rather than creating a second one for the same find. Distinct from a deviation, which is the claimed issue's own work departing from its plan.
_Avoid_: drive-by fix, scope creep, nit, out-of-scope finding

**Candidate**:
An open issue whose title shares three or more tokens with an adjacent find the run is about to file, found by `file-issue` before it creates anything. The mechanic reports candidates and files nothing; the run reads each one and either links it in the deviations log as the same find, or refiles past it with `--distinct-from`. A report, not a verdict: the judgement of same-or-different is the run's.
_Avoid_: duplicate, match, near-miss, collision

**Ship defect**:
A gap in Ship itself met during a run: a host write or gating read no generic mechanic performs, or prose that promises what a mechanic does not do. Reported by name in the merge summary with a drafted issue for the source repo, which Ship files there only on the human's word at the merge gate, printing the command where the run cannot reach the source repo's host; never a hand-rolled call. A gap in the ship profile rather than in Ship is a profile defect: an adjacent find of the consumer repo, filed there. In Ship's own source repo the run is already upstream, so a Ship defect is also an adjacent find and takes its dispositions, and is still named on the summary's row.
_Avoid_: tooling gap, missing helper, upstream bug, profile defect (that is the consumer repo's)

**Release run**:
The push-to-main workflow that owns every skill's `metadata.version`: it writes the number and cuts that skill's `CHANGELOG.md`, one run per skill, from the Conventional-Commit type of the squash subject. The `version-lines` gate refuses a PR that writes the line instead. `semantic-release` is the tool that runs it, and the value the ship profile's `Tooling:` line takes.
_Avoid_: release job, auto-bump, version bump PR
