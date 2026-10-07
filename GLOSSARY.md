# Skills

Ahmed Gharib's shared agent skills. Each skill is written once here and reaches a repo as a derived copy; a repo expresses its own differences through per-repo docs, leaving its copy as installed.

## Language

### Ship run

**Ship**:
The skill that drives one tracker issue from nothing to a merge-ready PR in a single unattended run, stopping at the merge gate.
_Avoid_: pipeline, deliver, autopilot

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
A host read no phase or stop branches on, made for context alone. Where no mechanic covers it, a run may make it directly through the host's REST form, which the cloud sandbox admits, and lists it in the Run file's `## Direct reads`; one made directly in two runs is a candidate mechanic. Verification scaffolding (a scratch issue, scratch review thread or throwaway probe PR set up by hand) is neither kind of read and sits outside the rule.
_Avoid_: side read, ad-hoc call

**Cloud bootstrap**:
Ship's sandbox preparation for one repo, run before any claim in every cloud run and every unattended run. With a harness it is the cloud setup run again, so a broken sandbox stops before the claim, then only the steps that need something only Ship has, such as the local gate's secrets scanner and a live end-to-end check's credentials; anything the check entry point needs belongs to the cloud setup instead. Without one, it is whatever the repo's own script installs. Setup-skills drafts it.
_Avoid_: cloud setup, setup script, cloud-ship bootstrap

**Sibling skill**:
A skill that composes Ship rather than reimplementing it. Today there is one: `cloud-ship`, which invokes Ship unattended from a cloud routine and relays its outcome. It adds nothing Ship could do for itself: the cloud bootstrap, the PR cap, the selection, the claim, the branch, the isolation, the hand-back and the merge summary are all Ship's. Only Ship claims an issue: a sibling leaves the claim and every tracker write to Ship, and reaches it through the Skill tool rather than by a script path.
_Avoid_: wrapper, plugin, variant

**Fire**:
One `cloud-ship` run: one selected issue driven to one merge-ready PR, ending at the merge gate with no human present. A fire ends at one of two resting states, merge-ready or handed back, so the issue always ends up somewhere a human can act on. Distinct from an unattended run, which is the Ship run inside a fire.
_Avoid_: run, invocation, job, tick, cycle

**PR cap**:
The count of open pull requests at which a fire stops before selecting anything, because the human merge-review queue is the bottleneck rather than the backlog. The rail is core in every repo; only the number is a profile fact.
_Avoid_: throttle, rate limit, concurrency limit

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
The end of a Ship run where its full summary records the merge decision. By default an attended run waits for the human's exact "merge"; a profile with `Merge: on-clean-gate` authorizes a merge when `run-file gate clean` confirms every recorded condition and no unmet criterion is listed, since each needs the human's waiver. An unattended run posts to the PR and returns.
_Avoid_: approval, sign-off, review

**Clean gate**:
The recorded conditions permitting an attended run to merge without a reply when its profile opts in: every CI leg green, every local gate passed or deferred to CI on the PR head (a deferral holds the gate while a CI check outside the legs is not green), every reviewer's loop stopped on an unchanged tree (a fallback answers for its primary), every applicable Verification passed or deferred to a green CI leg, and no override, Ship defect or Tracker draft. Deviations alone do not hold it.
_Avoid_: auto-merge (a host flag that can merge before Ship finishes its reviews)

**Small lane**:
The collapsed form of a Ship run for a change that is narrow, locally provable, invisible to the public surface and inside the size cap, which is counted on the diff, never estimated; revocable mid-run. It drops planning breadth and keeps every check: the floor is the same in every repo and is worktree isolation, the local gate's small floor (the repo's security check plus the test proving the change, or the full gate where more than one test proves it), the self-review, the PR, CI plus every reviewer per its trigger, and the merge gate. The self-review runs at full width in every lane, whether or not a reviewer exists, because it is the only check that reads the diff against the issue.
_Avoid_: fast path, quick mode, hotfix

**Hand-off**:
An attended stop where Ship prints the exact command and setup, waits for the human to run or confirm it, and resumes. The claim holds. In an unattended run a hand-off becomes a hand-back.
_Avoid_: pause, wait-state, hand-back (that releases the claim)

