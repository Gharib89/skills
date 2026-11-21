# Research: which quota bucket a Codex pull request review draws from

Researched 2026-11-21 for issue #1314 (map #1310, pain point 10: spend the Codex
review limit while there is quota, and spend it wisely near the limit).

Each claim carries its basis: **measured** (a command run on 2026-11-21, named),
**sourced** (a first-party page or source file, linked), **inferred** (reasoned
from measured or sourced facts) or **guess**.

No review was requested and no pull request comment was posted for this note. A
live before-and-after measurement spends the owner's allowance, so it is written
as the remaining probe in section 8.

## 1. Verdict

**Same bucket, on the current plan. Inferred, with strong evidence, not yet
confirmed by a before-and-after read.**

A review requested with `@codex review` draws from the `codex` bucket that the
quota reader (`account/rateLimits/read`) reports: both its 5 hour window and its
weekly window. Four window starts recorded by the reader, two weekly and two
5 hour, each fall 41 to 60 seconds after a review request and at no other
recorded Codex activity (section 4).

The caveat that decides whether the reading can be trusted: the reader measures
the account the Codex CLI is logged in to, and a review is billed to the account
the GitHub connector is linked to. From 2026-11-04 to 2026-11-09 the connector
refused 64 requests while the reader's bucket showed 5 to 77 percent used
(section 5). In that period the reader was not measuring the bucket that gated
reviews.

## 2. What the reader returns

**Measured** with the fleet file's `providers.codex.quota_command`, run once at
2026-11-21T09:09:42Z on `codex-cli 0.170.0`. The reply to
`account/rateLimits/read`, account id and credit id redacted:

```json
{
  "ordinaryUsageAllowed": true,
  "rateLimits": {
    "limitId": "codex",
    "limitName": null,
    "normalModelSlug": null,
    "primary":   { "usedPercent": 0,  "windowDurationMins": 300,   "resetsAt": 1795270183 },
    "secondary": { "usedPercent": 36, "windowDurationMins": 10080, "resetsAt": 1795452246 },
    "credits": { "hasCredits": false, "unlimited": false, "balance": null },
    "individualLimit": null,
    "spendControlReached": false,
    "planType": "team",
    "rateLimitReachedType": null
  },
  "rateLimitsByLimitId": { "codex": { "...": "the same object as rateLimits" } },
  "rateLimitResetCredits": {
    "availableCount": 1,
    "credits": [
      { "id": "<redacted>", "resetType": "codexRateLimits", "status": "available",
        "grantedAt": 1794523696, "expiresAt": 1797115696,
        "title": "Full reset (Weekly + 5 hr)" }
    ]
  },
  "accountId": "<redacted>",
  "rateLimitUpsell": null
}
```

- The reply holds one bucket, `codex`, with a 5 hour window (`primary`, 300
  minutes) and a weekly window (`secondary`, 10080 minutes). There is no bucket
  named for code review. **measured** (the command above).
- An idle 5 hour window reports `resetsAt` as the read time plus 5 hours:
  1795270183 is 2026-11-21T14:09:43Z, 5 hours after the read. So a 5 hour reset
  time says when the window began only when `usedPercent` is above 0.
  **measured** (same reply).
- One banked "Full reset (Weekly + 5 hr)" credit is available, granted
  2026-11-12T22:48:16Z and expiring 2026-12-12T22:48:16Z. **measured** (same
  reply). OpenAI's help page says using a banked reset "refreshes your 5-hour
  and weekly Codex usage windows and changes your weekly reset date".
  **sourced**
  (<https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan>).
- The reader cannot show a separate code review limit even if the backend sends
  one. The CLI builds this reply from the backend's usage payload, and its
  payload model has the fields `plan_type`, `rate_limit`, `credits`,
  `spend_control`, `additional_rate_limits` and `rate_limit_reached_type` only.
  `rate_limit` becomes the `codex` bucket and each `additional_rate_limits`
  entry becomes one more bucket keyed by its `metered_feature`. **sourced**
  (`codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs`
  and `codex-rs/backend-client/src/client.rs` in `openai/codex` at commit
  `1145028ae47e8119955323d38ce34122d418f951`). The name
  `code_review_rate_limits` appears in that repository only in two test
  fixtures, both times as `null`. **measured**
  (`gh api search/code -f q='code_review_rate_limit repo:openai/codex'`).

## 3. What OpenAI's pages say

