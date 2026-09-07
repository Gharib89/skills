# Skills

Ahmed Gharib's shared agent skills, installed globally into every repo the same way the mattpocock skills are. Each skill is written once here; a repo expresses its own differences through per-repo docs, never by forking the skill.

## Language

**Ship**:
The skill that drives one tracker issue from nothing to a merge-ready PR in a single unattended run, stopping at the merge gate.
_Avoid_: pipeline, deliver, autopilot

**Ship profile**:
The per-repo document (`docs/agents/ship.md`) that carries every repo-specific fact Ship needs, one section per axis. A repo without a profile cannot run Ship.
_Avoid_: ship config, ship settings, project instructions (that is CLAUDE.md)

**Axis**:
One dimension along which repos legitimately differ in how they ship: worktree layout, local gate, review-bot topology, verification kind, versioning, PR template, small-lane floor.
_Avoid_: option, knob, setting

**Local gate**:
The repo-owned script that runs every check the repo's CI would run, locally, before a PR opens. The only Ship mechanic whose body is the repo itself.
_Avoid_: pre-push checks, lint step, test step

**Generic mechanic**:
A Ship script whose behavior is the same in every repo once the profile supplies its parameters: preflight, manage-issue (take, release, hand back), isolate, CI wait, merge, reflect.
_Avoid_: helper, util

**Setup skill**:
A user-invoked skill that explores a repo and drafts its per-repo documents, confirming with the human before writing. `setup-ship` drafts the ship profile.
_Avoid_: init, scaffold, bootstrap

**Sibling skill**:
A skill that composes Ship rather than reimplementing it. Today there is one: `cloud-ship`, which picks an issue in a cloud routine and runs Ship unattended. Only Ship claims an issue; a sibling never pre-claims.
_Avoid_: wrapper, plugin, variant

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
The collapsed form of a Ship run for a change the whole team would call trivial; keeps a fixed floor of checks and is revocable mid-run.
_Avoid_: fast path, quick mode, hotfix

**Reviewer**:
One automated review bot the ship profile names for a repo, with its login, its trigger, and whether it is gating (a required check that can block the merge). A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push and its rounds are free, on-request delivers one review per explicit request and is capped. Convergence and mechanics follow the trigger, never the bot's brand.
_Avoid_: mode, kind of bot

**Converged**:
The phase-7 exit where CI is green and every reviewer is settled per its trigger: auto-once threads all dispositioned; on-push quiet on the current head with every thread dispositioned and resolved; on-request latest round nothing actionable and every thread dispositioned. Silence on the current head is never quiet.
_Avoid_: approved, clean, passed

**Degraded exit**:
A phase-7 exit that is not converged but still proceeds to the merge gate on green CI, named by one reason per reviewer: never-queued, blocked, silent, infra-error, cap-hit, unreachable. Never a hand-back on its own; the human reads it and decides.
_Avoid_: failure, timeout, skipped review

**Host**:
The platform holding a repo's code, pull requests, CI and tracker: GitHub, or Azure DevOps (Repos, Pipelines, Boards). The ship profile names it; every generic mechanic has one implementation per host inside the skill, selected, never generated.
_Avoid_: tracker (Boards is one part of a host), provider, platform
