### Review

**Reviewer**:
One automated review bot the ship profile names for a repo, with its login, its trigger, whether it is gating (a required check that can block the merge), and the reviewer it is a fallback for. A repo lists zero or more; no reviewer means the self-review plus green CI is the whole review gate. Preflight parses the blocks and refuses ten shapes before the claim: a block named `self-review` (or starting `self-review `), whose Run-file lines would be phase 4's, a fallback that is not on-request, one naming a reviewer nobody listed, an on-request reviewer with no cap, a `Cap:` that is neither a number nor `None.`, a `Request: comment` with no phrase for the transport to post, a comment transport with no `Workflow:` naming the file its round comes from, a `Workflow:` on a block no comment transport drives, a `Workflow:` naming a file the checkout does not carry, and a `Workflow: native <integration>` naming an integration ship has no reader for. One reviewer fact the blocks cannot settle themselves comes from the host instead: whether a Copilot reviewer's `Trigger:` matches the `copilot_code_review` ruleset that drives it.
_Avoid_: review bot topology (the old three-shape framing), bot lane

**Trigger**:
How a reviewer's rounds start: auto-once fires on PR creation and is dispositioned once, on-push re-reviews every push, on-request delivers one review per explicit request, and where the host still posts an opening round on its own, round 1 is polled from PR creation, so that round is round 1, and one already landed takes no request. The loop and mechanics follow the trigger alone; the bot's brand decides nothing. The profile's `Cap:` is a budget for the rounds **ship drives**, which is every round only where ship starts them: a reviewer the host re-runs on its own keeps posting past the number.
_Avoid_: mode, kind of bot

**Fallback reviewer**:
A reviewer driven only when the reviewer it names exits not reviewed, for any reason but the inline lane, is capped with findings, or stops not landed; a primary that reviewed otherwise leaves it unspent. Always on-request, because a reviewer that fires on every push cannot be withheld. When the primary reviewed, the fallback still reports, as not invoked, so the human sees it exists.
_Avoid_: backup bot, secondary reviewer, second opinion

**Capped with findings**:
A reviewer that stopped at `cap` after spending its whole `Cap:`, the last of those rounds' fixes changing the tree, so no host round read them. It and a not-landed primary are the `reviewed` primaries that still drive their fallback. A docs-only fix-only diff that ends the loop before the cap is spent, a last round whose findings were all declined, and a cap from a re-raised declined finding, are not it.
_Avoid_: ran out of rounds, hit the cap

**Not landed**:
A reviewer's `Stop:` reason where a dispositioned round's fixes changed the tree and the next requested round did not land (blocked, never-queued, infra-error and the other `not_reviewed` causes), so no host round read those fixes. Its exit is still `reviewed`, the cause on its `## Review` line, and like a primary capped with findings it drives its fallback.
_Avoid_: blocked stop, half reviewed

**Request transport**:
How an on-request reviewer is asked for a round, named by its `Request:` line alone, whatever its brand. Two of them: the host's own request-a-reviewer call, for a reviewer the host can add to the PR, and the comment transport, `comment <phrase>`, which posts the phrase as a PR comment for a reviewer a comment triggers: a comment-triggered workflow, or a native integration such as Codex. Either way the request is read back off the host, and the since rule takes its timestamp from that read-back, so the clock is the host's.
_Avoid_: request method, trigger phrase (that is the workflow's own setting)

**Landing rule**:
Which reviews `poll-pr` accepts as the round it is waiting for, reported as `landed_by`. The reviewer's `Trigger:` picks the rule, which `poll-pr --reviewer` derives from its block. The head rule takes only a review on the current head, because an on-push reviewer earns a fresh one per push. The since rule takes a review submitted at or after the `--since <iso>` instant on any head, because an on-request or auto-once reviewer posts one round per request and a later push would otherwise strand it; that instant is the one value the poll cannot derive. Neither rule takes a row that is not substantive; a quota or rate-limit notice refuses the round rather than delivering it.
_Avoid_: landing check, freshness rule

**Substantive**:
A review row that counts as a round: one with text that is not wholly a quota or rate-limit notice, or a bodiless verdict (approved or changes). Ship grades it above the host, never in an adapter.
_Avoid_: real review, meaningful round

**Round clip**:
The 2000-character cap `poll-pr` puts on every review body, marked `...[truncated]` where it bites, so one poll cannot flood the run's window. `--brief --full <id>` lifts it for the rows it names and nothing else, and `--full` without `--brief` is refused. It covers review bodies alone. A `--brief` thread row's `lead` is its first line with text, cut at 200 characters, and carries the same marker where either cut bites: past 200 characters, or where a later line with text was dropped. Naming the thread in `--brief --full <id>` returns its first comment whole as `lead`. A reviewer that opens with a preamble pushes its findings past the cap, and a round or lead that comes back clipped is one phase 7 has not read.
_Avoid_: truncation, body limit

**Reviewed**:
A reviewer's phase-7 exit where at least one of its rounds landed and every finding in it carries a disposition, whether or not a later round landed. A gating reviewer's declined finding is still reviewed, cited at the merge gate as the override the human decides on.
_Avoid_: converged, approved, clean, passed

**Not reviewed**:
A reviewer's phase-7 exit where no round of it landed, or one did and its threads could not be read (unreachable), named by the cause a mechanic observed: poll-pr's `not_reviewed` (unreachable, blocked, never-queued, still-running, stale-head, infra-error, silent) or request-review's exit 1 (never-queued). It still proceeds to the merge gate on green CI, the human's call there rather than a hand-back.
_Avoid_: degraded, failure, timeout, skipped review

**Not invoked**:
The phase-7 exit belonging to a fallback reviewer whose primary reviewed, was not capped with findings and did not stop not landed: it went unrequested, so it has no rounds and no findings. Neither reviewed nor not reviewed, and the run carries on past it. It is reported anyway, in the PR body and the merge summary, so a reader sees a reviewer that exists and was deliberately not spent rather than one nobody configured.
_Avoid_: skipped, not needed, n/a

**Shape**:
The compressed code-form view of a change, sitting under a PR body's `## Change outline`: a call tree, control flow, pseudocode or component tree, written as a `diff` fence so the before and the after sit in one view. **One behavioural fence per PR**, about 15 lines or fewer, every node a real symbol and every root node carrying its file path; a carrier file tree may follow it, and only where the same edit lands in more than two files. The `Shape: none, mechanical (<kind>).` line replaces the fence only where the reviewer's question is "did the text change correctly", never where it is "what does X now do", and omitting both silently is a finding.
_Avoid_: diagram, visual, picture, mermaid, sketch

**Body preamble**:
Everything in a PR body above its first `## ` heading, which is the closing reference and nothing else. The half of a body no section rewrite reaches, and `update-pr-body --preamble` is what rewrites it, carrying over a closing line the new content lacks so a rewrite that says nothing about closing keeps the link to the issue; content carrying its own closing line is left as written, whichever issues it names.
_Avoid_: header, intro, top of the body
