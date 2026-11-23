# Ship skill audit

**Fix profile-controlled merge authorization first, then worktree pruning and cleanup.** Reviewed Ship 0.69.2, profile schema 5, at `1f8dedf96f95f5155f389c04e70d7064dde0e9e6` on 2026-11-23. The peer reviewer checked the three real consumer repos. All use GitHub and set `Merge: on-clean-gate`. Azure DevOps installations are test labs. The [best-practices benchmark](ship-best-practices-2026-11-23.md) records the research criteria and primary sources.

The fixes are specified in #1337 and ticketed as its sub-issues #1338 to #1346, one per slice in the order of [Proposed tickets](#proposed-tickets). This document keeps what the tickets leave out: the evidence behind each severity, the lab-only findings and the deferred design options.

P1 covers exposed merge authorization or data-loss defects. P2 covers narrower correctness defects. P3 is backlog. Measured results below identify the fixture or scan. Inferences follow from the code or stated deployment configuration.

## Ranked findings

### 1. P1 · A profile change can authorize its own merge

**Measured.** The policy probe held on `reviewer Primary: missing stop` with the base profile. A feature profile removed the reviewer and yielded clean admission and a fake-host merge call with the same CI evidence. The dirty-profile probe also changed the gate from held to clean with zero committed profile changes. [Attended policy](../../skills/ship/reference/merge-gate.md#L140-L166) · [Clean gate](../../skills/ship/scripts/lib/run-file-clean-gate.sh#L26-L46) · [Final admission](../../skills/ship/scripts/merge.sh#L130-L156)

**Inferred.** All three real consumer repos can take the clean-gate path. The final mechanic reads the main checkout's policy for sandbox permission and CI legs, while the clean evaluator grades reviewers and Verifications from the feature checkout.

**Fix.** Require a human merge when the approved commit changes `docs/agents/ship.md` against the freshly resolved actual PR base. Grade the approved commit's profile bytes, or hold if the checkout copy differs. Hold on unreadable comparisons. Use the existing admission record. The Git comparison probe found a working-tree-only diff misses a committed change that is locally reverted, and an untracked first profile. Cover both cases, a changed reviewer block, and an ordinary clean admission in the regression tests.

### 2. P1 · Preflight can delete uncommitted work

**Measured.** The prune probe supplied a merged PR at the worktree's head. Preflight refused admission, reported the unrelated worktree as pruned and deleted its untracked draft. A locked-worktree variant reported pruning while the directory survived. A separate Git 2.53.0 fixture showed plain `git worktree remove` silently removed a directory with an ignored draft. The peer found a T3 worktree outside the scanned container in a consumer checkout and no `pruned` reader in Ship's instructions. [Preflight prune](../../skills/ship/scripts/preflight.sh#L234-L253) · [Existing tests](../../tests/preflight-prune.test.sh#L42-L64)

**Inferred.** The scan misses T3 worktrees outside `.claude/worktrees/`. Narrowing the scan to truly empty worktrees also limits its usefulness in checkouts with ignored dependencies. The prune violates **A delete keyed on a probe treats an unknown answer as keep**.

**Fix.** Recommend removing the automatic prune from preflight. The owner can instead keep it for an exact merged PR head and a status known clean including ignored files. Use plain removal, preserve the worktree on an unreadable check, and report only successful removals. Test normal, ignored and untracked changes, failed removal, and preflight refusal.

### 3. P1 · Free-text cleanup can remove another run's worktree

**Measured.** With two scratch worktrees ending in `-none`, the cleanup probe returned success after deleting the wrong worktree and its untracked draft. The adoption probe called `isolate none fix user-slug` from a host-launched checkout. It returned the actual branch `fix/host-slug-none`. [Cleanup selection](../../skills/ship/scripts/cleanup.sh#L50-L81) · [Worktree adoption](../../skills/ship/scripts/isolate.sh#L76-L116)

**Inferred.** Preflight and isolate check for existing suffix matches inside the local container. Adopted worktrees can sit outside it. A slug reconstructed at cleanup need not match the branch adopted earlier.

**Fix.** Require `cleanup none --branch <head_ref>` with the exact PR branch already read at merge. Refuse an ambiguous tracked-issue match before removing a worktree or branch. Exercise two adopted free-text worktrees through phase 9, and two tracked-issue candidates.

### 4. P2 · Merge freshness can inspect the wrong head and target

**Measured.** The merge probe had an unpushed checkout commit caught up with the target and a published PR head one commit behind. Merge called the Host fake on the behind head. A separate probe made origin temporarily unavailable and got `fresh:true,fetched:false`. Restoring it showed the same checkout was one commit behind. [Merge freshness call](../../skills/ship/scripts/merge.sh#L109-L129) · [Base comparison](../../skills/ship/scripts/base-fresh.sh#L28-L38)

**Inferred.** The expected SHA binds the host mutation to the published source head. The base check still compares local HEAD to `origin/HEAD` and accepts a cached comparison. That can admit a stale-base squash under host policy that permits it.

**Fix.** At merge time, compare the gated SHA with the PR's actual target after fetching it successfully. Refuse on a failed fetch. Test a locally advanced checkout, a non-default target and a failed fetch.

### 5. P2 · GitHub CI can lose check evidence

**Measured.** The GitHub adapter probe returned one green `build` after reading a red check run and a newer green commit status of the same name. A separate Host fake passed a named check row without a status to `ci-wait`, which returned green. Neither a name collision nor more than 30 status contexts was measured in a real consumer repo. [GitHub checks adapter](../../skills/ship/scripts/host/github.d/prs.sh#L74-L94) · [CI grader](../../skills/ship/scripts/ci-wait.sh#L106-L118)

**Inferred from source and API.** The combined-status call reads only the first page, with a default of 30 contexts. GitHub requires both a check run and a commit status to pass when they share a required name. [Combined-status API](https://docs.github.com/en/rest/commits/statuses#get-the-combined-status-for-a-specific-reference) · [Required status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)

**Fix.** Keep check runs and commit statuses distinct through grading and paginate the combined endpoint. Validate the normalized result and status vocabulary at the polling boundary. Test a name collision, a required context on page two and a partial row.

### 6. P2 · Claim and hand-back have a race window

**Measured.** The claim probe released two simultaneous empty reads to two `take --fresh` calls sharing an identity. Both returned `claim:taken` and posted the claim comment. The peer's REST scan of the newest 1,500 issue comments in one repo found 201 Ship claim comments on 200 issues from 2026-10-18 to 2026-11-19, with zero pairs on one issue within 120 seconds. No real-run double claim was observed in that scan. [Take and hand-back](../../skills/ship/scripts/manage-issue.sh#L63-L124)

**Inferred.** The hand-back currently releases the assignment while `ready-for-agent` still makes the issue eligible. A duplicate claim can waste work. No duplicate merge was observed.

**Fix.** Remove and verify the agent-ready label before releasing the assignment. Keep the assignment if the removal is unconfirmed. Test the order and failed label removal. Defer a claim tie-break until there is consumer evidence.

### 7. P2 · The gate evaluator accepts missing CI or criteria evidence

**Measured.** The deferral probe returned clean with `Legs: None.`, `No-checks legal: yes`, zero check rows and a deferred local test. The criteria probe used one issue criterion and no Criteria section in the Run file. `gate summary` held while `gate admit clean` wrote a clean admission. The peer confirmed the real consumer using that no-checks configuration runs every check locally. [Deferral evaluator](../../skills/ship/scripts/lib/run-file-clean-gate.sh#L165-L181) · [Criteria summary](../../skills/ship/scripts/lib/run-file-gate-summary.sh#L24-L36) · [Admission writer](../../skills/ship/scripts/lib/run-file-verbs-gate.sh#L32-L49)

**Inferred.** The no-checks case matters in that consumer only if its local gate emits a deferral. The usual attended summary catches the missing-criteria case. Direct admission can miss it.

**Fix.** Add the zero-CI-evidence hold for a deferral. Move the existing tracked-issue criteria check into the evaluator used by clean, summary and admission. Test all three entrypoints against the same state and keep legal no-checks green when every check ran locally.

### 8. P3 · Reviewer settings and wait caps accept invalid bounds

**Measured.** A reviewer-profile fixture accepted cyclic fallbacks, a negative cap and a mistyped `Gating:`. The wait-cap probe used a two-second fake host read with a one-second cap. It exceeded the cap and returned green. [Reviewer validation](../../skills/ship/scripts/lib/poll.sh#L146-L197) · [CI timeout](../../skills/ship/scripts/ci-wait.sh#L126-L147)

**Fix.** Validate reviewer fields and cap host subprocesses while preserving cursor deadlines. Keep this in backlog.

## Lab-only findings, P3

Record these Azure DevOps findings for the labs. The lab-only rule excludes compatibility work and rollout tickets.

- **Measured, Azure CI probe.** A status from an older iteration appeared green under the current head. A failed status read became legal no-checks. [Azure checks adapter](../../skills/ship/scripts/host/ado.d/prs.sh#L37-L52) · [Iteration statuses API](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-iteration-statuses/list?view=azure-devops-rest-7.1)
- **Measured, Azure review probe.** An old PR-level thread appeared under `on_head` after iteration lookup failed. [Azure review adapter](../../skills/ship/scripts/host/ado.d/prs.sh#L89-L105)
- **Measured, Azure merge payload probe.** The PATCH requests source-branch deletion and work item transitions. **Inferred from the completion contract.** Those effects can run before Ship's leased deletion and apply to linked items even on a free-text run. [Azure merge payload](../../skills/ship/scripts/host/ado.d/threads-and-lists.sh#L65-L75) · [Completion options](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/update?view=azure-devops-rest-7.1#gitpullrequestcompletionoptions)

## What can be removed

| Item | Proposed change and evidence |
| --- | --- |
| Inner `gating` case | Remove the unreachable branch. **Source trace.** The sole call to `norm` is outside the outer branch that handles `gating`. Preserve the boolean result. [Parser](../../skills/ship/scripts/lib/poll.sh#L87-L100) |
| Duplicate reviewer parser assertions | Keep them in the rows suite. **Measured.** The files share a 160-line prefix. Omitting the 92-line assertion block from the refusal suite leaves 17 unique coverage-equivalent duplicates removed, and both suites pass. Keep the fixture needed by the refusal cases. [Rows suite](../../tests/reviewer-blocks-rows.test.sh#L3-L162) · [Refusal suite](../../tests/reviewer-blocks.test.sh#L69-L160) |
| Identical PR body rewrite | Skip the write when the validated body exactly equals the current body. **Measured.** The Host fake received an identical write. The change saves one host write per match. The GitHub CI effect is unmeasured. Keep read-back for changed bodies. [Body update](../../skills/ship/scripts/update-pr-body.sh#L103-L121) |

The derived copy, retired-term migration data, exact supervisor wait line, `codebase-design` pin, and `Gating:` still have readers. `nothing-ready` distinguishes a healthy empty queue from unavailable input. [Distribution](../glossary/distribution-and-refresh.md) · [Retired terms](../../skills/ship/retired-terms.md) · [Supervisor waits](../../skills/super-agent/reference/watching.md) · [TDD composition](../../.claude/skills/tdd/SKILL.md#L26) · [Reviewer override](../../skills/ship/reference/review-loop.md#L236-L240) · [Unattended selection](../../skills/ship/reference/unattended.md#L31-L49)

## Proposed tickets

Use one spec parent outside the agent queue and one PR per slice. Start each bug fix with a regression that fails at the audited revision.

| Slice | Scope |
| --- | --- |
| 1 | Hold clean merge on a changed Ship profile and verify the profile bytes being graded. |
| 2 | Remove automatic preflight pruning, or make it non-forcing and safe for ignored files if the owner keeps it. |
| 3 | Bind free-text cleanup to the exact PR branch and refuse ambiguous tracked cleanup. |
| 4 | Use one gate evaluator for the no-CI deferral hold and missing tracked criteria. |
| 5 | Compare the gated SHA against the freshly fetched actual PR target at merge. |
| 6 | Preserve GitHub CI source identity, paginate statuses and validate polling input. |
| 7 | Remove the agent-ready label before releasing a claim. Defer the claim tie-break. |
| 8 | Remove the unreachable gating branch, duplicate assertions and identical-body write. |
| 9 | Validate reviewer fields and wait caps. P3 backlog. |

The owner chose removal for slice 2, since the scan cannot see worktrees outside the container and a version safe for ignored files would rarely fire. Slice 8 was eligible for an inline fix and the owner chose a ticket. [Inline lane](../../skills/ship/reference/small-lane.md#the-inline-lane)

**Deferred design options.** Keep host-backed round provenance, a common attended and unattended gate report with workflow-attempt freshness, and separate outcomes for merge and cleanup as design options for the owner. Preserve the existing Run file, cursors, Local gate and expected-head merge payloads. [Round evidence](../../skills/ship/reference/review-loop.md#L203-L224) · [Unattended return](../../skills/ship/reference/unattended.md#L56-L73) · [Merge sequence](../../skills/ship/scripts/merge.sh#L157-L229) · [Downstream-reader ADR](../adr/0011-ship-rules-guard-what-is-read-downstream.md)

**Separate prose-budget spec.** The entrypoint is 262 lines and 2,330 whitespace-delimited words. The always-read set is exactly at 16,000 words. Test moving detailed rules behind phase and lane pointers with paired live runs. Compare token use, tool calls and gate outcomes. Use a separate paired pilot before removing the `show-me` dependency or consolidating model-tier and unattended preparation instructions. [Prose budget](../../scripts/prose-budget-check.sh#L162-L181) · [Outline instructions](../../skills/ship/reference/pr-body.md#L69-L95) · [Agent Skills specification](https://agentskills.io/specification#progressive-disclosure)

## Evidence and verification

The fixture measurements come from 21 offline probe scripts, kept in [`ship-audit-2026-11-23-probes/`](ship-audit-2026-11-23-probes/). Run one from the repo root at `1f8dedf9` with `bash docs/research/ship-audit-2026-11-23-probes/<name>.sh`. Each builds scratch Git repos under a temporary directory and reaches no host.

| Finding | Probes |
| --- | --- |
| 1 | `policy`, `dirty-profile`, `profile-compare` |
| 2 | `prune`, `prune-locked`, `worktree-ignored` |
| 3 | `cleanup`, `isolate-adopt` |
| 4 | `merge`, `base-fresh-offline` |
| 5 | `gh`, `ci-wait-partial-row` |
| 6 | `claim` |
| 7 | `deferral`, `criteria` |
| 8 | `reviewer-fields`, `wait-cap` |
| Azure DevOps list | `ado`, `ado-review`, `ado-merge` |
| Identical PR body rewrite | `noop-body` |

Three measurements have no script, because each read live data once: the scan of 1,500 issue comments for claim pairs, the consumer checkout's worktree listing, and the line comparison of the two reviewer parser suites. Each ticket's regression test reproduces its probe's result before changing the mechanic.

All 14 focused Ship test files passed, as did the prose budget, derived-copy comparison and document edit checks. The full suite passed 245 of 254 files initially. Seven of the nine failures passed on retry with a writable pre-commit cache. In the two video suites, follow-up probes reproduced sandbox `EPERM` on nested Node launches, including launching `brief.mjs` in the explainer malformed-input test. No failure on main was established outside the sandbox. The Ship probes used local scratch Git repos, the Host fake and stubbed host transport.
