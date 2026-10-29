# Ship profile: reviewer notes

Setup and probe evidence for the reviewers in the ship profile's `## Reviewers`, and how each one's round reads. The profile ([ship.md](ship.md)) keeps the lines a run reads; this file is for a run reading a reviewer's round, or a maintainer setting one up or checking what it was seen to do.

## codex

`request-review --reviewer codex` posts the phrase; Codex answers under `chatgpt-codex-connector[bot]` with 👀 on the request comment (removed when the round ends) and a status comment it edits in place, then posts findings as a `COMMENTED` review with inline threads badged by priority (P1 and P2 observed), or, clean, a `Codex Review: Didn't find any major issues` comment and 👍 on the PR with no review at all. `Workflow: native codex` is what tells `poll-pr --reviewer codex` to read those signals off the PR instead of a run, so a clean round lands as a round and a reply that is neither (a refusal) reads `not reviewed: blocked` with its text.

Setup, once, on the maintainer's ChatGPT account: install the ChatGPT Codex Connector app on the repository (the **Connect GitHub** button in the environment picker on chatgpt.com/codex), turn code review on for this repository at chatgpt.com/codex/settings/code-review, and leave automatic review off there, both for the repository and in personal preferences, so a round runs only when requested. A round run through GitHub counts as Code Review usage against the subscription's Codex allowance, shown on the usage dashboard at chatgpt.com/codex/settings/usage. To disable the reviewer, delete its `### codex` block in the profile. Turning code review off in those settings instead leaves ship requesting rounds that nothing answers, each one a window that closes `never-queued` (unprobed).

Observed on the probe PRs #504 and #505 for #500, where the docs say otherwise: P2 findings are posted, not only P0 and P1; a draft PR is reviewed on request; the footer saying reviews start when a PR opens describes automatic review, which is off here. Codex acknowledged a request within 11 s on both, inside the 60 s a comment-transport poll allows for one. A mention of Codex on an issue drew a reply asking for a Codex environment, which is no review.

## claude

`.github/workflows/claude-review.yml` drives it. It runs only when `codex` ends as [the profile's block](ship.md#claude) says: **Not reviewed**, **Capped with findings** or **Not landed**, each defined in [the review glossary](../glossary/review.md). The workflow posts its findings as one formal review per round, which is what `poll-pr --reviewer claude --since <iso>` lands, and the action attaches the per-file ones as inline threads on that review.

`Login:` is `claude[bot]`: the round is posted by `anthropics/claude-code-action` under the Claude GitHub App the workflow's `claude_code_oauth_token` authenticates, not under the Actions identity. Only the `if: failure()` comment below the action runs on `github.token`, and that comment is not a round, so the login the loop awaits is the app's.

A round that dies before posting is `not reviewed: infra-error`: `poll-pr --reviewer claude` awaits the run the block's `Workflow:` names and reads its failure directly, a plain comment being no round; the workflow's own `if: failure()` comment names the run on the PR, with the failure subtype where the action left one and `unknown` where it did not, so the PR carries the reason, or the link to it in the Actions log. A cancelled job runs no step and leaves nothing on the PR, and the run read is what still names it: `poll-pr` reports a `cancelled` run as `infra-error`.
