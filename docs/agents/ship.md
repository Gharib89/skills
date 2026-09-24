# Ship profile

Schema: 3

Every repo-specific fact `/ship` needs, one section per axis. Vocabulary: [CONTEXT.md](../../CONTEXT.md).

This repo is both the **source** of the shared skills and a **consumer** of them: `skills/<name>/` is the source of truth and `.claude/skills/<name>/` is the derived copy that actually runs. A change to a skill is not shipped until both carry it.

## Host

Host: github

## Worktree

Carry: None.
Bootstrap: None.

Nothing here is gitignored. The mechanics are bash; the gate needs `gitleaks` on PATH for its `secrets` gate, and a `shellcheck`, which it fetches once per machine with `npx -y shellcheck` when none is on PATH.

## Local gate

Location: scripts/local-gate.sh
Small node: the path of the changed script, e.g. `skills/ship/scripts/merge.sh`; for a `docs`-class change, the path of the changed document, e.g. `skills/ship/SKILL.md`
Tripwires: None.

Every gate is repo-wide and takes seconds, so the small lane records the node and narrows nothing. The one workflow on a PR head, `bump-guard`, reads the PR title rather than the diff, so no gate is ever `deferred-to-ci`: this script is the whole automated check on a diff, alongside that leg and the reviewers.

`tests` runs `tests/run.sh`, and it runs every `tests/*.test.sh`. Their subject is the pure transformations the mechanics are built around (`ship_body_replace_section`, `ship_body_closes`, `ship_title_candidates`, `_gh_add_closes`): a test sources its function and asserts on strings. A function that reads a repo file is that same subject with a fixture for the file: `triage-label` sources `ship_triage_label` and runs it inside throwaway checkouts under the OS temp dir, one of them carrying a copy of this repo's own label file, because the function resolves that file through the main checkout rather than the worktree a run works in. A gate script is the second subject: `contract-gate` runs `scripts/contract-check.sh` once per fixture and asserts the exit code and the stdout of that one run, because the verdict and the violation it names are two readings of one run, reaching no host either. A mechanic's usage guard is the third: `manage-issue-usage` invokes the mechanic malformed, which the guard answers before `ship_load_host`, so no host is reached there either. A helper whose subject is an order of calls rather than a string is the fourth: `create-verify` drives `_gh_create_verify` with stub post and find functions, so the create-then-verify sequence is asserted without a host. A function whose subject is the request it sends is the fifth: `api-retry` puts a fake `gh` on PATH that drains stdin before it fails, so the REST wrapper's retry is held to resending the bytes the first attempt sent, with the fake in place of a host. A mechanic driven end to end is the sixth: `run-file` writes and flips its own file, so `run-file` invokes the mechanic against a scratch directory under the OS temp dir and asserts on the lines it wrote, reaching no host and no repo file. A mechanic driven over the Host fake is the seventh: `reviewer-run` and each pass-through mechanic's test point `SHIP_HOST_ADAPTER` at `tests/host-fake.sh` inside a throwaway GitHub-origin checkout, so the mechanic's own envelope is the subject and fixtures stand where the host would; `host-contract` holds that fake to the real adapters' function set and its defaults to the `_lib.sh` key sets. A mechanic driven end to end over the real GitHub adapter is the eighth: `request-review-readback` puts a fake `gh` answering per endpoint, and a no-op `sleep`, in front of PATH inside a throwaway GitHub-origin checkout, because the Host fake replaces the adapter function whose logic is the subject. `gh-threads-proxy` is an eighth-kind test too, its fake `gh` applying each call's own `--jq` to raw fixtures, so the thread functions' GraphQL path and the REST path they take on the cloud proxy's refusal are held to one row shape. A behavioural claim about one of them earns a case here, where it survives the run that made it, instead of a scratchpad probe that does not. The `host_*` functions stay the `github-mechanics` verification's job: a test that reaches a host is that verification, not this gate.

`prose-budget` holds the shape of ship's own documents, the one gate here whose subject is prose rather than a script: `skills/*/SKILL.md` at most 400 lines, and every `skills/*/reference/*.md` over 100 lines opening with a `## Contents` heading inside its first 15 lines whose list matches the file's `## ` headings, each heading listed and each entry naming a heading that exists. A run reads `SKILL.md` whole at load and re-reads it after a compaction, so a file that outgrows the budget spends that read on reference material and reaches phase 0 late; the `## Contents` list is what makes a long reference file answerable without reading it through, and a list that drifted from the file sends that reader to a heading that is not there, which is worse than no list. `scripts/prose-budget-check.sh` is the whole rule, a script rather than a function in the gate so `tests/prose-budget.test.sh` can drive it against fixture trees, the way `derived-copies` calls `scripts/profile-schema-check.sh`. A `## ` inside a fence is an example: it needs no entry, and no entry may name it.

