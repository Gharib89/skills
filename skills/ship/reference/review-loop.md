# Phase 7: driving every reviewer to convergence

The profile's `## Reviewers` lists zero or more reviewers. Each has the login(s)
it posts under, a `Trigger:`, `Gating:`, a `Cap:`, an optional `Instructions:`
file, and per trigger: `Request:` (on-request), `Resolve:` (on-push). The
**trigger fixes the loop and convergence**; the bot's brand fixes nothing.
Zero reviewers: skip this phase; the review gate is phase 4's self-review plus
green CI (SKILL.md), and reviewer rounds never replace it.

A reviewer re-reads the **whole PR** each round: treat every round's output as
a fresh read of the committed tree, not a conversation.

## Shared mechanics

- **Poll with `poll-pr <pr> --await-review <login>`**, inline, bounded,
  foreground. It returns one JSON: head sha, mergeable, checks, the reviewer's
  rounds with `substantive`, threads with resolved state, `reviewer_blocked`,
  and `landed_by` naming the rule that admitted the round. `done: false` means
  the window closed first: re-run to extend, never a background monitor. The
  poll is the landing signal only; before triage, read the round's review body
  and its threads from the same payload. The body sits on the row the reviewer's
  landing rule admitted: `reviews.on_head[].body` under the head rule,
  `reviews.all[].body` under the since rule, where the round may sit on an older
  head. A round whose findings live in the body rather than in threads is
  invisible from the thread list alone, and `infra-error` is a judgment about
  the body.
- **`--brief` projects that same poll** down to what this loop acts on: head,
  mergeable, `landed_by`, one row per round (id, `submitted_at`, `substantive`,
  and the body cut to its lead line and finding items) and one row per OPEN
  thread. Rounds come from the list the landing rule admitted, and the run's own
  replies drop out, so a round count is the reviewer's rounds and not ours. Take
  the full shape when a round needs reading whole; `--full <id>` still answers
  that on the row it names.
- **A body ending `...[truncated]` has not been read.** Rounds are clipped past
  2000 characters so one poll cannot flood the window, and a reviewer that opens
  with a preamble (an overview, a per-file table) pushes its findings past that
  cap. Re-run the poll with `--full <id>` for that row and it alone comes back
  whole. Dispositioning a clipped round is converging on findings you never
  saw.
- **The trigger picks the landing rule; the poll has to be told which.** Under
  the **head** rule (no `--since`) a round counts only on the current head:
  right for `on-push`, where every push earns a fresh review. Under the
  **since** rule (`--since <iso>`) a round counts wherever it sits, if it was
  submitted at or after that time: right for `on-request` and `auto-once`,
  which deliver one round per request and never re-post, so a push between the
  request and the review leaves the round keyed to the older head, and the head
  rule then waits out the whole window for a review that will never come again.
  Pass `request-review`'s `requested_at` or `open-pr`'s `created_at` straight
  through. `--since` without `--await-review` is a usage error. The since rule
  needs a timed round, so a reviewer whose only signal is an Azure DevOps vote,
  which the API never stamps, exits `degraded: silent` under it; its threads,
  which carry anything actionable, are stamped and land normally.
- **A round is a review with a body.** A reviewer's reply to one thread posts
  as a review row of its own (current head, empty body), so answering round N
  manufactures rows that look like round N+1 arriving. Only `substantive: true`
  counts; hold any hand check to that bar.
- **Triage, don't apply**, at the judgment tier, with phase 4's definition:
  harden rather than rip out capability, verify nits against the pinned
  versions, reject known non-issues with a one-line reason. The two rejection
  rails apply: check repo-existence claims against `origin/HEAD`, and judge a
  claim separately from the evidence it cites. Check the reviewer's
  `Instructions:` file when a finding contradicts it (a host may truncate that
  file; cite it when declining). A valid finding outside the issue is an
  adjacent find, and phase 2's three dispositions decide it, inline conditions
  and `file-issue`'s candidate check included. The thread then carries that
  disposition with the link. That is also the honest answer to a gating
  reviewer.
- **Batch fixes into one push per round**, then answer every `replied: false`
  thread with `reply-thread <pr> <thread> --body-file`, one call per thread with
  the id `poll-pr` returns (`fixed in <sha>`, or the decline and its reason).
  `poll-pr` returns the PR's whole thread set, not the round's, and `replied`
  is true once this identity has answered in the thread: skip those, one
  finding, one disposition. The disposition belongs in the thread the reviewer
  opened, which is where the reviewer's next pass and a human reading the round
  both look; a round-level `comment-pr` is a log of the round, never the
  disposition channel. **A fix to a rule is propagated to every copy of that
  rule inside the same batch**: grep the phrase before you push, and read each
  fix's hunk back out of the file while you are there, because the reviewer
  re-reads the whole PR and a copy the fix missed, or a fix applied by half, is
  another round spent on a finding you already agreed with. `resolve-thread`
  posts no body and runs per thread only once every thread carries its reply.
  Every push spends review quota and CI minutes, and an on-push reviewer's
  round.
- **Cap** is the profile's `Cap:`, the bound on one reviewer's rounds: a number,
  or `None.` for an uncapped loop. On-request it is required with no default,
  where a round costs a request; on-push it is a number or `None.`, where a
  round costs a push, a wait on the new head, and a triage and a reply per
  thread; `auto-once` delivers one round and reads `None.`. A round at the cap
  that is still substantive is a shape problem more rounds will not fix:
  disposition it in full (push its batch, reply to every thread, resolve where
  the trigger resolves), then exit `degraded: cap-hit` without waiting for
  another round.