- The pricing page defines a usage category: "Code Review usage applies only
  when Codex runs reviews through GitHub, for example, when you tag `@Codex` for
  review in a pull request or enable automatic reviews on your repository.
  Reviews run locally or outside of GitHub count toward your general usage
  limits." It gives no code review allowance, no number of reviews per plan and
  no reset rule for it. **sourced** (<https://developers.openai.com/codex/pricing>,
  read 2026-11-21).
- The same page says "Local messages and cloud chats share your plan's usage
  allowance. Weekly limits may also apply", lists the 5 hour estimates for Plus
  and Standard Business as equal, and says of an in-flight task: "If you reach
  your usage limits during an active turn, the agent will be able to continue
  working on that turn, subject to fair use limits." **sourced** (same page).
- The GitHub integration page says nothing on usage, limits or which account a
  review is billed to. **sourced**
  (<https://learn.chatgpt.com/docs/third-party/github>, where
  `developers.openai.com/codex/integrations/github` now redirects).
- OpenAI staff, in the Codex repository's discussions: "There are two separate
  utilizations: one for code generation and a second for code review"
  (2026-01-08), and, on a refusal with quota showing: "When a github is
  connected to multiple accounts (or accounts in workspaces, which are see as
  separate accounts), the most recently connected one is usually used"
  (2026-01-22). **sourced**
  (<https://github.com/openai/codex/discussions/8503>).
- Open bug reports from July to October 2026 describe the refusal arriving with
  weekly allowance left (98, 73, 50 and 44 percent remaining), with no staff
  answer on which bucket gates a review. One reporter read the backend usage
  endpoint twice and found that the value with no account header was exhausted
  while the account-scoped value the dashboard and CLI use was at 64 percent.
  **sourced**, third-party reports, not OpenAI statements
  (<https://github.com/openai/codex/issues/31001>,
  <https://github.com/openai/codex/issues/52549>).

So the pages name code review as its own usage category, and do not say today
whether it has its own allowance. They do not settle the question.

## 4. Local evidence that a review draws from the `codex` bucket

Sources, all read on 2026-11-21:

- Review requests and connector answers: `gh api --paginate
  'repos/<owner>/<repo>/issues/comments?since=2026-11-01T00:00:00Z'`, filtered
  to `@codex review` comments and comments by `chatgpt-codex-connector[bot]`,
  over this repository and three others on the same account (found with
  `gh api search/issues -f q='commenter:<owner> "@codex review" in:comments is:pr'`).
  From 2026-11-01 to 2026-11-21: 183 requests, 75 reviews started and 76 refused
  with the usage-limit notice.
- Bucket readings: the two saved reads under `~/.local/state/super-agent/`
  (`quota.json`, read 2026-11-19T20:29:35Z, and a saved copy read
  2026-11-18T09:38:40Z), and the `rate_limits` snapshot the Codex CLI writes into
  its session logs under `~/.codex/sessions/` on every turn (3613 snapshots, the
  same `codex` bucket with `used_percent` and `resets_at`).
- The ledger holds no `limit` record at all, and none of its entries names a
  Codex model: 117 name a Claude model and 16 name none (`jq` over
  `ledger.json`). **measured**. So no supervised thread is known to have spent
  the Codex bucket in the intervals below. **inferred**.

### Four window starts, each just after a review request

A window's start is its reset time minus its length. **Measured** from the
readings above, lined up against the request comments:

| Window | Reset the reader reported | Window start | Review request just before | Gap |
| --- | --- | --- | --- | --- |
| weekly | 2026-11-16T15:07:33Z | 2026-11-09T15:07:33Z | 2026-11-09T15:06:33Z | 60 s |
| weekly (the current one) | 2026-11-23T16:44:06Z | 2026-11-16T16:44:06Z | 2026-11-16T16:43:12Z | 54 s |
| 5 hour | 2026-11-18T13:40:48Z | 2026-11-18T08:40:48Z | 2026-11-18T08:40:07Z (PR #1273 here) | 41 s |
| 5 hour | 2026-11-19T22:36:47Z | 2026-11-19T17:36:47Z | 2026-11-19T17:35:54Z | 53 s |

- No local Codex CLI session was running at any of the four starts: the session
  logs hold no snapshot between 2026-11-06T22:25Z and 2026-11-15T09:59Z, none
  between 2026-11-16T06:46Z and 2026-11-17T06:42Z, and none after
  2026-11-17T07:19Z. **measured** (session log timestamps). Codex use on another
  machine logged in to the same account is not ruled out. **guess** that there
  was none at those four minutes.
- The windows behave as "started by the first use after the last one expired".
  The weekly window that ended 2026-11-16T15:07:33Z was followed by one that
  began at 16:44:06Z, at the first review after the expiry, and reviews at
  11:13Z, 13:38Z, 13:39Z and 14:48Z that day, before the expiry, started
  nothing. On 2026-11-19 reviews at 12:26Z and 15:55Z were followed by a new
  5 hour window only at 17:36:47Z, which fits a window opened by the 12:26Z
  review and expired near 17:27Z. **inferred** from the measured times.
- That a review starts a window of the `codex` bucket means it is metered in
  that bucket. **inferred**. Four of four is hard to read as chance, since each
  gap is under a minute and the reviews are hours or days apart.

### Refusals that follow the 5 hour window

On 2026-11-09, after the weekly window began at 15:07:33Z:

- 8 reviews started between 15:06Z and 15:40Z, then 10 requests were refused
  from 15:42Z to 19:43Z. That 5 hour window ended at 20:07:33Z.
- 6 reviews started between 21:00Z and 23:37Z, then 2 requests were refused at
  01:37Z and 01:46Z, inside the 5 hours after 21:00Z.
- Reviews ran again from 03:54Z on 2026-11-10, and none has been refused since:
  33 reviews started through 2026-11-20.

**Measured** (the comment timestamps). The refusals start after 6 to 8 reviews in
one 5 hour window and stop when it ends, so the notice on that day was the
bucket's 5 hour window at its limit, not a weekly limit. **inferred**.

## 5. Evidence against, and what it means

From 2026-11-04T13:42Z to 2026-11-09T14:55Z the connector refused 64 requests
in five runs, while the Codex CLI's own snapshots of the `codex` bucket showed
room in both windows. **Measured** (comment timestamps against session log
snapshots):

| Refusals | Nearest reading of the reader's bucket |
| --- | --- |
| 2026-11-05T05:59Z to 08:11Z, 5 refused | 5 hour 5 to 13 percent used, weekly 17 to 19 percent |
| 2026-11-05T18:32Z to 19:31Z, 2 refused | 5 hour 33 percent, weekly 33 percent |
| 2026-11-05T20:59Z to 2026-11-09T14:55Z, 50 refused | at the start 5 hour 17 percent and weekly 37 percent, at 2026-11-06T22:25Z weekly 77 percent |

In those snapshots `plan_type` is `plus`. From 2026-11-15 on it is `team`, with
a weekly window that began at the first review after the long run of refusals
(first row of the table in section 4). **measured**.

Two readings fit, and the evidence does not choose between them:

1. The CLI was logged in to a different account than the one the connector
   billed (a personal plan against a workspace plan), so it read a bucket the
   reviews never touched. OpenAI staff describe this case (section 3).
   **inferred**. The long run of refusals then reads as the connector account's
   weekly window at its limit: 28 reviews started from 2026-11-01 up to the
   first refusal of that run.
2. On the earlier plan a review was gated by a separate code review limit on
   the same account, and the plan change merged or replaced it. **guess**.

Either way the rule for the design is the same: **the reading predicts a refusal
only while the CLI login and the connector's link are the same account**, and
the reader cannot tell on its own. A refusal that arrives while the reader shows
room is the signal that they have diverged.

## 6. What one review costs

No single review was measured in isolation. These are totals over intervals
where the session logs show no local Codex use and the ledger no Codex thread,
so each is an upper bound if another machine used the account. **Measured**
readings, **inferred** attribution:

| Interval | Reviews started | Weekly window moved | Per review |
| --- | --- | --- | --- |
| 2026-11-09T15:07Z to 2026-11-15T09:59Z | 27 | 0 to 61 percent | about 2.3 points |
| 2026-11-16T16:44Z to 2026-11-17T06:42Z | 1 (4 minutes, with findings) | 0 to 3 percent | about 3 points |
| 2026-11-17T07:19Z to 2026-11-18T09:38Z | 1 (2 minutes, clean, PR #1273) | 11 to 11 percent | under 1 point |
| 2026-11-17T07:19Z to 2026-11-19T20:29Z | 13 | 11 to 29 percent | about 1.4 points |

For the 5 hour window: 3 percent after the one clean review on 2026-11-18,
23 percent after two reviews on 2026-11-19 (about 12 points each), and a
refusal after 8 reviews on 2026-11-09 (about 12 points each).

Working numbers, **inferred**: one review costs about 1.5 to 3 points of the
weekly window and about 12 points of the 5 hour window, less for a small clean
diff. That is roughly 8 reviews per 5 hour window and 35 to 65 per week if
nothing else spends the bucket. Cost varies with the diff: the pricing page
says usage depends on "size and complexity of your tasks" (**sourced**, section
3). The 5 hour window, not the weekly one, is what a burst of ship runs hits
first.

## 7. Reset, and predicting a notice

- The weekly window resets at **2026-11-23T16:44:06Z** (`secondary.resetsAt`
  1795452246), at 36 percent used on 2026-11-21T09:09Z. **measured**. The next
  window opens at the first use after that, review or CLI, and resets 7 days
  after that use, so the weekly reset drifts later each week by the idle gap.
  **inferred** (section 4). The banked reset credit moves it too (section 2).
- A notice can be predicted from one read before the request, with no spend,
  under the same-account condition of section 5. **inferred**. The rule the
  evidence supports: expect a refusal when `primary.usedPercent` or
  `secondary.usedPercent` is at 100, and treat a request as likely to be the
  last one when the 5 hour window is above about 88 percent or the weekly one
  above about 97 percent. The reply also carries `rateLimitReachedType` and
  `ordinaryUsageAllowed`, which are `null` and `true` with room left; their
  values at the limit were not observed.
- What is not measured: no reading was saved during a refusal, so "a notice
  means a window at 100 percent" rests on the 2026-11-09 timing, not on a read.
  A review already running when the window fills is expected to finish
  (**sourced**, section 3), which was not observed either.
- A refusal is cheap to recognise after the fact: the connector answers within
  about 12 seconds with a summary comment whose state is `"status":"failed"`
  and a second comment starting "You have reached your Codex usage limits for
  code reviews". **measured** (76 notices).
- When a refusal is caused by the 5 hour window, waiting is short: the reader's
  `primary.resetsAt` is the time to retry. The current ship profile caps Codex
  at one round as a fallback and records a usage-limit answer as not landed
  (`docs/agents/ship.md`, `docs/agents/ship-reviewers.md`), which fits a weekly
  limit and gives up early on a 5 hour one. **inferred**.

## 8. The remaining probe (needs the owner's approval, spends one review)

It turns "inferred" into "measured" for the verdict and gives a clean cost for
one review.

1. Pick a moment when the bucket is idle: run the reader and check that
   `primary.usedPercent` is 0 and `primary.resetsAt` is the read time plus
   5 hours. Run no Codex CLI, app or cloud task on any machine until step 4.
2. Save the read with its time: `<quota_command> | jq -c 'select(.id==2)' >
   before.json`.
3. On one open pull request in a repository where code review is on, of
   ordinary size (a ship PR of 100 to 400 changed lines, not a one-line fix),
   post `@codex review` once. Note the request time and the diff size
   (`gh api repos/<owner>/<repo>/pulls/<n> --jq '.additions,.deletions'`).
4. Read again 2 minutes after the request, then 2 minutes after the connector's
   summary comment reaches `"status":"completed"`, saving each read.
5. Compare. Same bucket if `primary.resetsAt` stops moving and sits about
   5 hours and 1 minute after the request, and `primary.usedPercent` rises.
   Separate bucket if the 5 hour window is still idle (reset still read time
   plus 5 hours, 0 percent used) after the review completed. The rise in
   `primary.usedPercent` and `secondary.usedPercent` is the cost of that one
   review.

Two cheaper checks that spend nothing:

- At the next usage-limit notice, run the reader within a minute. A window at
  100 percent confirms the prediction rule. Room in both windows means the
  connector is billing another account or another limit.
- Read the backend usage payload the dashboard uses
  (`GET https://chatgpt.com/backend-api/wham/usage` with the CLI's login) and
  look at `code_review_rate_limit` and `additional_rate_limits`, which the CLI
  drops. This was attempted for this note and refused by the session's
  permission rules, since it reuses the CLI's stored credential, so it is the
  owner's to run or allow. The usage page at
  `chatgpt.com/codex/settings/usage` shows the same data, and the connector
  page at `chatgpt.com/codex/settings/connectors` shows which account GitHub is
  linked to.

## 9. For the map

- The reader the super agent already runs is the right meter for the Codex
  review budget, with no new command, while the login and the connector match.
- Budget by the 5 hour window first: about 8 reviews per window. The weekly
  window is the slower limit.
- A refusal with room showing is an account mismatch signal worth a
  needs-the-owner message, not a reason to retry.
- The reader needs one correction for an idle bucket: a 5 hour reset equal to
  the read time plus 5 hours means "not started", not "resets then".
