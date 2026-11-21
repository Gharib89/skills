# Research: evidence per job kind for the agents and models table

Researched 2026-11-21 for wayfinder ticket #1313. This page holds the evidence
behind each row of the draft table in
[super-agent-agents-and-models.md](super-agent-agents-and-models.md), which
also defines the claim labels (**measured**, **sourced**, **inferred**,
**guess**). Benchmark names and scores are quoted from the pages cited; none
was re-run here.

## Code

- Anthropic: "For most coding and knowledge tasks, we recommend that users start
  with Claude Opus 5.5, our strongest daily driver", and "Fable and Mythos are
  best for the most ambitious, open-ended technical work." Its own table puts
  Fable 5.2 at 49.1% on FrontierCode 2.0 against 45.5% for Opus 5.5 and 42.8%
  for GPT-6 Astra, and says Fable at high effort about matches Opus 5.5's best
  at about half the cost per task. Vendor numbers. **sourced**
  <https://www.anthropic.com/news/claude-fable-and-mythos-5-2>
- OpenAI: "For most tasks in ChatGPT Work or Codex, start with GPT-6.2 Sol.
  Choose GPT-6.2 Astra for complex projects." **sourced**
  <https://learn.chatgpt.com/docs/model-selection> Sol "comes within 0.5 points
  of GPT-6.2 Astra at about one-fifth the cost" on FrontierCode 2.0. Vendor
  number. **sourced** <https://openai.com/index/introducing-gpt-6-2-astra-sol/>
- Independent, long-horizon (a Rails app over seven sprints with 14 planted
  defects, one run per model): Opus 5.5 100.0 in 64 min for $16.63; GPT-6 Astra
  100.0 in 100 min; Gemini 4 Argon 100.0 in 114 min; GPT-6.1 Sol 97.0 in 65 min;
  Sonnet 5.5 88.0 in 27 min for about $3.90; Gemini 3.8 Flash through
  Antigravity 89.5; Grok 4.7 83.5 in 120 min for $27.94. The author measured a
  nine point swing between two runs of one model. **sourced** (the Akita URL in
  the main page). GPT-6.2 and Fable 5.2 postdate that run.
- Independent leaderboard: Terminal-Bench 4.1 has Opus 5.5 and Fable 5.2 tied
  at 65.8%. **sourced** <https://snorkel.ai/leaderboard/?topic=agentic-coding>
- Grok: xAI's model card reports 38.0% on Terminal-Bench 4.0 against 57.9% for
  Fable 5.1. **sourced** <https://media.x.ai/v1/website/4p7card-5eccc980.pdf>
  Artificial Analysis ranks Grok Build with Grok 4.7 fourth among native
  harnesses and notes it uses about three times the output tokens of GPT-6
  Astra per task. **sourced**
  <https://artificialanalysis.ai/articles/benchmarking-grok-4-7> One hands-on
  reviewer placed it last on all three builds and "wouldn't trust it on
  day-to-day coding". **sourced** <https://www.aiformortals.co/blog/grok-vs-chatgpt>

Reading: keep the Sonnet then Opus ladder on Claude Code. Sonnet 5.5 is the
fastest and cheapest of the set and scores lowest of the current models, which
fits XS and S only. Codex on Sol is the fallback because it is the one other
instance with both a quota read and a T3 launch. Fable 5.2 is a candidate top
rung for XL or ambiguous work, on its own nearly unused weekly bucket; that is
a ladder change for the owner. Grok and Pi stay out of ship runs. **inferred**.

## Research

- Fable 5.2 scores 82.1% on WANDR (agentic search) against 72.3% for Opus 5.5,
  and 74.2% on Humanity's Last Exam with tools against 67.7% and 57.2% for
  GPT-6 Astra. Vendor numbers. **sourced** (Anthropic URL above).
- OpenAI positions Astra for research: it "can work through a research question
  across multiple sources and check its conclusions against the data".
  **sourced** <https://learn.chatgpt.com/docs/whats-new/gpt-62-astra-sol> OpenAI
  claims GPT-6.2 Astra leads Fable 5.2 by 5.5 points on Agents' Last Exam at 5%
  of the cost. Vendor number, on a leaderboard that excluded nine Fable tasks.
  **sourced** (OpenAI announcement URL above).
- Grok's API tools include web search and X search. **sourced**
  <https://docs.x.ai/developers/grok-4-7> The same hands-on reviewer found it
  best "for anything that needs X". **sourced** (aiformortals URL above).