`version-lines` refuses a diff that changes a `metadata.version` line under `skills/`, which `## Versioning and changelog` below hands to the release run on main. `scripts/version-line-check.sh` is the whole rule: it compares the merge base with the working tree, so an uncommitted bump is caught alongside a committed one, and it needs a *removed* version line, because a new skill arrives carrying its first and a file can gain a metadata block it did not have. `metadata.profile-schema` is exempt.

`stray-files` refuses a tracked path outside the top-level entries this repo owns, the allowlist being `dirs` and `files` in `scripts/stray-file-check.sh`, stated once more in that file's header. It reads the index rather than the working tree, so scratch a run leaves behind is not a finding and a file a `git add -A` swept in is.

`contract` holds a new mechanic to the malformed-invocation contract `## Public surface` names: no `${N:?}` or `${N?}` expansion under the mechanics, and a bare invocation of one that requires an argument answering with a single JSON error object and exit 2. A third check traverses the whole `skills/` tree rather than the mechanics alone, for the Bash 4 constructs a consumer machine's Bash 3.2 lacks; the `setup-skills` local-gate template is excepted, being repo-local once installed. A fourth invokes every mechanic that takes a positional with one, two and three `--x` arguments and holds each answer to that mechanic's own usage line and exit 2, because a flag typed where an id belongs is a malformed invocation, not an id. A fifth holds every mechanic, none exempted, to answering `--help` with its own usage line on stdout, exit 0 and nothing on stderr: that is where a run reads a mechanic's flags, so an answer it cannot trust is worse than none. The gate reaches no host while the contract holds, because every usage guard fires before its mechanic loads the adapter: an unguarded mechanic is what makes check 4 reach one, and that call is the finding. Check 5 is where placement stops being a convention: it runs each mechanic from a directory where no origin remote resolves, so a guard sitting after `ship_load_host` answers `--help` with the adapter's tooling error and fails, while a mechanic that guards first answers its usage line from anywhere. It also holds that answer to the same string the mechanic's own guards print, because the two are separate paths and a second copy going stale is what this contract replaced; `base-fresh` and `select` are the only two that comparison skips, their guards answering a bad call with a takes-no-arguments line rather than a usage one. A sixth holds `SHIP_HOST_ADAPTER`, which swaps the host adapter for the test suite's Host fake, to its one reader, `ship_load_host` in `_lib.sh`: any other mention under `skills/`, prose included, is a mechanic that can be pointed off its host.

`derived-copies` is the drift gate. It fails when `.claude/skills/<name>/` differs from `skills/<name>/` for `ship`, `cloud-ship` or `setup-skills`, which is what makes the refresh below non-optional rather than a habit. It also holds the profile schema number consistent across the three files the bump rule in [profile-schema.md](../../skills/setup-skills/profile-schema.md) moves together, the `Schema:` line in `skills/setup-skills/ship-profile.md`, `metadata.profile-schema` in `skills/ship/SKILL.md`, and that doc's own `## Schema <n>` entry for ship's number, failing with one message naming all three. That is the same drift one level up: a ship that moves to a new schema while the template stays at the old one has every profile drafted from that template refused by the next run, with every gate here green.

## CI

Legs: bump-guard: the PR title is a Conventional Commit of a type the release run reads, and a title implying a major bump carries the `major` label
No-checks legal: no, `bump-guard` is not path-filtered and reports on every PR
Push policy: Default.

`bump-guard` is the one leg. It runs on `pull_request` opened, edited, synchronize, labeled and unlabeled, is not path-filtered, and reports on every PR, so a run always has a check to await. Its subject is the PR title, because the release run on main grades the bump from the squash subject: a red leg here is a title to fix with `update-pr-title`. It reads the branch's commit messages too, because a `BREAKING CHANGE:` footer in one of them reaches the release run through the squash body, and it reads the description for the same footer, so neither text grades a major bump the guard has not seen. The one red run cannot clear is the `major` label, which only the maintainer applies: a run whose change grades major keeps the `!` in the title, leaves the leg red, and asks for the label at the merge gate rather than dropping the `!`, which would under-grade the release.