**Unmet criterion**:
An acceptance criterion asking for a host action no mechanic performs, which a run leaves verbatim in the issue and lists on the merge summary with the action a human must take: unattended always, attended when the human, asked before building, says to build the rest. Merging needs the human's explicit waiver of each, beside the merge word. Not a Ship defect: the action is the issue's deliverable, not a step the run itself must perform.
_Avoid_: rewritten criterion, descoped criterion

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). Ship reads it off the repo's remote and the ship profile names it as a cross-check; every generic mechanic has one adapter per host inside the skill, selected from the ones it carries. A host's own words (label or tag, assignee or Assigned To, review thread or thread) stop at the mechanics, which translate them into Ship's own vocabulary.
_Avoid_: tracker (Boards is one part of a host), provider, platform

**Host fake**:
A third host adapter, beside the GitHub and Azure DevOps ones: `tests/host-fake.sh`, defining the same `host_*` functions and answering each call from a fixture, so a generic mechanic is tested as a script with no host behind it. Selected only by `SHIP_HOST_ADAPTER`, which `ship_load_host` reads and nothing else under `skills/` may; it lives under `tests/` and is never part of a derived copy. Its default answers carry exactly the key sets the `_lib.sh` host contract documents, which `tests/host-contract.test.sh` holds them to.
_Avoid_: mock, stub host, `host-stub` (the stub `gh` and `az` that fail any test reaching a real host)

