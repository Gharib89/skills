# Prior art for the super agent: routing, the review budget and a second view (pain points 9 to 11)

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Pain points 9 and 10: agents, quota, the right model, the Codex review limit

### 9a. Route by job kind first, then by quota

- usage-guard: `route --kind code|review|plan|bulk`. `plan` and `review` "stay
  on Claude while its daily share allows, then Codex"; `code` and `bulk` "go to
  the subscription lane with the most daily share left". With nothing left the
  lane is `wait`, with the time the next share starts, and "a banked provider
  reset is never spent automatically". **sourced**
  <https://github.com/agent-layer-mcp/usage-guard>
- omnitrix: exclude accounts that cannot take the task now (signed out, cooling
  down, out of quota, not permitted for the task's privacy level), then score
  by fit, quota left, cost and past acceptance. A window that "resets within
  the next hour" with at least 20% left multiplies the score by 1.25 "so that
  the quota is used before it is lost"; an account "forecast to run out of a
  window before it resets" is multiplied by 0.75. **sourced**
  <https://github.com/MdHashim1011/omnitrix>
- Quota Boss: each sub-task gets a tier (critical, normal, trivial) and a
  category (architecture, debugging, implementation, review, research,
  mechanical); `utility = P(success) ^ alpha(tier, profile) / (cost x quota
  price)`. "Small jobs stay with the boss, because handing over a few minutes
  of work costs more than it saves." **sourced**
  <https://github.com/crazytoto/quota-boss>
- cli-relay: skip a provider when a window is at or over 97% used, wait for one
  that resets within 15 minutes, and rest a provider that failed on a limit
  until its reset. **sourced** <https://github.com/mustikon/cli-relay>
- Codync keeps a per-failure rest table (a usage limit rests until the reported
  reset, a sign-out until signed in again). **sourced**
  <https://www.codync.dev/docs/agent-fallbacks>
- LOOP lets "the root, execution, and audit stages" use different providers.
  **sourced** <https://github.com/LEO001020/codex-loop-orchestra>
- A practitioner's result of good pacing: "every week I finish with only 3 to
  5% of the weekly limit left". **sourced** (Tmeister)

Fit: `route.sh` today picks by size, headroom times weekly weight, and two
floors. Add, in this order (**inferred**):

1. `--kind` (ship, triage, research, grill, review, check, small). A table in
   the fleet file maps each kind to an ordered driver list and a starting tier.
   This is the map's "routing becomes job-aware".
2. Two pacing terms on the existing headroom number: a boost when an instance's
   window resets soon with quota left, and a penalty when its burn rate would
   empty it before the reset. Both need the reset time `quota.sh` already
   reads for Claude and Codex.
3. The route's reason string names which rule fired, as omnitrix and
   usage-guard both do, so a routing choice can be explained later (pain
   point 2).

Cost: medium. `route.sh`, the fleet schema, `quota.sh` saving reset times, and
fixtures for each rule.

### 10a. Spend the review limit once per PR, and use what would expire

- Codex reviews from Claude Code count: "Usage will contribute to your Codex
  usage limits." **sourced**
  <https://github.com/openai/codex-plugin-cc/blob/main/README.md>
- Fleet measured that "78% of our Copilot code review spend went to second and
  later reviews of the same PR", and changed to: every PR opens as a Draft and
  is marked Ready only after its internal review and CI pass, so the paid
  reviewer runs "then, once". **sourced** (Fleet part 4)
- ryle.dev: "One complete review, one fix pass, then merge." A cap of three fix
  rounds per failure kind still let a single PR "get up to eight fix pushes".
  **sourced** (ryle.dev)
- A different model as reviewer "catches mistakes the author model misses",
  but "it stops working as soon as it loops". **sourced** (ryle.dev)

Fit: the map lets the super agent steer the reviewer policy. A
`review-budget.sh` answers one question per PR from the saved quota read:
request Codex now, or not, and why. **inferred** rules, in order:

- Healthy quota: one Codex review per PR, requested when the PR is ready (CI
  green, the first reviewer done), never on each push.
- Near the limit: keep the remaining reviews for L and XL tickets and for PRs
  that touch a path the ship profile marks as risky; the rest go to the
  fallback reviewer alone.
- Near the reset with quota left: spend it, on the oldest open PR without a
  Codex read, or on an adversarial read of an open design ticket.

Whether the Codex review quota can be read separately from the general Codex
quota is a **guess**; probe the same command `quota.sh` uses. Cost: small.

## Pain point 11: more than one model's view on a new idea

- PAL MCP `consensus`: each model gets a stance (for, against, neutral),
  "Models analyze your proposal from their assigned perspective", and the
  calling agent "combines all perspectives into a balanced recommendation".
  **sourced**
  <https://github.com/BeehiveInnovations/pal-mcp-server/blob/HEAD/docs/tools/consensus.md>
- Its consultations are blinded: each model sees "only the original proposal",
  never another model's answer; the against stance "Must not oppose excellent,
  common-sense ideas just to be contrarian". **sourced, secondary**
  <https://deepwiki.com/BeehiveInnovations/pal-mcp-server/5.4.1-consensus-tool>
- llm-council: first opinions from every model, then each model ranks the
  others with "identities ... anonymized so that the LLM can't play favorites",
  then a Chairman "compiles them into a single final answer". **sourced**
  <https://github.com/karpathy/llm-council>
- Codex `adversarial-review` is "a steerable review that questions the chosen
  implementation and design", read-only, with focus text. **sourced**
  (codex-plugin-cc README)
- Claude Code's own example of a team for a design question: three teammates,
  "one playing devil's advocate". **sourced**
  <https://code.claude.com/docs/en/agent-teams>
- cezar: "Run the same task x2 or x3, compare the diffs and keep the best one."
  **sourced** (cezar README)

Fit: the skill already sends bounded text work to a second vendor through
`agy-job.sh`. Generalize it to a `second-view.sh` that sends one prompt file to
each vendor CLI with healthy quota, blind and in parallel, saves each answer,
and has the super agent write one comparison: where they agree, where they
differ, and what only one of them raised. That is the map's "one merged
comparison". **inferred**

- Borrow blinding (free) and the for/against stances as an option for a
  yes-or-no decision.
- Label the answers A, B, C before the merge step, so the merging model cannot
  favour its own vendor. **inferred** from llm-council's reason.
- Skip the peer-ranking round: it multiplies the calls by the number of models
  and the owner reads a comparison, not a league table. **inferred**
- Gate it on the kind (design, spec, research) and on the quota floors, with
  the router's reason recorded.
- Cost: small to medium. One script, one reference page.