- **Per-reviewer accountability.** Each reviewer gets its own block in the
  merge summary and its own line in the PR body's `## Review` section
  (`update-pr-body` at phase-7 exit): `converged`,
  `converged, override needed`, or `degraded: <reason>`, plus the round count.
- **The exit rewrites Deviations too, when the rounds grew the log.** A round
  can force the same departure from the issue, brief or plan that phase 2 logs,
  and an in-scope fix is no more a deviation here than anywhere else, so where
  the log changed since phase 6, write it back with
  `update-pr-body <pr> --section "Deviations from plan" --body-file <path>`
  before the `Review` write, which stays last so `read-pr` reads both back at
  once. Skip it and the PR body ships the phase-6 log while the merge summary
  carries the current one, and the human reads the two against each other.

## By trigger

### `auto-once`

Fires once on PR creation; nothing to request and **never re-requested**. Wait
for it to land under the **since** rule, with `open-pr`'s `created_at`. If a
round arrives before you poll, that is the round. Triage it once, push the
fixes, `reply-thread` on every `replied: false` thread. **Converged** when every
thread is dispositioned.
A later push does not bring it back; a lint or flake fix after convergence
needs nothing from it.

### `on-push`

Re-reviews every push, and the profile's `Cap:` bounds the rounds. After each
push, wait for a review **landed on the current head**, the **head** rule (no
`--since`); silence on the head is never quiet.
Triage, batch-fix, push, `reply-thread` on every `replied: false` thread. Once
**every** thread carries a disposition, and only then, use the reviewer's
`Resolve:` mechanism (`resolve-thread`, or the comment the profile names) to
resolve them.
**Converged** when a review has landed on the current head with nothing
actionable and every thread is dispositioned and resolved. A fix pushed after
convergence gets re-read on its own: wait for quiet on the new head again.
When `poll-pr` reports `threads: unavailable`, this reviewer's exit is
`degraded: unreachable` and the run proceeds; the other triggers read reviews
and comments, which stay readable.

### `on-request`

Nothing arrives until asked. `request-review <pr> <login>` issues the request
and **reads it back** from the host's own record (the mechanic knows that the
login you request and the login you read back can differ, and that an empty
requested-reviewers list proves nothing). One request yields one round; the
reviewer does not re-review on push, so each round after the first is a new
request against the corrected tree. Loop: request, poll under the **since**
rule with `request-review`'s `requested_at`, triage, batch-fix, push,
`reply-thread` on every `replied: false` thread, request again. **Converged**
when the latest round has nothing actionable and every thread from all rounds is
dispositioned.
Small lane: exactly one round. A lint or flake fix after convergence earns no
new request.

## Degraded exits: fixed vocabulary, per reviewer

Degraded means the reviewer did not finish its job; it proceeds to the merge
gate on green CI and never hands back on its own, in either lane. The human
reads the reason and decides.

| Reason | Detection |
|---|---|
| `never-queued` | on-request: no request event on the host's record after one retry. Do not spend a second poll window on it. |
| `blocked` | queued, then a quota or rate-limit notice from the reviewer, on either surface it states one on, a review body or a PR comment (`reviewer_blocked` non-null), and the poll window closed. A round that is only such a notice is not `substantive`, so `landed_by` stays null and the poll waits it out rather than reporting it as the round. Non-null with `done: false` means waiting, not missing. |
| `silent` | queued, no round admitted by the reviewer's landing rule within the bounded wait: under the head rule none on the current head, under the since rule none submitted after the timestamp on any head. |
| `infra-error` | a review whose body is only an error notice with zero comments, twice. Not feedback. |
| `cap-hit` | `Cap:` reached with the latest round still substantive, that round dispositioned. |
| `unreachable` | no host path to the reviewer from this environment, or thread state could not be read (`threads: unavailable`, which is also what leaves `reply-thread` with no id to answer). |

## Gating reviewer with a declined finding

A `Gating: yes` reviewer can hold the merge on a finding you decline. Every
thread dispositioned, the declined finding cited with evidence, build still
red: the exit is `converged, override needed`. Not degraded, because the
reviewer ran; the human overrides the policy or accepts the finding at the
merge gate.

## Worked examples

Brand-level detail lives in the host adapters; these show the mapping only.

- **GitHub Copilot as `on-request`**: request per round, cap from the
  profile. Two identities behind one reviewer: the request names one login,
  the review posts under another, and the check run a third; the mechanics
  match each surface to its own name. Copilot enabled as an automatic review
  by a repository ruleset is `on-push` or `auto-once` instead, according to the
  `copilot_code_review` rule's `review_on_push`.
- **CodeRabbit as `on-push`**: reviews every push; `Resolve:` is its resolve
  comment, posted once after every thread carries a reply.
- **Claude Code on GitHub Actions as `on-push`**: reviews every push through a
  workflow; no thread-resolution mechanism, so `Resolve:` reads `None.` and
  convergence rests on dispositioned threads and a quiet head.
- **Claude Code on Azure Pipelines as `on-push`, `Gating: yes`**: a build
  validation policy that fails the build on a critical finding; threads are
  Azure DevOps PR threads with `fixed | closed` status; a declined critical is
  `converged, override needed`.
