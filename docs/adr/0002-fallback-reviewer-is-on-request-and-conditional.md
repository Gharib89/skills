---
status: accepted
---

# A fallback reviewer is on-request and fires only on a degraded primary

Copilot's review quota is per month and a repo whose only reviewer is Copilot spends the rest of the month with every PR exiting `degraded: blocked`. The obvious repair is a second reviewer on every push, but that doubles the threads to triage and the spend in every month where the primary has quota. So a fallback reviewer is a reviewer that the run requests only after the reviewer it names exits degraded, for any degraded reason, since the human wants a review on the PR and the primary's reason for failing is a footnote. It is always on-request: a reviewer whose workflow fires on every push cannot be withheld, so nothing on-push can be a fallback. When the primary converges the fallback still reports, as not invoked, so a reader of the PR body or merge summary sees it exists rather than reading its absence as a reviewer nobody configured.

## Considered options

- Always-on second reviewer: no change to Ship, but every push pays for two reviews and two triages even when the primary is healthy.
- Swap the profile block to Claude until the quota returns, swap back by hand: no change to Ship, but the swap is a human's memory and the quota returns silently.
- Conditional on-request fallback (chosen): the request goes out only when the primary's exit is degraded, so the fallback costs nothing in a healthy month and the primary resumes on its own the month its quota returns.

## Consequences

- The fallback needs a new line on its reviewer block, which by the profile-schema bump rule is Schema 2 and a Ship major bump; installed consumers migrate through `setup-skills`.
- A comment-triggered workflow is the request transport, so `request-review` grows a second transport chosen by the profile and the round's `requested_at` is the comment's creation time.
- A fallback that stays silent on a clean PR is indistinguishable from one that failed, so the Claude reviewer submits one formal review per round, even when it has no findings.

## Amended by #307

The primary's `degraded` exit is now `not reviewed: <reason>`, and a primary whose cap ran out is `reviewed`, since its rounds landed: it no longer requests the fallback. The decision stands for every primary that exits `not reviewed`: one that delivered no round, or whose landed round's threads could not be read (`unreachable`).

## Amended by #531

The #307 amendment's capped primary is reversed for one case. A primary **capped with findings**, one that spent its `Cap:` (rounds == Cap) on a last round whose fixes changed the tree and so stopped at `cap`, drives the fallback as an ordinary on-request reviewer under its own `Cap:`. Otherwise those fixes reach the merge gate read by no host reviewer, only by the local cap review on the Standards axis. When the fallback reviews, its host rounds read them, so the primary's cap round gets no local review of its own; that review goes to the last reviewer that stopped at `cap`.

These still leave the fallback `not invoked`:

- a primary that stopped on `tree unchanged`, a last round whose findings were all declined included;
- a primary stopped by the small lane or `auto-once`;
- a docs-only fix-only diff that ended the loop before `Cap:` was spent.

It is a global Ship rule, not a profile key, so no schema moves.

## Amended by #545

A primary that exits `not reviewed: inline lane` leaves the fallback unrequested too. An inline-lane run without `--review` requests no round of any reviewer: the human waived them by invoking `--inline`, so the fallback records the same `inline lane` stop, and `run-file gate clean` reads that stop as settling its own reviewer only, never as a fallback covering a primary.
