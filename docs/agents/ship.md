# Ship profile

Schema: 5

Every repo-specific fact `/ship` needs, one section per axis. Vocabulary: [GLOSSARY.md](../../GLOSSARY.md).

This repo is both the **source** of the shared skills and a **consumer** of them: `skills/<name>/` is the source of truth and `.claude/skills/<name>/` is the derived copy that actually runs. A change to a skill is not shipped until both carry it.

## Host

Host: github

## Worktree

Carry: None.
Bootstrap: None.

Nothing here is gitignored. The mechanics are bash; the gate needs `gitleaks` on PATH for its `secrets` gate, and the hooks need every tool `scripts/check.sh` runs (`shellcheck`, `actionlint`, `zizmor`, Prettier, `prek`), which the harness cloud setup, `.claude/hooks/cloud-setup.sh`, installs in a cloud session.

## Local gate

Location: scripts/local-gate.sh
Small node: the path of the changed script, e.g. `skills/ship/scripts/merge.sh`; for a `docs`-class change, the path of the changed document, e.g. `skills/ship/SKILL.md`
Tripwires: None.

Two CI legs report on a PR head: `bump-guard` reads the PR title and body rather than the diff, and `check-full` runs `scripts/check.sh full` on the head. The repo is public, so CI minutes cost nothing, and this script runs only what CI cannot or must not: `secrets` over the base range, so a secret is caught before the push, and `version-lines`, which needs the base `check-full` lacks. Every check `full` would report (its `runner`, a `TURN_ROWS` member's `typecheck:` and `tests:` checks, and each `FULL_ROWS` row: `tests`, `derived-copies`, the prose checks, `contract`) is a gate of the same name, `deferred-to-ci` and unrun, its names read from `check.sh`'s configuration block so they cannot drift. Ship's clean gate admits a `deferred-to-ci` gate only while every CI check on the head is green. No `full` check needs this machine. It also prints `scripts/glossary-warn.sh` and `scripts/context-report.sh` (characters in `CLAUDE.md`, `AGENTS.md` and the owned skills' descriptions, no cap) to stderr, which set no gate status. The small lane is the same gate, `secrets` and `version-lines` with the rest deferred, so the recorded node is only what the run records.

Gate notes (the test catalog, `prose-budget`, `version-lines`, `stray-files`, `self-contained`, `contract`, `derived-copies`): [ship-gates.md](ship-gates.md). Read it when a gate fails or a new test or check needs placing; a run needs nothing in it at start.

## CI

Legs: bump-guard: the PR title is a Conventional Commit of a type the release run reads, and a title implying a major bump carries the `major` label; the PR body carries every `##` heading of the PR template; its `## Change outline` holds a `diff` fence or a `Shape: none, mechanical (` line, the first `diff` fence is at most 15 lines, each root line in it carries a file path, and each call node one level under a root is a word of that root's file
Legs: check-full: `scripts/check.sh full` exits 0 on the PR head
No-checks legal: no, neither leg is path-filtered and both report on every PR
Push policy: Default.

Each leg's triggers and what a red run means are in [ship-gates.md](ship-gates.md): a red `check-full` is a failing test or check on the head, fixed on the branch; `bump-guard` adds the rule for a breaking change (titled `feat(<skill>):` while 0.x, the `major` label asked for at the merge gate).

Two workflows are not legs. `.github/workflows/claude-review.yml` is triggered by an issue comment carrying `@claude` and has no `pull_request` trigger, so it lands no check run on a PR head: it is the `claude` reviewer below. `.github/workflows/semantic-release.yml` runs on push to main, after the merge, so no PR ever sees it.

## Reviewers

Self-review cap: 3

### codex

Login: chatgpt-codex-connector[bot]
Trigger: on-request
Request: comment @codex review
Workflow: native codex
Cap: 2
Resolve: resolve-thread
Gating: no
Fallback-for: None.
Instructions: AGENTS.md

Native Codex code review through the ChatGPT Codex Connector GitHub app, on the maintainer's ChatGPT subscription: no API key, no Actions workflow. This repo's primary reviewer, driven on every run and capped at two rounds; `claude` below stands in for it when it exits `not reviewed`, is capped with findings, or stops `not landed`. `request-review --reviewer codex` posts the phrase; Codex answers under `chatgpt-codex-connector[bot]` with 👀 on the request comment (removed when the round ends) and a status comment it edits in place, then posts findings as a `COMMENTED` review with inline threads badged by priority (P1 and P2 observed), or, clean, a `Codex Review: Didn't find any major issues` comment and 👍 on the PR with no review at all. `Workflow: native codex` is what tells `poll-pr --reviewer codex` to read those signals off the PR instead of a run, so a clean round lands as a round and a reply that is neither (a refusal) reads `not reviewed: blocked` with its text. The review rules Codex reads are the `## Code Review Rules` section of the root `AGENTS.md`.

