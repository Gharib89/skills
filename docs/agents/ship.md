# Ship profile

Schema: 2

Every repo-specific fact `/ship` needs, one section per axis. Vocabulary: [CONTEXT.md](../../CONTEXT.md).

This repo is both the **source** of the shared skills and a **consumer** of them: `skills/<name>/` is the source of truth and `.claude/skills/<name>/` is the derived copy that actually runs. A change to a skill is not shipped until both carry it.

## Host

Host: github

## Worktree

Carry: None.
Bootstrap: None.

Nothing here is gitignored and nothing needs installing: the mechanics are bash, and the gate's only download is `npx -y shellcheck`, cached per machine.

## Local gate

Location: scripts/local-gate.sh
Small node: the path of the changed script, e.g. `skills/ship/scripts/merge.sh`; for a `docs`-class change, the path of the changed document, e.g. `skills/ship/SKILL.md`
Tripwires: None.

Every gate is repo-wide and takes seconds, so the small lane records the node and narrows nothing. No workflow here runs on a PR head, so no gate is ever `deferred-to-ci`: the gate is the whole automated check on a diff, alongside the reviewers.

`tests` runs `tests/run.sh`, and it runs every `tests/*.test.sh`. Their subject is the pure transformations the mechanics are built around (`ship_body_replace_section`, `ship_body_closes`, `ship_title_candidates`, `_gh_add_closes`): a test sources its function and asserts on strings. A gate script is the second subject: `contract-gate` runs `scripts/contract-check.sh` against a copy of the mechanics and asserts on its exit code, reaching no host either. A mechanic's usage guard is the third: `manage-issue-usage` invokes the mechanic malformed, which the guard answers before `ship_load_host`, so no host is reached there either. A helper whose subject is an order of calls rather than a string is the fourth: `create-verify` drives `_gh_create_verify` with stub post and find functions, so the create-then-verify sequence is asserted without a host. A function whose subject is the request it sends is the fifth: `api-retry` puts a fake `gh` on PATH that drains stdin before it fails, so the REST wrapper's retry is held to resending the bytes the first attempt sent, with the fake in place of a host. A behavioural claim about one of them earns a case here, where it survives the run that made it, instead of a scratchpad probe that does not. The `host_*` functions stay the `github-mechanics` verification's job: a test that reaches a host is that verification, not this gate.

`contract` holds a new mechanic to the malformed-invocation contract `## Public surface` names: no `${N:?}` or `${N?}` expansion under the mechanics, and a bare invocation of one that requires an argument answering with a single JSON error object and exit 2. A third check traverses the whole `skills/` tree rather than the mechanics alone, for the Bash 4 constructs a consumer machine's Bash 3.2 lacks; the `setup-skills` local-gate template is excepted, being repo-local once installed. A fourth invokes every mechanic that takes a positional with one, two and three `--x` arguments and holds each answer to that mechanic's own usage line and exit 2, because a flag typed where an id belongs is a malformed invocation, not an id. A fifth holds every mechanic, none exempted, to answering `--help` with its own usage line on stdout, exit 0 and nothing on stderr: that is where a run reads a mechanic's flags, so an answer it cannot trust is worse than none. The gate reaches no host while the contract holds, because every usage guard fires before its mechanic loads the adapter: an unguarded mechanic is what makes check 4 reach one, and that call is the finding, and check 5's empty-stderr assertion is what catches a `--help` answered after the adapter loaded.

`derived-copies` is the drift gate. It fails when `.claude/skills/<name>/` differs from `skills/<name>/` for `ship`, `cloud-ship` or `setup-skills`, which is what makes the refresh below non-optional rather than a habit. It also holds the profile schema number consistent across the three files the bump rule in [profile-schema.md](../../skills/setup-skills/profile-schema.md) moves together, the `Schema:` line in `skills/setup-skills/ship-profile.md`, `metadata.profile-schema` in `skills/ship/SKILL.md`, and that doc's own `## Schema <n>` entry for ship's number, failing with one message naming all three. That is the same drift one level up: a ship that moves to a new schema while the template stays at the old one has every profile drafted from that template refused by the next run, with every gate here green.