Two workflows are not legs. `.github/workflows/claude-review.yml` is triggered by an issue comment carrying `@claude` and has no `pull_request` trigger, so it lands no check run on a PR head: it is the `claude` reviewer below. `.github/workflows/semantic-release.yml` runs on push to main, after the merge, so no PR ever sees it.

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: .github/copilot-instructions.md

The review itself lands under `copilot-pull-request-reviewer[bot]`, which is the login `poll-pr --reviewer copilot` awaits; the inline comments arrive under Copilot's own name, so a thread's author and the round's author differ here. `Request: None.` because the host adds this login to the PR's reviewer list, so `request-review --reviewer copilot` makes the host's own request call and no comment phrase is needed.

Enabled by the repository ruleset **Copilot code review** on the default branch, with `review_on_push: false`. That setting, not the brand, is what fixes the trigger. `false` still opens one round when the PR does, and that one only: a push opens none, which is the free first round the `on-request` loop reads under the since rule before it spends a request; every round after it is a request ship issues, so `Cap: 3` is the number of rounds this reviewer actually gets. Flipping `review_on_push` back to `true` makes it `on-push`, and this block must move with it: preflight reads the ruleset and refuses the pair when they disagree.

Under `on-push` the cap is advisory: a ruleset that re-reviews every push keeps posting whatever `Cap:` says, so the number bounds only how long ship waits, and a bound that cannot be enforced is worse than a slower loop that can.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 3
Resolve: resolve-thread
Gating: no
Fallback-for: copilot
Instructions: .github/copilot-instructions.md

Claude Code on GitHub Actions, `.github/workflows/claude-review.yml`, standing in for Copilot on the month its quota runs out. Driven only when `copilot` exits degraded, for any degraded reason; on a run where Copilot converges it reports `not invoked: copilot converged` and costs nothing. The workflow posts its findings as one formal review per round, which is what `poll-pr --reviewer claude --since <iso>` lands, and the action attaches the per-file ones as inline threads on that review, so `Resolve: resolve-thread` the way Copilot's rounds resolve. A finding that names no file stays on the review body and is answered with `comment-pr`, which leaves nothing to resolve. `Login:` is `claude[bot]`: the round is posted by `anthropics/claude-code-action` under the Claude GitHub App the workflow's `claude_code_oauth_token` authenticates, not under the Actions identity. Only the `if: failure()` comment below the action runs on `github.token`, and that comment is not a round, so the login the loop awaits is the app's. A round that dies before posting is `degraded: infra-error`: `poll-pr --reviewer claude` awaits the run this block's `Workflow:` names and reads its failure directly, a plain comment being no round; the workflow's own `if: failure()` comment names the run on the PR, with the failure subtype where the action left one and `unknown` where it did not, so the PR carries the reason, or the link to it in the Actions log. A cancelled job runs no step and leaves nothing on the PR, and the run read is what still names it: `cancelled` is a conclusion the `infra-error` row owns.

## Coding standards

docs/contributing/coding-standards.md

## Verification

### github-mechanics

Proves: a changed generic mechanic or the GitHub adapter performs its host call against a real issue, PR, thread or merge.
Applies when: the change touches `skills/ship/scripts/`, on any path the GitHub adapter reaches.
Run: drive the changed mechanic by hand against a scratch issue on this repo, the way issues #30 and #31 were used, then `manage-issue <n> close` to close the scratch issue after. Where the change reaches the PR body, the run's own PR is the subject and no scratch PR is needed: open it carrying the attribution footer, and after the phase-7 `update-pr-body --section Review` write, `read-pr` reads the body back and confirms the footer is still there. Where the change reaches the body's preamble, the same PR is the subject of an `update-pr-body <pr> --preamble` write, read back the same way, confirming the closing reference survived it. The thread-reply path is driven against a thread the reviewer opened on that same PR; the reviewer opens it and ship does not, so a PR carrying none at convergence leaves that path unexercised. Where an issue asks for a scratch review thread instead, creating and deleting it with `gh api` is verification setup done by hand, the way the scratch issue is, and not a Ship defect: no mechanic creates or deletes a review comment, by design. The verification then takes the result of the paths that did run, and its `<what ran>` note on the merge summary's `Verification` row names the unexercised one for the human to weigh. Where the thread-reply path is the **only** path the change touches, a threadless PR leaves no path to take a result from, and the verification's result is `unexercised`.
Needs: `gh` signed in with push permission on `Gharib89/skills`.
Without it: hand-off
Also proven by CI: None.
Claims to probe: the REST response shapes and api-versions the adapter reads, and whether the call is one GitHub still serves.

