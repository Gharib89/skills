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

**Project setup**:
The one run that takes a folder, whether empty, loose code with no git or already a git repo, to a consumer repo ready for its first Ship run, by following every setup skill in order, each in its own first-run or re-run mode. It holds no record of its own: what is done is read from the per-repo documents those skills write and from the lock. Re-running it is how a repo catches up, since each followed skill proposes only what is missing or behind. `setup-project` performs it.
_Avoid_: bootstrap, onboarding, setup-all, meta-setup

**Setup status**:
The table a project setup reads at its start and again at its end: one row per step in fixed order (tools, repo and remote, installed skills, Matt's setup, the harness, Ship's setup, the proof), each `done`, `re-run audit` or `run`, read from the files that step leaves behind. The human confirms it once before anything is written, and the run is done when every other row reads `done` and Ship's preflight admits a run, which settles the proof row.
_Avoid_: plan, checklist, status report

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
