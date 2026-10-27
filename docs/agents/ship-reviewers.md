# Ship profile: reviewer notes

Setup and probe evidence for the reviewers in the ship profile's `## Reviewers`. The profile ([ship.md](ship.md)) keeps the lines a run reads; this file is for a maintainer setting a reviewer up, or checking what one was seen to do.

## codex

Setup, once, on the maintainer's ChatGPT account: install the ChatGPT Codex Connector app on the repository (the **Connect GitHub** button in the environment picker on chatgpt.com/codex), turn code review on for this repository at chatgpt.com/codex/settings/code-review, and leave automatic review off there, both for the repository and in personal preferences, so a round runs only when requested. A round run through GitHub counts as Code Review usage against the subscription's Codex allowance, shown on the usage dashboard at chatgpt.com/codex/settings/usage. To disable the reviewer, delete its `### codex` block in the profile. Turning code review off in those settings instead leaves ship requesting rounds that nothing answers, each one a window that closes `never-queued` (unprobed).

Observed on the probe PRs #504 and #505 for #500, where the docs say otherwise: P2 findings are posted, not only P0 and P1; a draft PR is reviewed on request; the footer saying reviews start when a PR opens describes automatic review, which is off here. Codex acknowledged a request within 11 s on both, inside the 60 s a comment-transport poll allows for one. A mention of Codex on an issue drew a reply asking for a Codex environment, which is no review.