**Fixture repo**:
A git repo a pre-merge live run drives a skill in, to prove one path through it on real state: synthetic (a standing repo reset by branching off a seed tag) or real (reverted afterwards).
_Avoid_: fixture (the host fake's canned answers), test repo, lab

**Run file**:
The one file a Ship run keeps outside every working tree, in the repo's git common directory at `<git common dir>/ship/ship-<issue>/run.md`, keyed by issue, so the main checkout and the run's worktree resolve the same path and a wiped temp directory leaves it standing. It holds the ten-phase checklist with a clock stamp on every flip, the run's design and plan, each Verification's result, each Local gate verdict with the head it ran on, the run's `Grade:`, and the evidence lines `run-file close 4` and `close 7` refuse without (`Reverted-fix:`, `Dropped:`, `Near-miss:`, `Declined:` with its `Probe:`, then a `Round:` per round and a `Stop:` per reviewer). The run's record, and the harness task list is its display: the source of truth for where the run is and the map back after a mid-run context summary, shown as one task per open phase, created when the phase opens and completed when it closes; each stamp is read from the clock by the command that writes it, and the merge summary's timing is computed from those stamps. `cleanup <issue>` removes it after the merge; a free-text run (`cleanup none`) leaves its `ship-<slug>/` in place, and a run that stops before the merge gate leaves its record, which `init` then refuses to overwrite without `--rebuild`.
_Avoid_: task list, scratch file, plan file, todo

**Scratch directory**:
The directory a Ship run names in every subagent prompt as the one place that subagent writes scratch of its own: `<git common dir>/ship/scratch-<issue>/<role>/`, keyed by issue (or slug), so two runs with different keys never read each other's leftovers, `<role>` being that subagent's job in the run, and where that subagent writes its Report file. Edits to the repo are separate, and go under the worktree prefix. A sibling of the Run file's directory rather than a child, so a path a subagent invents below the one it was given still lands clear of the run's record. Passed at every dispatch the way the model tier is, and removed by `cleanup <issue>` with the Run file, except that a free-text run (`cleanup none`) leaves its `scratch-<slug>/` in place and a run that stops before the merge gate leaves its directory.
_Avoid_: scratch file (that names the Run file, and is avoided there too), temp directory, workspace

**Report file**:
The file a phase-4 pass writes its report to (a subagent's, where one was dispatched), at the path named in the producing role's Scratch directory, `<scratch>/<role>/<role>-report.md`, `<scratch>` being the directory `run-file init` printed, a subagent handing back only the path and a summary of at most five lines: one per `code-review` axis, and one for the `writing-for-agents` pass where it fired. No file there at hand-back is a report that failed to arrive. A report held in context alone is taken by a compaction, so the file is what a disposition and the merge summary's `Self-review` rows are read from; a row whose file is no longer on disk reads `unverified`.
_Avoid_: axis output, review log, findings dump

**Adjacent find**:
A problem outside the claimed issue that Ship meets while working it, whether the agent spotted it or a reviewer raised it. Filed for triage and left alone, unless an acceptance criterion names it, its fix lands in a file the PR already changes, or a reviewer of the PR would flag it, in which case it is fixed inline and logged as a deviation. Filing goes through `file-issue`, which answers with an existing open issue rather than creating a second one for the same find. Distinct from a deviation, which is the claimed issue's own work departing from its plan.
_Avoid_: drive-by fix, scope creep, nit, out-of-scope finding

**Candidate**:
An open issue whose title shares three or more tokens with an adjacent find the run is about to file, found by `file-issue` before it creates anything. The mechanic reports candidates and files nothing; the run reads each one and either links it in the deviations log as the same find, or refiles past it with `--distinct-from`. A report, not a verdict: the judgement of same-or-different is the run's.
_Avoid_: duplicate, match, near-miss, collision

**Ship defect**:
A gap in Ship itself met during a run: a host write or gating read no generic mechanic performs, or prose that promises what a mechanic does not do. Reported by name in the merge summary with a drafted issue for the source repo, which Ship files there only on the human's word at the merge gate, printing the command where the run cannot reach the source repo's host; never a hand-rolled call. A gap in the ship profile rather than in Ship is a profile defect: an adjacent find of the consumer repo, filed there. In Ship's own source repo the run is already upstream, so a Ship defect is also an adjacent find and takes its dispositions, and is still named on the summary's row.
_Avoid_: tooling gap, missing helper, upstream bug, profile defect (that is the consumer repo's)

### Profiles

**Ship profile**:
The per-repo document (`docs/agents/ship.md`) that carries every repo-specific fact Ship needs, one section per axis. A repo without a profile cannot run Ship.
_Avoid_: ship config, ship settings, project instructions (that is CLAUDE.md)

**Harness profile**:
The per-repo document (`docs/agents/harness.md`) that the harness setup skill writes and re-reads. It carries only what the repo cannot say for itself: the contracts other readers parse (the check entry point's path, the cloud setup's path), the human's choices with their reasons (a budget override, a local-only verdict), and proof state. Anything already recorded in the repo's own files stays out of it.
_Avoid_: harness config, harness.md (the path, not the concept)

**Profile schema**:
The integer a per-repo profile declares and its reader declares it reads: Ship for the ship profile, the harness setup skill for the harness profile. It moves only when the reader's expectations of the profile change; Ship refuses a run on a mismatch either way; the profile's setup skill migrates a trailing profile on its re-run and stops on one ahead. Separate from the reader's version, which moves on any change.
_Avoid_: profile version, format version, compat level

**Axis**:
One dimension along which repos legitimately differ in how they ship: worktree layout, local gate, reviewers, verification kind, versioning, PR template. The small-lane floor is not an axis: it is the same in every repo.
_Avoid_: option, knob, setting

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing, and stopping with the exact command when a prerequisite is missing. Two in the source repo, each a different concern: `setup-skills` drafts what Ship reads, and each later Ship document joins it as one more section; the harness setup skill drafts the agent harness and needs no Ship.
_Avoid_: init, scaffold, bootstrap

**Dimension label**:
A label on one of the three dimensions a repo's tracker carries beside the five triage roles: kind, size and priority, at most one label per dimension on an issue, stamped at triage time. `setup-skills` seeds the vocabulary, creating the labels on the host and writing the `## Dimension labels` section into a `docs/agents/triage-labels.md` that has none; the repo owns the section from then on. Implementation order is derived from priority, size and blocking edges and is never one of them: a rank label rots the moment a higher issue ships.
_Avoid_: tag, rank label, severity, t-shirt size

**Setup section**:
One unit of what `setup-skills` writes into a consumer repo, fed by one template file or directory of it: the PR template, the reviewer scaffolding, the local gate, the CLAUDE.md Ship block and the like. A refresh re-runs a section when its template moved, and a re-run holds the repo's whole file to the whole template, keeping the repo's own choices, rather than applying only the template's change.
_Avoid_: template, step, item

**Carried file**:
An untracked, gitignored file the ship profile names to be copied into the run's worktree when it is isolated, and left there. A run that changes one stops.
_Avoid_: env file (one kind of carried file), secrets, worktree setup

**Verification**:
One check the ship profile names that proves a change against the real thing the repo integrates with (a live org, a browser, a database in a container), scoped to what the change touched and run where the issue was reported. A repo lists zero or more; each names what it proves, when it applies, how to run it, what it needs, what Ship does without that, and which CI leg also proves it. A run's result for one is `pass`, `fail`, `deferred-to-ci`, `unavailable`, or `unexercised`, the last meaning its prerequisites held but every applicable path lacked a subject to drive, the subject being one another actor creates.
_Avoid_: e2e, integration test, smoke test, live test (kinds of verification), phase-3 hook

### Harness

**Agent harness**:
The repo-owned setup that lets any Claude Code session, cloud or local, prove its own work fast: one check entry point, pre-commit hooks, linters and formatters, the Claude Code hooks that run them, working language servers, installed dependencies, and the cloud setup that makes all of it available in the cloud sandbox. Configured for the cloud first; a repo is local-only only when the project needs it or the operator chooses it, and says why. The harness setup skill audits an existing harness and fills its gaps, keeping the repo's own choices; the local gate runs the check entry point rather than duplicating it.
_Avoid_: agent config, dev environment, tooling setup

**Check entry point**:
The one repo-owned command every rung but the commit rung calls, taking the rung and a file set and answering a verdict per check. It knows nothing of Ship; the local gate calls its full rung and adds only what is Ship's own.
_Avoid_: verification entry point (Verification is Ship's real-system check), verify script, test command

**Rung**:
One layer of the harness's check ladder, fastest first: edit (the edited file), turn (the uncommitted change set, at turn end), commit (staged files, owned by the repo's pre-commit runner) and full. A slower check never runs at a faster rung, and a rung over its budget warns the human rather than passing or blocking.
_Avoid_: layer, stage, level

**Budget**:
The seconds one rung, or the cloud setup, may take on a warm run. The harness setup skill ships a default per rung; a repo overrides one only with a reason the human gives, recorded in its harness profile, and the skill never raises one silently. A rung measured over its budget is narrowed, demoted to the next rung, or overridden before its hook is written.
_Avoid_: timeout (the hook's backstop, derived from the budget), limit, SLA

**Timebox**:
The optional `Timebox: <n> minutes` line of a ship profile's Verification entry: how long that verification may run. At an overrun, or a second failed rerun, it stops with the result `fail` and its evidence rather than looping. Named apart from a harness rung's Budget.
_Avoid_: budget, timeout, limit

**Stack**:
One language and its package manager, rooted at a directory whose manifest owns a lockfile or which a workspace config names: the unit that installs once and runs one set of tool versions. A polyglot repo or a monorepo holds several; a language the harness setup skill has no entry for is reported, never guessed.
_Avoid_: language, project, ecosystem

**Candidate root**:
A stack's manifest with no lockfile beside it that no root's workspace config names, which the harness setup skill asks the human to mark a root or ignored. The answer lands in the harness profile as a `Root: <manifest>` or a `Declined: <manifest> as a root` line, and a candidate root with neither line is new, so each run asks it.
_Avoid_: candidate (that is `file-issue`'s open-issue match), lockless root

**Fixture tree**:
A tracked `fixtures` or `testdata` directory, inputs a test reads that are often bad or byte-exact by design, which the harness setup skill asks the human to exclude or read. Excluded, it is recorded as an `Excluded: <path prefix>` line in the harness profile: detection reads nothing under it, and the pre-commit runner's exclude keeps every fix-mode tool off it. A fixture tree with neither that line nor a `Declined: <path prefix> as excluded` line is new, so each run asks it.
_Avoid_: test data, ignored tree

**Member**:
One workspace package inside a stack: the unit typecheck and affected tests run on, carrying its own tools or inheriting the stack root's. A stack with no workspace is its own single member.
_Avoid_: package (overloaded), module, subproject

**File kind**:
Tracked files that tools act on without a package manager, such as shell scripts, Dockerfiles, workflow YAML and Markdown. They take the edit and commit rungs only, never turn.
_Avoid_: pseudo-stack, file type

**Catalog**:
The harness setup skill's closed, shipped list of stacks and file kinds, one entry each, carrying the signals that detect it and the known tools per role (a default and its alternatives, each with its publisher and trust tier). It changes only through a change to the skill, never at run time: a stack with no entry is reported, and every tool drawn from an entry still passes the install check.
_Avoid_: registry, tool list, knowledge base

**Entry trial**:
One catalog entry's tools installed by the routes the entry names and run on a small clean tree, which must pass, and a planted-bad tree, which must fail, in a cloud session: the proof that the entry's claims about installing and running still hold.
_Avoid_: smoke test, catalog check (the check entry point is the repo's), probe (a probe measures an unknown)

**Surface**:
What a repo lets someone drive from outside its test suite: a web UI, an API, a CLI or a library's public API. A repo has zero or more, worked out afresh on every run from evidence the repo already carries and never recorded in the harness profile.
_Avoid_: repo kind (kind is already a file kind and a dimension label), app type, project type

**Behaviour tool**:
A trusted-tier tool that drives one surface beyond the test suite, such as a browser driver or a public-API checker. It runs on the full rung or on demand, never at a faster rung.
_Avoid_: verification tool (Verification is Ship's real-system check), e2e tool, smoke test

**Local-only**:
A verdict that a repo, or one rung of its harness, runs in a local session and not in the cloud sandbox, always recorded with its reason. A repo is local-only when evidence in it shows the project needs something the cloud sandbox cannot give (a non-Linux-x86_64 build, a private network, interactive or SSO auth, more than the VM holds, hardware or licensed tools, org IP allowlisting or Zero Data Retention, secrets that cannot be plain environment variables), or when the operator chooses it. A rung is local-only when the cloud cannot run it (repo-enabled plugins) or cannot yet reach it (a host the network policy blocks), and a language server always is, sitting on no rung. Neither makes the repo local-only. Hosting on Azure DevOps is not a reason: its cloud route is a human-started bundle session.
_Avoid_: offline, local mode, no-cloud

**Vendored plugin**:
A Claude Code plugin's config that the harness setup skill copies into a consumer repo's `.claude/skills/harness-<upstream>/` from one upstream commit, named in its README, so every machine runs the same config; nothing refreshes it but a later harness run. Language servers are wired only this way.
_Avoid_: derived copy (a shared skill installed from the source repo), installed plugin

**Bundle session**:
A cloud session a human starts from a local clone, which uploads that clone instead of cloning from GitHub: the only cloud route for a repo hosted elsewhere, such as Azure DevOps. It sees the local HEAD, pushed or not, plus edits to tracked files, but never untracked files, so anything it must run is committed first. No routine can start one.
_Avoid_: bundle upload, local cloud session

**Cloud setup**:
The harness's step that makes the whole harness available in a cloud session: run at the start of every cloud session, safe to rerun, knowing nothing of Ship. It installs every runtime, dependency and tool the check entry point runs. A failed cloud setup never stops the session, so whatever must not proceed on a broken sandbox runs it again and stops on its failure.
_Avoid_: setup script (the cloud environment's own slot, which the harness does not use), cloud bootstrap, provisioning

**Trust tier**:
One of the three ordered sources the harness setup skill installs from: Anthropic-authored plugins and docs; the tool's own vendor (which admits a partner entry in the official marketplace only when the partner makes the tool it wraps); the skill sources the consumer repo already pins. Being listed in a marketplace is not a tier. Anything outside the tiers is reported as found, not trusted, and never installed.
_Avoid_: allowlist entry, verified source, trusted marketplace

**Install check**:
What the harness setup skill runs before adding any third-party unit to a repo: read every file of the unit's glue (the config and scripts that make Claude Code run it), pin the unit and everything it launches, show what it runs and reaches and whether it reaches the cloud, then take one confirmation or refuse. A refused unit is named with its reason and never written; the human can still install it by hand. Deps restored from the repo's own lockfile and hook scripts the skill writes itself are not units.
_Avoid_: security review, vetting, audit (the audit is the whole skill's pass over a repo)

**Gap**:
One place where a repo's harness differs from what a fresh run of the harness setup skill would write or prove: a missing or incomplete piece, a broken contract, a pin that is broken or behind, a budget or proof no longer met, a stack or tool the harness does not yet cover. A re-run reports every gap; one the human declines with a reason becomes a standing choice and is not proposed again. The repo's own additions to a file the skill writes are departures it keeps, not gaps.
_Avoid_: drift (Upstream drift is a composed skill's), finding (a reviewer's), issue

### Distribution and Refresh

**Composed skill**:
A skill Ship takes a phase's logic from at the phase that needs it, rather than reimplementing it: `tdd`, `writing-for-agents`, `code-review`, `find-docs` and `show-me`. Ship loads each through the Skill tool, except `show-me`, which it reads as a file because its upstream disables model invocation. Ship's `metadata.composes` line names each with the repo and pinned ref it installs from, and preflight refuses a run before the claim when one is absent from the consumer repo's `.claude/skills/`, or its `skills-lock.json` records it at another ref. Adding one, or moving its pin, is therefore a breaking change for installed consumers. `setup-skills` composes `triage` the same way, so it counts as one wherever composed skills are pinned and checked. The inverse of a sibling skill: Ship composes these, a sibling composes Ship.
_Avoid_: dependency, sub-skill, helper skill

**Derived copy**:
The copy of a shared skill committed under a repo's `.claude/skills/`, installed from this repo and left as installed, every change going to the source. A repo's copy is what runs, in the attended and unattended lanes alike, and refreshing it is the repo owner's act. A shared skill is installed at repo scope, because a personal skill silently shadows a repo's.
_Avoid_: vendored fork, sync, symlink, snapshot

**Source repo**:
This repo, `Gharib89/skills`: where the skills recorded with `source: "."` in its lock, `skills-lock.json`, are written, and where the versions of their composed skills are tested. Every derived copy of those skills is installed from it.
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

**Retired term**:
A word a source-repo skill stops using, declared in that skill's `retired-terms.md` with the version that retired it and the word that replaces it, so a refresh that crosses that version can find the word in the consumer repo's own documents and replace it there, renaming a file whose name is the word.
_Avoid_: deprecated term, old vocabulary, stale wording

**Release run**:
The push-to-main workflow that owns every skill's `metadata.version`: it writes the number and cuts that skill's `CHANGELOG.md`, one run per skill, from the Conventional-Commit type of the squash subject. The `version-lines` gate refuses a PR that writes the line instead. `semantic-release` is the tool that runs it, and the value the ship profile's `Tooling:` line takes.
_Avoid_: release job, auto-bump, version bump PR

### Review

**Reviewer**:
One automated review bot the ship profile names for a repo, with its login, its trigger, whether it is gating (a required check that can block the merge), and the reviewer it is a fallback for. A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate. Preflight parses the blocks and refuses nine shapes before the claim: a fallback that is not on-request, one naming a reviewer nobody listed, an on-request reviewer with no cap, a `Cap:` that is neither a number nor `None.`, a `Request: comment` with no phrase for the transport to post, a comment transport with no `Workflow:` naming the file its round comes from, a `Workflow:` on a block no comment transport drives, a `Workflow:` naming a file the checkout does not carry, and a `Workflow: native <integration>` naming an integration ship has no reader for. One reviewer fact the blocks cannot settle themselves comes from the host instead: whether a Copilot reviewer's `Trigger:` matches the `copilot_code_review` ruleset that drives it.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push, on-request delivers one review per explicit request, and where the host still posts an opening round on its own, round 1 is polled from PR creation, so that round is round 1, and one already landed takes no request. The loop and mechanics follow the trigger alone; the bot's brand decides nothing. The profile's `Cap:` is a budget for the rounds **ship drives**, which is every round only where ship starts them: a reviewer the host re-runs on its own keeps posting past the number.
_Avoid_: mode, kind of bot

**Fallback reviewer**:
A reviewer driven only when the reviewer it names exits not reviewed, for any reason; a primary that reviewed leaves it unspent. Always on-request, because a reviewer that fires on every push cannot be withheld. When the primary reviewed, the fallback still reports, as not invoked, so the human sees it exists.
_Avoid_: backup bot, secondary reviewer, second opinion

**Request transport**:
How an on-request reviewer is asked for a round, named by its `Request:` line alone, whatever its brand. Two of them: the host's own request-a-reviewer call, for a reviewer the host can add to the PR, and the comment transport, `comment <phrase>`, which posts the phrase as a PR comment for a reviewer a comment triggers: a comment-triggered workflow, or a native integration such as Codex. Either way the request is read back off the host, and the since rule takes its timestamp from that read-back, so the clock is the host's.
_Avoid_: request method, trigger phrase (that is the workflow's own setting)

**Landing rule**:
Which reviews `poll-pr` accepts as the round it is waiting for, reported as `landed_by`. The reviewer's `Trigger:` picks the rule, which `poll-pr --reviewer` derives from its block. The head rule takes only a review on the current head, because an on-push reviewer earns a fresh one per push. The since rule takes a review submitted at or after the `--since <iso>` instant on any head, because an on-request or auto-once reviewer posts one round per request and a later push would otherwise strand it; that instant is the one value the poll cannot derive. Neither rule takes a row that is not substantive; a quota or rate-limit notice refuses the round rather than delivering it.
_Avoid_: landing check, freshness rule

**Substantive**:
A review row that counts as a round: one with text that is not wholly a quota or rate-limit notice, or a bodiless verdict (approved or changes). Ship grades it above the host, never in an adapter.
_Avoid_: real review, meaningful round

**Round clip**:
The 2000-character cap `poll-pr` puts on every review body, marked `...[truncated]` where it bites, so one poll cannot flood the run's window. `--brief --full <id>` lifts it for the rows it names and nothing else, and `--full` without `--brief` is refused. It covers review bodies alone. A `--brief` thread row's `lead` is its first line with text, cut at 200 characters, and carries the same marker where either cut bites: past 200 characters, or where a later line with text was dropped. Naming the thread in `--brief --full <id>` returns its first comment whole as `lead`. A reviewer that opens with a preamble pushes its findings past the cap, and a round or lead that comes back clipped is one phase 7 has not read.
_Avoid_: truncation, body limit

**Reviewed**:
A reviewer's phase-7 exit where at least one of its rounds landed and every finding in it carries a disposition, whether or not a later round landed. A gating reviewer's declined finding is still reviewed, cited at the merge gate as the override the human decides on.
_Avoid_: converged, approved, clean, passed

**Not reviewed**:
A reviewer's phase-7 exit where no round of it landed, or one did and its threads could not be read (unreachable), named by the cause a mechanic observed: poll-pr's `not_reviewed` (unreachable, blocked, never-queued, still-running, stale-head, infra-error, silent) or request-review's exit 1 (never-queued). It still proceeds to the merge gate on green CI, the human's call there rather than a hand-back.
_Avoid_: degraded, failure, timeout, skipped review

**Not invoked**:
The phase-7 exit belonging to a fallback reviewer whose primary reviewed: it went unrequested, so it has no rounds and no findings. Neither reviewed nor not reviewed, and the run carries on past it. It is reported anyway, in the PR body and the merge summary, so a reader sees a reviewer that exists and was deliberately not spent rather than one nobody configured.
_Avoid_: skipped, not needed, n/a

**Shape**:
The compressed code-form view of a change, sitting under a PR body's `## Change outline`: a call tree, control flow, pseudocode or component tree, written as a `diff` fence so the before and the after sit in one view. **One behavioural fence per PR**, about 15 lines or fewer, every node a real symbol and every root node carrying its file path; a carrier file tree may follow it, and only where the same edit lands in more than two files. The `Shape: none, mechanical (<kind>).` line replaces the fence only where the reviewer's question is "did the text change correctly", never where it is "what does X now do", and omitting both silently is a finding.
_Avoid_: diagram, visual, picture, mermaid, sketch

**Body preamble**:
Everything in a PR body above its first `## ` heading, which is the closing reference and nothing else. The half of a body no section rewrite reaches, and `update-pr-body --preamble` is what rewrites it, carrying over a closing line the new content lacks so a rewrite that says nothing about closing keeps the link to the issue; content carrying its own closing line is left as written, whichever issues it names.
_Avoid_: header, intro, top of the body

### Grilling

**Grilling round**:
One frontier of the design tree put to the human at once: every decision whose prerequisites are settled, each numbered and carrying a recommended answer, answered together before the next frontier is computed. In `grill-with-artifact` a round is a section of the artifact, and a round the human submits leaves each question answered or deferred.
_Avoid_: round alone outside `grill-with-artifact` (elsewhere a round is a reviewer's round), batch, turn, step