Reading: Fable 5.2 preferred, Codex Astra as fallback and as the natural
second-vendor view, since the two vendors each claim the lead on a different
benchmark. Grok only when X or the live web is the source. **inferred**.

## Review

One pre-registered, non-vendor benchmark (168 pull requests, three runs per
reviewer, effort high, run 2026-10-20 to 26) compared the three harnesses.
**sourced** <https://cross-review.tlelabs.com/benchmark/>

| Reviewer | Model | Recall | Precision | False alarms on correct PRs | Median run |
| --- | --- | --- | --- | --- | --- |
| Codex | GPT-6 Astra | 0.916 | 0.576 | 47.8% | 179 s |
| Claude Code | Opus 5.5 | 0.892 | 0.620 | 20.7% | 141 s |
| Antigravity | Gemini 4 Argon | 0.707 | 0.871 | 5.2% | 325 s |

- The recall gap between Codex and Claude Code is not significant; Codex raised
  a false alarm on almost half of the correct pull requests. **sourced**.
- "A second model did not fix more bugs": adding any reviewer to a Claude Code
  or Codex fix loop did not raise the share fixed over the agent reviewing its
  own work. **sourced**. This cuts against a second-vendor read on every PR.
- Its limits, stated on the page: Claude wrote the planted corpus, the judges
  are the contestants, and the real-bug set is 21 bugs. It tested GPT-6 Astra,
  not the `gpt-6.2-sol` the owner's Codex defaults to. **sourced**.
- OpenAI: "Choose Sol to review a pull request". **sourced** (GPT-6.2 URL
  above).
- Cursor Bugbot scored 84.2% precision and 28.2% recall on a vendor-run
  benchmark whose author's own tool leads it. **sourced**
  <https://codepulse.review/benchmark>

Reading: Codex stays the cross-vendor reviewer for Claude-written PRs while its
weekly bucket is healthy, and its findings need the triage the false-alarm rate
implies. Near the limit, Claude Code's review loses little recall, so reserving
Codex for M and larger PRs costs little. Antigravity on Gemini 4 Argon would be
the quiet, precise reviewer, but T3 cannot launch it and that model shows as
disabled here. **inferred**.

## Bounded text

- OpenAI names GPT-6 Luna for "frequent, bounded tasks": "edit existing files,
  extract fields, and triage routine requests". **sourced** (model selection
  URL above).
- Gemini 3.8 Flash through Antigravity cost "$0 marginal (OAuth)" in the
  independent run. **sourced** (the Akita URL in the main page). It is on a quota the owner's ship
  runs do not touch. **inferred**.
- No evaluation of summarising or drafting quality was found for these models.

Reading: keep agy on Gemini 3.8 Flash as the first pick, because the job is
cheap and that quota is otherwise idle. Today it has no fallback except Claude
Code, and agy's read failed, so a Codex Luna fallback over `codex exec` would
close the gap. **inferred**.

## Design critique

- WebDev Arena (blind human votes on built web apps, 2026-11-20): Fable 5.2 at
  xHigh 1,824, Opus 5.5 at Max 1,819, Sonnet 5.5 1,772, Gemini 4 Carbon 1,769,
  GPT-6.2 Astra 1,766, Gemini 4 Neon 1,765, GPT-6.2 Sol 1,754. **sourced**
  <https://arena.ai/leaderboard/code/webdev>
- DesignArena overall agentic board (2026-11-21): Opus 5.5 at high 1439, GPT-6
  Astra at max 1391, Fable 5.2 1360. **sourced**
  <https://www.designarena.ai/leaderboard?section=overall> Its single-file
  board orders them differently: GPT-6.2 Sol 1404, then Fable 5.2, Gemini 4 Neon
  and GPT-6.2 Astra at 1390, all four preliminary. **sourced**
  <https://www.designarena.ai/leaderboard/code>
- OpenAI: "Choose GPT-6.1 Terra to interpret visual information, such as charts
  and screenshots". **sourced** (model selection URL above).
- A write-up of these boards notes they rank a model's default choices when
  building, and that the order reshuffles when the input is a screenshot.
  **sourced** <https://thanor.ai/blog/design-arena-leaderboard>

Reading: the two boards disagree on order and agree on the set, so the vendors
are close and this is the job kind where a second-vendor view is most likely to
differ usefully. Opus 5.5 leads both agentic boards and is on a read quota.
Building well is not the same skill as critiquing, so this row is the weakest
in the table. **inferred**.