## CI

Legs: None.
No-checks legal: yes, the one workflow is comment-triggered and never runs on a PR head
Push policy: Default.

The one workflow, `.github/workflows/claude-review.yml`, is triggered by an issue comment carrying `@claude` and has no `pull_request` trigger, so it lands no check run on a PR head and is not a leg. It is the `claude` reviewer below, not CI.

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: .github/copilot-instructions.md

The review itself lands under `copilot-pull-request-reviewer[bot]`, which is the login `poll-pr --await-review` takes; the inline comments arrive under Copilot's own name, so a thread's author and the round's author differ here. `Request: None.` because the host adds this login to the PR's reviewer list, so a bare `request-review` is the transport and no comment phrase is needed.

Enabled by the repository ruleset **Copilot code review** on the default branch, with `review_on_push: false`. That setting, not the brand, is what fixes the trigger. `false` still opens one round when the PR does and never again on a push, which is the free first round the `on-request` loop reads under the since rule before it spends a request; every round after it is a request ship issues, so `Cap: 3` is the number of rounds this reviewer actually gets. Flipping `review_on_push` back to `true` makes it `on-push`, and this block must move with it: preflight reads the ruleset and refuses the pair when they disagree.

Under `on-push` the cap is advisory: a ruleset that re-reviews every push keeps posting whatever `Cap:` says, so the number bounds only how long ship waits, and a bound that cannot be enforced is worse than a slower loop that can.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Cap: 2
Resolve: resolve-thread
Gating: no
Fallback-for: copilot
Instructions: .github/copilot-instructions.md

Claude Code on GitHub Actions, `.github/workflows/claude-review.yml`, standing in for Copilot on the month its quota runs out. Driven only when `copilot` exits degraded, for any degraded reason; on a run where Copilot converges it reports `not invoked: copilot converged` and costs nothing. The workflow posts its findings as one formal review per round, which is what `poll-pr --since` lands, and the action attaches the per-file ones as inline threads on that review, so `Resolve: resolve-thread` the way Copilot's rounds resolve. A finding that names no file stays on the review body and is answered with `comment-pr`, which leaves nothing to resolve. `Login:` is `claude[bot]`: the round is posted by `anthropics/claude-code-action` under the Claude GitHub App the workflow's `claude_code_oauth_token` authenticates, not under the Actions identity. Only the `if: failure()` comment below the action runs on `github.token`, and that comment is not a round, so the login the loop awaits is the app's. The exit is still `degraded: silent` when a round dies before posting, because `poll-pr` does not read a plain comment as a round, but where the job fails the workflow leaves one naming the run and the failure subtype, so the reason is on the PR and not only in the Actions log. A cancelled job runs no step and still leaves nothing.

## Coding standards

docs/contributing/coding-standards.md

## Verification

### github-mechanics

Proves: a changed generic mechanic or the GitHub adapter performs its host call against a real issue, PR, thread or merge.
Applies when: the change touches `skills/ship/scripts/`, on any path the GitHub adapter reaches.
Run: drive the changed mechanic by hand against a scratch issue on this repo, the way issues #30 and #31 were used, then `manage-issue <n> close` to close the scratch issue after. Where the change reaches the PR body, the run's own PR is the subject and no scratch PR is needed: open it carrying the attribution footer, and after the phase-7 `update-pr-body --section Review` write, `read-pr` reads the body back and confirms the footer is still there. Where the change reaches the body's preamble, the same PR is the subject of an `update-pr-body <pr> --preamble` write, read back the same way, confirming the closing reference survived it. The thread-reply path is driven against a thread the reviewer opened on that same PR; the reviewer opens it and ship does not, so a PR carrying none at convergence leaves that path unexercised. The verification then takes the result of the paths that did run, and its `<what ran>` note on the merge summary's `Verification` row names the unexercised one for the human to weigh. Where the thread-reply path is the **only** path the change touches, a threadless PR leaves no path to take a result from, and the verification's result is `unexercised`.
Needs: `gh` signed in with push permission on `Gharib89/skills`.
Without it: hand-off
Also proven by CI: None.
Claims to probe: the REST response shapes and api-versions the adapter reads, and whether the call is one GitHub still serves.