Setup, once, on the maintainer's ChatGPT account: install the ChatGPT Codex Connector app on the repository (the **Connect GitHub** button in the environment picker on chatgpt.com/codex), turn code review on for this repository at chatgpt.com/codex/settings/code-review, and leave automatic review off there, both for the repository and in personal preferences, so a round runs only when requested. A round run through GitHub counts as Code Review usage against the subscription's Codex allowance, shown on the usage dashboard at chatgpt.com/codex/settings/usage. To disable the reviewer, delete this block. Turning code review off in those settings instead leaves ship requesting rounds that nothing answers, each one a window that closes `never-queued` (unprobed).

Observed on the probe PRs #504 and #505 for #500, where the docs say otherwise: P2 findings are posted, not only P0 and P1; a draft PR is reviewed on request; the footer saying reviews start when a PR opens describes automatic review, which is off here. Codex acknowledged a request within 11 s on both, inside the 60 s a comment-transport poll allows for one. A mention of Codex on an issue drew a reply asking for a Codex environment, which is no review.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Resolve: resolve-thread
Gating: no
Fallback-for: codex
Instructions: .github/copilot-instructions.md

Claude Code on GitHub Actions, `.github/workflows/claude-review.yml`, standing in for Codex when its round does not come: the subscription's Codex allowance spent, the connector down, a refusal. Driven only when `codex` exits `not reviewed`, for any reason, or is capped with findings (both rounds spent, the second one's fixes changing the tree), or stops `not landed` (round 1's fixes changed the tree and round 2 did not land), and then for at most two rounds; on any other run where Codex reviews it reports `not invoked: codex reviewed` and costs nothing. The workflow posts its findings as one formal review per round, which is what `poll-pr --reviewer claude --since <iso>` lands, and the action attaches the per-file ones as inline threads on that review, so `Resolve: resolve-thread` the way Codex's rounds resolve. A finding that names no file stays on the review body and is answered with `comment-pr`, which leaves nothing to resolve. `Login:` is `claude[bot]`: the round is posted by `anthropics/claude-code-action` under the Claude GitHub App the workflow's `claude_code_oauth_token` authenticates, not under the Actions identity. Only the `if: failure()` comment below the action runs on `github.token`, and that comment is not a round, so the login the loop awaits is the app's. A round that dies before posting is `not reviewed: infra-error`: `poll-pr --reviewer claude` awaits the run this block's `Workflow:` names and reads its failure directly, a plain comment being no round; the workflow's own `if: failure()` comment names the run on the PR, with the failure subtype where the action left one and `unknown` where it did not, so the PR carries the reason, or the link to it in the Actions log. A cancelled job runs no step and leaves nothing on the PR, and the run read is what still names it: `poll-pr` reports a `cancelled` run as `infra-error`.

## Coding standards

docs/contributing/coding-standards.md

## Verification

### github-mechanics

Proves: a changed generic mechanic or the GitHub adapter performs its host call against a real issue, PR, thread or merge.
Applies when: the change touches `skills/ship/scripts/`, on any path the GitHub adapter reaches.
Run: drive the changed mechanic by hand against a scratch issue on this repo, the way issues #30 and #31 were used, then `manage-issue <n> close` to close the scratch issue after. Where the change reaches the PR body, the run's own PR is the subject and no scratch PR is needed: open it carrying the attribution footer, and after the phase-7 `update-pr-body --section Review` write, `read-pr` reads the body back and confirms the footer is still there. Where the change reaches the body's preamble, the same PR is the subject of an `update-pr-body <pr> --preamble` write, read back the same way, confirming the closing reference survived it. The thread-reply path is driven against a thread the reviewer opened on that same PR; the reviewer opens it and ship does not, so a PR carrying none when the reviewers exit leaves that path unexercised. Where an issue asks for a scratch review thread instead, creating and deleting it with `gh api` is verification setup done by hand, the way the scratch issue is, and not a Ship defect: no mechanic creates or deletes a review comment, by design. The verification then takes the result of the paths that did run, and its what-ran note on the merge summary's `Verification` item names the unexercised one for the human to weigh. Where the thread-reply path is the **only** path the change touches, a threadless PR leaves no path to take a result from, and the verification's result is `unexercised`.
Needs: `gh` signed in with push permission on `Gharib89/skills`.
Without it: hand-off
Also proven by CI: None.
Claims to probe: the REST response shapes and api-versions the adapter reads, and whether the call is one GitHub still serves.

### ado-mechanics

Proves: a changed Azure DevOps adapter performs its host call against a real work item, PR, thread or completion.
Applies when: the change touches `skills/ship/scripts/host/ado.sh`.
Run: drive the changed mechanic by hand against the lab at `https://dev.azure.com/AhmedGharib`, project `AhmedGharib`, repo `AhmedGharib`, from a scratch checkout whose origin is that repo, carrying a scratch profile whose reviewer blocks name the maintainer's own Azure DevOps identity. The fixture is an active PR there (PR 1 today) reviewed by that identity. A scratch round opened on that PR is dispositioned with `resolve-thread` and left in place: the lab PR is a shared fixture whose resolved rounds accumulate, and no mechanic removes them. A later verification picks its own round out of `all[]` by `submitted_at`, then reads it whole: `poll-pr <pr> --reviewer <name> --since <iso>` reports a round at or after that time as `landed_by: since`, and `poll-pr <pr> --brief --full <id>` lifts the round clip on that row alone.
Needs: `az login` with Entra (the PAT path has known gaps, issue #29) plus the `azure-devops` extension.
Without it: blocked
Also proven by CI: None.
Claims to probe: the api-version each call pins, and the work-item type and closed state the lab's tracker template declares.

### herdr-live

Proves: drive-session's scripts read a real Herdr's states and sequence numbers the way the fake in `tests/herdr-fake.sh` assumes.
Applies when: the change touches `skills/drive-session/scripts/`.
Run: from a session inside Herdr, `spawn` two sessions on a cheap model (`--model haiku`) into one scratch roster, `--cwd` a folder Claude Code trusts: one prompted to ask a question with the AskUserQuestion tool, which must reach `blocked`, and one given a short task, which must reach `done`. Confirm `watch` reports each once, never on the previous turn's `done`, and moves on after `read`; answer the dialog with `answer <name> --roster <file> --keys`, confirm the next `watch` reports that session's new turn, and once the short task is `done`, send it `answer --text /rename <x>` and confirm it exits 1 with `code` `agent_prompt_stalled`, then close the two tabs with `herdr tab close`.
Needs: `HERDR_ENV=1`, herdr 0.9.3 or newer, and `claude` on PATH.
Without it: hand-off
Also proven by CI: None.
Claims to probe: that a permission dialog, not only a question dialog, reads `blocked` (it did on herdr 0.9.3, with `--permission-mode default`); that `agent get` on a closed tab's agent, or one whose claude exited with its pane open, answers `agent_not_found`; that a blocked agent's `visible` screen shows the dialog where a 120-line `recent-unwrapped` read is refused with `agent_not_idle`; that `agent prompt --wait` answers `agent_prompt_stalled` after 5 s for text that starts no turn, from `done`; and that focusing a tab turns `done` into `idle` without moving `state_change_seq` (all measured on herdr 0.9.3), so a glance at a tab wakes no `watch`.

### ship-live-run

Proves: Ship's prose, as a real model reads it, takes a plain issue to the merge gate and stops `ambiguous` on a vague one with no claim, no branch and no PR.
Applies when: the change touches `skills/ship/SKILL.md` or `skills/ship/reference/`.
Run: `git -C <worktree> worktree add --detach <scratch>/verify/live-run-judge origin/HEAD`, then `<scratch>/verify/live-run-judge/scripts/live-run-ship.sh <worktree>`, then `git -C <worktree> worktree remove <scratch>/verify/live-run-judge` whatever the driver exits: the driver and its checks come from the default branch, in an attended worktree and an unattended clone alike, so a change under test cannot change its own judge. The `result` field of its JSON line is the result word; a failed `worktree add`, or a `result` of `unavailable`, is a `Needs:` failure, so take `Without it:`. Non-empty `retried` lines go in the `Verification` item's what-ran note.
Needs: `gh` and `claude` signed in, and `Gharib89/ship-fixture` reachable with its `main` at its `seed` tag.
Without it: hand-off
Also proven by CI: None.
Claims to probe: that `claude -p` reports a hit `--max-budget-usd` cap as a nonzero exit with `subtype` `error_max_budget_usd` (it did on 2026-10-12).
Paths: skills/ship/SKILL.md, skills/ship/reference/**

### real-render

Proves: the explainer-video composer's frame grid holds under real HyperFrames: the render's frame count equals the composer's, two renders match frame for frame, and two stream-copy-joined halves have the whole's frame count.
Applies when: the change touches a file in `Paths:`.
Run: first, a slice adding scenes extends the fixture in `maintainer/real-render.mjs`; then `node skills/explainer-video/maintainer/real-render.mjs` after `node skills/explainer-video/scripts/setup.mjs install` has installed the worktree's lock (a new pin is a new cache). Outside `tests/run.sh` (it needs real Chrome). Exit 0 is `pass`, 1 `fail`, 2 a missing tool row.
Needs: the `npm-packages` and `chrome` rows installed, and `ffmpeg`.
Without it: hand-off
Also proven by CI: None.
Claims to probe: that HyperFrames renders `ceil(duration * fps)` frames and has no frame-range flag (both held on 0.8.169, 2026-10-19).
Paths: skills/explainer-video/scripts/render/**, skills/explainer-video/scripts/gates/**, skills/explainer-video/scripts/lib/**, skills/explainer-video/maintainer/**, skills/explainer-video/package*.json

## Versioning and changelog

Tooling: semantic-release
Reads: the squash subject's Conventional-Commit type, one configuration per skill under `.release/`; it writes `metadata.version` in that skill's `SKILL.md` and its section of `skills/<name>/CHANGELOG.md`
In-PR requirement: the PR title is a Conventional Commit, of a type the release run reads, whose type is the public-surface grade from [release.md](../contributing/standards/release.md), because the squash subject is what the release run reads; a change to what `ship` expects of a profile still bumps `metadata.profile-schema` by hand and adds the matching `## Schema N` entry to `skills/setup-skills/profile-schema.md`
Subject constraints: conventional-commit prefix, scoped to the skill where the change is a skill's, e.g. `fix(ship):`, and to the area otherwise, e.g. `feat(ci):`. The scope is for a human reading the log: `path_filters` in `.release/*.toml` route a commit to a skill by the paths it touched, and `bump-guard` accepts a scopeless subject, so it is the type that decides the bump and the type is graded first

Why the release run owns the version line and the title is load-bearing: [ship-versioning.md](ship-versioning.md). Read it for a title or version question; a run needs nothing in it at start.

## PR

Template: .github/pull_request_template.md
Body-check: scripts/check-pr-body.sh
Merge: on-clean-gate

## Public surface

Everything a consumer repo depends on, all of it under `skills/`:

- each skill's name, `description` and `argument-hint`, which decide when an agent reaches it
- `ship`'s flags and its stop-reason vocabulary
- every generic mechanic's CLI signature and the shape of the JSON it prints
- the local-gate contract: the flags, the gate statuses, the verdict
- the ship profile's fourteen headings, their `Label:` lines, and the schema number
- the `### Ship` CLAUDE.md block `setup-skills` writes
- the `setup-skills` templates, which land verbatim in consumer repos
- each skill's `retired-terms.md` table (version, term, replacement or `None.`), which `update-skills`' plan reads
- `ship`'s `metadata.composes` line: the set of skills a consumer must have installed, each at its pinned ref, for a run to pass preflight

## Triage

File as an issue labelled `needs-triage`.

This repo is Ship's own source, so a run here is already in the source repo and a **Ship defect** met during the run is an adjacent find: it takes phase 2's dispositions, through `file-issue` and its candidate check, and is still named on the merge summary's `Ship defects` item. It takes no source-repo draft under ADR 0004, because the repo the run is in is the source repo.

## Docs sync

Targets: GLOSSARY.md, docs/adr/, docs/agents/, skills/setup-skills/profile-schema.md, .out-of-scope/
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

The sandbox image lacks `gitleaks`, and its proxy refuses a release-asset download. Without this bootstrap every cloud run stops `local gate unavailable: secrets`. The script runs the harness profile's `Setup:` (`.claude/hooks/cloud-setup.sh`, idempotent) and then apt-installs a missing `gitleaks`, so it is safe to rerun. It is a no-op outside a cloud session, so a local `--unattended` run needs `gitleaks` on PATH already. The `SessionStart` command in `.claude/settings.json` runs it silently, then calls `cloud-setup.sh` again, a fast no-op, to print `harness cloud setup: ok`.
