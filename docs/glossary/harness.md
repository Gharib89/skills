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
Tracked files that tools act on without a package manager, such as shell scripts, Dockerfiles, workflow YAML and Markdown. They take the edit and commit rungs only, never turn, unless a repo hand-adds a turn row for one (this repo does for shell, in `docs/agents/harness.md`).
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
The harness's step that makes the whole harness available in a cloud session: run at the start of every cloud session, safe to rerun, knowing nothing of Ship. It installs every runtime, dependency and tool the check entry point runs. A failed cloud setup never stops the session, so whatever must not proceed on a broken sandbox runs it again and stops on its failure. With `--local` it runs the same steps on a developer's machine, which the check entry point names under a check whose tool is missing; a local-only repo has it for that run alone, with no `SessionStart` entry.
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