### ado-mechanics

Proves: a changed Azure DevOps adapter performs its host call against a real work item, PR, thread or completion.
Applies when: the change touches `skills/ship/scripts/host/ado.sh`.
Run: drive the changed mechanic by hand against the `ship-ado-lab` repo in the `AI_And_Data_Practice` project. A scratch round opened there is dispositioned with `resolve-thread` and left in place: the lab PR is a shared fixture whose resolved rounds accumulate, and no mechanic removes them. A later verification picks its own round out of `all[]` by `submitted_at`, then reads it whole: `poll-pr <pr> --await-review <login> --since <iso>` reports a round at or after that time as `landed_by: since`, and `poll-pr <pr> --full <id>` lifts the round clip on that row alone.
Needs: `az login` with Entra (the PAT path has known gaps, issue #29) plus the `azure-devops` extension.
Without it: blocked
Also proven by CI: None.
Claims to probe: the api-version each call pins, and the work-item type and closed state the lab's tracker template declares.

## Versioning and changelog

Tooling: manual
Reads: `metadata.version` in each skill's `SKILL.md`; `metadata.profile-schema` in `skills/ship/SKILL.md`
In-PR requirement: a change to a skill bumps that skill's `metadata.version` in the same PR, graded patch, minor or major by the public-surface rule in [coding-standards.md](../contributing/coding-standards.md); a change to what `ship` expects of a profile also bumps `metadata.profile-schema` and adds the matching `## Schema N` entry to `skills/setup-skills/profile-schema.md`
Subject constraints: conventional-commit prefix scoped to the skill, e.g. `fix(ship):`

## PR

Template: .github/pull_request_template.md

## Public surface

Everything a consumer repo depends on, all of it under `skills/`:

- each skill's name, `description` and `argument-hint`, which decide when an agent reaches it
- `ship`'s flags and its stop-reason vocabulary
- every generic mechanic's CLI signature and the shape of the JSON it prints
- the local-gate contract: the flags, the gate statuses, the verdict
- the ship profile's fourteen headings, their `Label:` lines, and the schema number
- the `### Ship` CLAUDE.md block `setup-skills` writes
- the `setup-skills` templates, which land verbatim in consumer repos
- `ship`'s `metadata.composes` line: the set of skills a consumer must have installed for a run to pass preflight

## Triage

File as an issue labelled `needs-triage`.

This repo is Ship's own source, so a run here is already upstream and a **Ship defect** met during the run is an adjacent find: it takes phase 2's dispositions, through `file-issue` and its candidate check, and is still named on the merge summary's `Ship defects:` row. ADR 0001 stands, because the write still goes to the repo the run is in, which here is the repo the defect belongs to.

## Docs sync

Targets: CONTEXT.md, docs/adr/, docs/agents/, skills/setup-skills/profile-schema.md, .out-of-scope/
Agent-facing: all of them, plus skills/ and .claude/skills/

Every file this repo ships is read by an agent, so `writing-for-agents` applies to the whole diff, not to a subset of it.

## Current docs

Sources: context7
Pinned: None.

The skills CLI (`npx skills@latest`) is unpinned and its behaviour is load-bearing: it decides what a derived copy is and what `skills-lock.json` records. Check its `--help` rather than assuming a flag.

## Cloud lane

PR cap: 3
Bootstrap: None.
