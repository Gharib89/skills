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
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: run-file, prepare, tooling, preflight, read-issue, manage-issue (take, release, hand back, close), isolate, base-fresh, open-pr, reflect, read-pr, poll-pr, request-review, comment-issue, comment-pr, reply-thread, update-pr-body, update-pr-title, update-issue-body, resolve-thread, CI wait, merge, cleanup, file-issue, list-prs, select. Every gating call in a Ship run goes through one of them, and a missing one is a Ship defect, not a prose fallback; any other host call may be a direct call. Not every one reaches a host: `run-file` writes the run's own record and nothing else. Their reads speak one vocabulary on every host, and a failed write to a PR (its body, its title, a comment, a thread reply) or to an issue (a comment, its body) answers with the HTTP status of the last attempt, `null` where the host reported none, so a run can tell a payload the host refused from a host that was briefly down. Every one of them answers `--help` with its usage line on stdout and exit 0, reaching no host: that is where a run reads a mechanic's flags.
_Avoid_: helper, util, raw `gh` or `az` call (for a gating call)

**Gating call**:
A host read or write that a later phase, a stop row, the merge or the release depends on, such as preflight's admission, poll-pr's round, CI wait's legs, the claim, the PR's title and body, or the merge itself. It goes through a generic mechanic, so the same host state always gives the same verdict and every write is read back. A gating read and a gating write are its two kinds.
_Avoid_: load-bearing call, check, probe

**Direct call**:
A host read or write that no phase, stop, merge or release depends on, made by the run itself through the host's REST form where no mechanic covers it, and logged in the Run file. One made in two runs, where this run can see the other, is a candidate mechanic, raised as a Ship note. Verification scaffolding (a scratch issue, scratch review thread or throwaway probe PR set up by hand) is not a direct call and sits outside the rule.
_Avoid_: informational read, side call, ad-hoc call

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
The assignee on a tracker issue, set by Ship before any work. An assigned issue is in flight or awaiting merge and no run takes it; the same rule in every repo, not an axis. Exclusive: one run holds it. A take that finds another identity beside its own is _contested_ and gives its own assignment back; a run started at preflight that finds its own identity already assigned yields to the run holding it.
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

**Rework run**:
An attended Ship run a human starts on an issue whose earlier run left its PR open at the merge gate, attended or unattended. It takes the PR's unresolved review threads whose latest comment is not Ship's own, the authoritative comments left on its PR since the head push (less Ship's own), and any feedback the human gives at the start as the change to make, and works it on the same claim, branch and PR, ending at a fresh merge gate. It needs the claim to be the human's own and one open PR on the issue's branch; with no feedback it stops before any change.
_Avoid_: resumed run (a run continuing its own record after a context loss), iteration, follow-up run

**Cloud sandbox**:
The container any cloud session runs in, attended or unattended, reaching hosts only through the session proxy. Its image, network policy and refusals (GitHub GraphQL among them) are facts Ship adapts to, not settings a repo owns. The lane decides which issues a run admits; the sandbox decides what the run must prepare before it can work.
_Avoid_: cloud env, default env, container

**Merge gate**:
The end of a Ship run where its full summary records the merge decision. By default an attended run waits for the human's exact "merge"; a profile with `Merge: on-clean-gate`, or an inline-lane run, authorizes a merge when `run-file gate clean` confirms every recorded condition, including that no criterion is unmet, since each needs the human's waiver. An unattended run posts to the PR and returns.
_Avoid_: approval, sign-off, review

**Clean gate**:
The recorded conditions permitting an attended run to merge without a reply when its profile opts in or the run is in the inline lane: every CI leg green, every local gate passed or deferred to CI on the PR head (a deferral holds the gate while a CI check outside the legs is not green), every reviewer's loop stopped on an unchanged tree at a covered head (a fallback answers for its primary) or on the inline lane, every applicable Verification passed at a covered head or deferred to a green CI leg, no unmet criterion, and no override or Tracker draft. Deviations and Ship defects alone do not hold it.
_Avoid_: auto-merge (a host flag that can merge before Ship finishes its reviews)

**Covered head**:
The PR head a piece of clean-gate evidence still answers for. A reviewer's unchanged-tree stop or a Verification's pass covers the head it was recorded on, and a later head reached from it only by clean merges of the base, each one's tree what merging the two parents gives with no conflict to resolve. A Verification whose profile entry names `Paths:` also covers a later head when none of the files those paths match has changed since; a path matching no file at either head proves nothing. The Local gate record covers its own head alone. Evidence that does not cover the PR head holds the clean gate.
_Avoid_: current, fresh, up to date

**Small lane**:
The collapsed form of a Ship run for a change that is narrow, locally provable, invisible to the public surface and within the small lane's size, a judgment the run confirms on the diff when it opens the PR; revocable mid-run. It drops planning breadth and keeps every check: the floor is the same in every repo and is worktree isolation, the local gate's small floor (the repo's security check plus the test proving the change, or the full gate where more than one test proves it), the self-review, the PR, CI plus every reviewer per its trigger, and the merge gate. The self-review runs at full width in every lane, whether or not a reviewer exists, because it is the only check that reads the diff against the issue. Its tier for a fix triage already has in hand is the inline lane.
_Avoid_: fast path, quick mode, hotfix

**Inline lane**:
The small lane's tier entered only by `/ship <issue> --inline`, attended and for a tracked issue: the same floor, a 20-line cap counted on the diff, no reviewer round unless `--review` buys one, and a merge on a clean gate, the invocation being the human's approval for that one PR. Revocable one way, inline then small then full, and the approval goes with the lane.
_Avoid_: inline fix (the hand-made PR it replaces), one-liner lane

**Hand-off**:
An attended stop where Ship prints the exact command and setup, waits for the human to run or confirm it, and resumes. The claim holds. In an unattended run a hand-off becomes a hand-back.
_Avoid_: pause, wait-state, hand-back (that releases the claim)

**Unmet criterion**:
Any criterion of the issue the run did not meet, recorded in the Run file as `Criterion <n>: not met: <reason>`, or owed a line and given none. The kind a run cannot meet is a criterion asking for a host action no mechanic performs, which it leaves verbatim in the issue and lists on the merge summary with the action a human must take: unattended always, attended when the human, asked before building, says to build the rest. Either kind holds the clean gate, and merging needs the human's explicit waiver of each, beside the merge word. A host-action criterion is not a Ship defect: the action is the issue's deliverable, not a step the run itself must perform.
_Avoid_: rewritten criterion, descoped criterion

**Spec precedence**:
The rule that a later triage brief or authoritative comment, each posted by someone with write access to the repo, supersedes the issue body: where they conflict, the latest one wins and the body's original acceptance criteria no longer bind.
_Avoid_: override, latest-wins

**Authoritative comment**:
A comment on the issue, or on a rework run's PR, by someone with write access to the repo. Only it, or a triage brief by such an author, can supersede the issue body under spec precedence; any other comment, a brief by anyone else included, is context, never spec. A comment whose author's access cannot be read is not authoritative, in every lane.
_Avoid_: maintainer comment, official comment