### ado-mechanics

Proves: a changed Azure DevOps adapter performs its host call against a real work item, PR, thread or completion.
Applies when: the change touches `skills/ship/scripts/host/ado.sh`.
Run: drive the changed mechanic by hand against the `ship-ado-lab` repo in the `AI_And_Data_Practice` project. A scratch round opened there is dispositioned with `resolve-thread` and left in place: the lab PR is a shared fixture whose resolved rounds accumulate, and no mechanic removes them. A later verification picks its own round out of `all[]` by `submitted_at`, then reads it whole: `poll-pr <pr> --reviewer <name> --since <iso>` reports a round at or after that time as `landed_by: since`, and `poll-pr <pr> --brief --full <id>` lifts the round clip on that row alone.
Needs: `az login` with Entra (the PAT path has known gaps, issue #29) plus the `azure-devops` extension.
Without it: blocked
Also proven by CI: None.
Claims to probe: the api-version each call pins, and the work-item type and closed state the lab's tracker template declares.

## Versioning and changelog

Tooling: semantic-release
Reads: the squash subject's Conventional-Commit type, one configuration per skill under `.release/`; it writes `metadata.version` in that skill's `SKILL.md` and its section of `skills/<name>/CHANGELOG.md`
In-PR requirement: the PR title is a Conventional Commit, of a type the release run reads, whose type is the public-surface grade from [coding-standards.md](../contributing/coding-standards.md), because the squash subject is what the release run reads; a change to what `ship` expects of a profile still bumps `metadata.profile-schema` by hand and adds the matching `## Schema N` entry to `skills/setup-skills/profile-schema.md`
Subject constraints: conventional-commit prefix, scoped to the skill where the change is a skill's, e.g. `fix(ship):`, and to the area otherwise, e.g. `feat(ci):`. The scope is for a human reading the log: `path_filters` in `.release/*.toml` route a commit to a skill by the paths it touched, and `bump-guard` accepts a scopeless subject, so it is the type that decides the bump and the type is graded first

**The release run owns `metadata.version`.** `.github/workflows/semantic-release.yml` writes it on every push to main, once per skill, from the commits that touched that skill's `skills/<name>/`: every conventional type is at least a patch, `feat` is minor, and a `!` or a `BREAKING CHANGE:` footer is major. The `version-lines` gate above refuses a diff that moves the line, so the habit from the old rule is caught before the PR opens rather than by a reviewer. `metadata.profile-schema` is the exception and stays a hand edit, because the `## Schema N` entry it carries is written by the change that needs it.

The title is therefore load-bearing twice: the `bump-guard` leg holds it to a Conventional Commit of a type the release run reads and gates the major grade behind the maintainer's `major` label, and `merge.sh` passes it as the squash `commit_title` so the subject the leg validated is the subject the release run reads. A human merging through the host's own UI instead must land the PR title as that subject.

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
Agent-facing: all of them, plus skills/, .claude/skills/ and docs/contributing/

A diff touching nothing on the `Agent-facing:` line, such as a `.github/` workflow edit, takes no `writing-for-agents` pass.

## Current docs

Sources: context7
Pinned: None.

The skills CLI (`npx skills@latest`) is unpinned and its behaviour is load-bearing: it decides what a derived copy is and what `skills-lock.json` records. Check its `--help` rather than assuming a flag.

## Cloud lane

PR cap: 3
Bootstrap: scripts/cloud-ship-bootstrap.sh

`Bootstrap:` runs in any cloud sandbox, attended or unattended: `prepare` runs it after `tooling --install` at the start of every run there and of any `--unattended` run, local included, so an attended `/ship` from a cloud session gets the same tools a fire does. `PR cap:` is the fire's alone, read only by the unattended lane before it selects.

The sandbox image lacks `shellcheck` and `gitleaks`, and its proxy refuses the `npx -y shellcheck` download. Without this bootstrap every cloud run stops `local gate unavailable: secrets shellcheck`. The script apt-installs whichever of the two is missing, so it is safe to rerun.
