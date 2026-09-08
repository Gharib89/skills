---
name: setup-skills
description: "Configure this repo for the Gharib89/skills engineering skills: draft its ship profile, local gate, PR template, coding-standards doc and reviewer scaffolding, and check the host tooling. Run once after /setup-matt-pocock-skills, before the first /ship."
disable-model-invocation: true
---

# Setup skills

Draft the per-repo documents the `ship` skill reads, confirming with the human before every write. Same shape as `setup-matt-pocock-skills`: explore once, present, walk what exploration could not settle, confirm the full draft, write, prove. This skill does only what that parent leaves undone and ship needs; it never re-asks anything the parent settled (tracker, triage vocabulary, domain-doc layout).

Vocabulary: [CONTEXT.md](https://github.com/Gharib89/skills/blob/main/CONTEXT.md) of the source repo (ship profile, axis, local gate, verdict, reviewer, trigger, derived copy). Every document you write here is read by an agent: apply `writing-for-agents` to its prose.

## Process

### 1. Preconditions: instruct and stop

Check all three before exploring. On any failure print the exact command, then "then rerun `/setup-skills`", and stop.

1. **Parent docs.** `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` and `docs/agents/domain.md` exist. Else: `/setup-matt-pocock-skills`. One exception: when the host (step 2) is Azure DevOps and `issue-tracker.md` is missing or is the parent's freeform "Other" page, offer to write the vendored [issue-tracker-ado.md](./issue-tracker-ado.md) in its place (confirm first), then continue. The parent ships GitHub, GitLab and local templates only.
2. **Composed skills as derived copies.** `.claude/skills/` holds `code-review`, `tdd`, `writing-for-agents`, `triage` and `find-docs`, each recorded in the repo's `skills-lock.json` (the skills CLI writes it at install). A copy present but absent from the lock is hand-maintained: report it as "will be replaced by the derived copy", confirm, then refresh it with the same line. A global copy under `~/.claude/skills` never counts: a personal skill silently shadows a repo's, so ship's composed skills must live in the repo. Else print:

   ```sh
   npx skills add mattpocock/skills --skill code-review --skill tdd --skill writing-for-agents --skill triage --agent claude-code -y
   npx skills add upstash/context7 --skill find-docs --agent claude-code -y
   ```

3. **`ship` and `cloud-ship`.** `.claude/skills/ship` and `.claude/skills/cloud-ship` exist and are in the lock. A `ship` folder with no `metadata.version` in its frontmatter is a hand-maintained copy from before the generic skill: report "will be replaced by the derived copy", confirm, refresh. Else print:

   ```sh
   npx skills add Gharib89/skills --skill ship --skill cloud-ship --agent claude-code -y
   ```

   Project scope always, never `-g`. The agent id is `claude-code`; the CLI rejects `'Claude Code'`.

### 2. Host

From `git remote get-url origin`: `github.com` is `github`; `dev.azure.com` or `visualstudio.com` is `ado`; anything else stops as out of scope. Cross-check against `docs/agents/issue-tracker.md`'s title line; a mismatch stops and names both.

Then prove the host tooling with ship's own preflight, the one host check that exists:

```sh
.claude/skills/ship/scripts/preflight.sh <any open issue number>
```

Exit 2 with a `host-unreachable` reason (CLI missing, extension missing, not signed in, no push permission) stops here with that reason: setup is the one moment a human is present to fix auth. Exit 1 with `profile missing` is the expected answer at this point; continue.

Preflight cannot prove the git remote itself, so also run `git ls-remote --heads origin`. A failure here surfaces later only as `existing branch: remote unreadable`, and every push in a run would fail. On Azure DevOps with an Entra `az login` and no PAT, offer the repo-local credential helper from the tracker doc's Auth line, which mints the git password from the same token.

### 3. Explore

Read the repo once, every section, before saying anything. The right-hand column says whether exploration settles the section or the walk (step 4) must.

| Section | Read | Settled by exploration? |
|---|---|---|
| Host | step 2 | yes |
| Worktree | `Carry:` from `git status --ignored --short`, kept to small dotfiles (`.env*`, `*.local`); `Bootstrap:` `None.` unless a setup script exists that the local gate cannot own | yes, confirm the list |
| Local gate | `scripts/local-gate.sh`, else `.claude/skills/ship/scripts/local-gate.sh`, else `scripts/ship/local-gate.sh`; the lockfile fixes the runner (`package-lock.json` npm, `pnpm-lock.yaml` pnpm, `uv.lock` `uv run pytest`, `pyproject.toml` alone `pytest`); `Small node:` syntax follows the runner | location yes; node syntax walked |
| CI | `Legs:` every job of every workflow with a `pull_request` trigger (`.github/workflows/*.yml`; on ADO the pipelines named by build-validation policies); other workflows named in prose as non-PR; `No-checks legal: yes` iff any PR workflow carries a `paths:` filter; `Push policy:` | legs yes; push policy walked |
| Reviewers | `.coderabbit.yaml` (on-push); `.github/copilot-instructions.md` plus a Copilot automatic-review ruleset from `gh api repos/{owner}/{repo}/rulesets` (auto-once); `review_requested` events on the last ten merged PRs (on-request); `claude-code-action` in a workflow or a Claude review pipeline (on-push). Propose each with the trigger the evidence implies, always confirmed; `Cap:` always asked, never defaulted | walked |
| Coding standards | a path CLAUDE.md names, `CODING_STANDARDS.md`, `CONTRIBUTING.md`, `docs/contributing/*` | yes, or stub |
| Verification | not discoverable; seed from test markers (`e2e`, `integration`), Docker use, browser-test scripts | walked |
| Versioning and changelog | semantic-release config, changesets, `version-gate` or bump scripts, `CHANGELOG.md`; `In-PR requirement:` | walked |
| PR | `.github/pull_request_template.md` or `.azuredevops/pull_request_template.md`: presence and headings | yes |
| Public surface | `Default.` proposed | walked |
| Triage | the `needs-triage` row's right-hand column in `triage-labels.md`, never invented | yes |
| Docs sync | `README.md`, `docs/`, `CONTEXT.md`, skills the repo ships; `Agent-facing:` `docs/agents/`, `.claude/skills/` | yes, confirm |
| Current docs | context7 always; Microsoft Learn when a Microsoft stack shows (D365, Azure, Power BI, .NET); `Pinned:` | walked |
| Cloud lane | `PR cap: 3`; `Bootstrap:` the path of `scripts/cloud-ship-bootstrap.sh` when it exists, else `None.` | yes |

Also record, for step 5: the per-repo ship scripts the generic mechanics supersede (`claim`, `isolate`, `preflight`, `poll-pr`, `ci-wait`, `merge-and-verify`, `merge`, `reflect`, `release`, `_lib` under `.claude/skills/ship/scripts/` or `scripts/ship/`), and whether the triage labels exist on the host (`gh label list`; on ADO tags exist once used, so nothing to check).

### 4. Present, then walk

Present the whole exploration once: what each section will read, one line each. Then walk **only the walked rows**, one section, one answer, each led by the recommended answer so the user can accept in a word. A one-line explainer only where the choice genuinely branches. Sections exploration settled are shown, never asked.

Walk order and the recommendation to lead with:

- **Local gate, small node**: the runner's own node syntax with one example from the repo's tests.
- **CI, push policy**: `one push per review round` on metered minutes (private repos, ADO parallel jobs); `Default.` otherwise.
- **Reviewers**: each detected reviewer with its inferred trigger; then "any reviewer not detected?", offering Claude Code as a reviewer (see step 5, scaffolding). For every on-request reviewer ask the cap; recommend 2.
- **Verification**: one block per seed, or `None.` when nothing in the repo talks to a real system.
- **Versioning**: what exploration found, then `In-PR requirement:`, the one line that changes what ship does.
- **Public surface**: `Default.` unless the repo publishes more than an API (gate rules, palettes, bundle inputs).
- **Current docs, pinned**: the libraries whose major version the repo's manifest pins and whose API moved recently.

### 5. Confirm and edit

Show the full draft of everything below, then let the user edit before writing. Field-level validation happens here, where a human can fix it: every on-request reviewer has a `Cap:`; every `Also proven by CI:` names a leg defined in `## CI`; `defer-to-ci` appears only with such a leg; `Host:` matches step 2; fourteen headings in order.

**`docs/agents/ship.md`** from [ship-profile.md](./ship-profile.md): all fourteen headings, `None.` or `Default.` where an axis is defaulted, template comments removed.

**The `### Ship` sub-block**, inside the existing `## Agent skills` block of whichever of `CLAUDE.md` / `AGENTS.md` the parent chose (the file that has the block). Updated in place when present, never duplicated:

```markdown
### Ship

`/ship` drives one issue to a merge-ready PR. This repo's ship profile: `docs/agents/ship.md`. Without that file ship refuses: run `/setup-skills`.

Every skill under `.claude/skills/` is a derived copy, never edited in place; `skills-lock.json` records each one's source. `ship` and `cloud-ship` come from `Gharib89/skills`; the skills ship composes come from `mattpocock/skills` and `upstash/context7`. Refresh a skill by re-running its install line at project scope (never `-g`), e.g. `npx skills add Gharib89/skills --skill ship --skill cloud-ship --agent claude-code -y`.
```

**Local gate.**

- Absent: write `scripts/local-gate.sh` from [local-gate.sh](./local-gate.sh), one gate per CI leg named as the leg is named in `## CI`, run locally where the runner is obvious and `deferred-to-ci` where it is not; `secrets` wired to a detected scanner (`gitleaks`, `ggshield`, `detect-secrets`, `trufflehog`), else left `unavailable` with a comment naming what to add. That is honest: the first attended run stops and names exactly what is missing.
- Present and conforming (JSON verdict with `verdict`, `gates`, a `secrets` gate, `--small` and `--base` flags): keep it; `Location:` records where it is.
- Present but non-conforming (prints text, positional `--small`, no `unavailable` status): propose a rewrite to the contract that keeps every check the old gate ran, show the diff, write on confirm. `Location:` moves to `scripts/local-gate.sh` only if the human agrees.

Either way, **run it once** (`--small` with the example node) and check the verdict shape: a JSON object with `verdict`, `base`, `lane`, `gates.secrets`.

**PR template.** None: create it from [pull_request_template.md](./pull_request_template.md) at `.github/pull_request_template.md` (GitHub) or `.azuredevops/pull_request_template.md` (ADO). Exists: propose adding the `## Review` section only.

**Coding standards.** None found: write `docs/contributing/coding-standards.md` from [coding-standards.md](./coding-standards.md), recording only what exists and is enforced today (config-enforced tools, links to CLAUDE.md sections carrying inline standards). Never move CLAUDE.md prose into it.

**Triage labels on the host** (GitHub only). Any of the five labels from `triage-labels.md` missing on the repo: create them, because ship's hand-back exits 1 without `ready-for-human`.

**Reviewer scaffolding**, for each reviewer the user named that is not installed: write the files the host needs and hand the human an inline checklist of the steps only they can do (secrets, app installs, branch policies). Claude Code as reviewer: [reviewers/github-claude-review.md](./reviewers/github-claude-review.md) or [reviewers/ado-claude-review.md](./reviewers/ado-claude-review.md). Point the reviewer's instructions at the coding-standards path, never at a copy of it. Other bots (CodeRabbit, Copilot) are configured in their own UIs; the checklist names the setting.

**Superseded ship scripts** (migrating repos): list what step 3 recorded, propose deletion, delete on confirm. Never touch `local-gate.sh`, `live-e2e`, `copilot-pr-review-loop`, or `cloud-ship-bootstrap.sh` (that one is now `## Cloud lane`'s `Bootstrap:`).

### 6. Write, then prove

Write every confirmed file. Then run ship's preflight against the new profile:

```sh
.claude/skills/ship/scripts/preflight.sh <any open issue number>
```

Report its `reasons`. Only issue-level reasons may remain (`not triaged`, `already claimed`, `existing PR`, and the like); any `profile missing` or `profile invalid` reason is yours to fix before finishing.

### 7. Done

Tell the user: the profile is at `docs/agents/ship.md`, the first `/ship <issue>` can run, `cloud-ship` is installed and how a cloud routine fires it (`ship --unattended` with no issue selects its own). The routine itself is one operator's schedule and not written here. They can edit `docs/agents/ship.md` directly later.

## Re-run

Profile exists: run steps 1 to 3, then diff each section of the fresh exploration against the existing profile, propose only the updates, and ask whether anything else should change. Prose under the headings is the human's; update the `Label:` lines and leave the prose alone unless a fact it explains changed. End with step 6.
