# Research: how others build a supervising agent, and what to borrow

Researched 2026-11-21 for issue #1312 (child of map #1310): prior art for a
supervising agent over many coding-agent sessions, read against the owner's
eleven pain points. It extends `docs/research/super-agent.md` (2026-11-06),
which covered DeepSeek's super-agent, Magentic-One, Anthropic's harness
guidance and what wakes a T3 thread; none of that is repeated here.

The platform is fixed by the map: the super agent stays a pinned T3 Code thread
driven by the `super-agent` skill, its shell scripts and hooks. Every "fit"
below is costed against that, never against a daemon.

Each claim carries its basis:

- **sourced**: read on the page or repo file at the URL given. "sourced,
  secondary" means a third party describing someone else's system.
- **inferred**: my reasoning from sourced facts plus the skill's own files.
- **guess**: plausible, not checked. Each one names the probe that would settle
  it.

## Ranked summary

Ranked by value to the map: how many pain points it answers, how well it moves
a rule out of prose, and how little it costs on the fixed platform.

| # | Pattern | Pain points | Source | Fit cost |
|---|---------|-------------|--------|----------|
| 1 | Turn-end guard: a Stop hook that refuses to end the turn while work is open and no watcher has a fresh beacon | 1 | FirstMate, Claude Code hooks | Small: one script, one beacon write, one probe |
| 2 | Posture as a file a script writes (away, quiet, answer-only), read by hooks and scripts, never inferred from chat | 2, 6, 7 | FirstMate `/afk` and `/quiet`, Fleet | Medium: one script, two hook entries, status changes |
| 3 | One egress with a default of silence: needs carry `blocking`, an age and a dedupe key; stale ones are demoted by a script | 6, 7 | Deemwar, Batty, Fleet, Dan Mercede, Alertmanager | Small to medium: `status.sh` and `ledger.sh need` |
| 4 | Job-kind routing with quota pacing (kind table, use-it-or-lose-it boost near reset, reserve when forecast to run dry) | 9, 10 | usage-guard, omnitrix, Quota Boss, cli-relay | Medium: `route.sh --kind`, fleet schema |
| 5 | Recurring check as a watcher-run command that wakes the model only on a changed result or a missed run | 3 | FirstMate custom checks, Codex scheduled tasks, Fleet patrol | Medium: a ledger kind and a `watch.sh` branch |
| 6 | Blind multi-vendor read with one merged comparison (stances optional, no ranking round) | 11 | PAL `consensus`, llm-council, Codex adversarial review | Small to medium: extends the agy job script |
| 7 | Review budget: one review per PR at ready, never per push; spend leftover quota near reset | 10 | Fleet, ryle.dev, codex-plugin-cc, omnitrix | Small: a policy script the gate step-in reads |
| 8 | Decision record: each autonomous action appends its rule and inputs, so "why" is answered from a record | 2 | Batty, Gas Town patrol receipts, Dan Mercede | Small: one append in the scripts that act |
| 9 | Detect stops from the thread itself, in named classes, and decide nothing on an unreadable read | 1 | Fleet `fleet stalled`, Gas Town thresholds | Small: two more classes in `watch.sh` |

## Systems read

- **FirstMate** (kunchenguid/firstmate): an "agent distro" of instructions,
  skills and bash scripts; one primary session supervises crew sessions in
  worktrees, with a T3 Code backend listed as experimental. The closest match
  to this repo's shape. **sourced**
  <https://github.com/kunchenguid/firstmate/blob/main/README.md>
- **Fleet** (a four-part series by its author): hooks write agent state to
  SQLite, a small-model "Foreman" answers stalls, a "Chief" agent supervises,
  and the series is about why adding supervisors failed. **sourced** part 1
  <https://yasmorita.com/blog/less-attention/part-1/>, part 2
  <https://yasmorita.com/blog/less-attention/part-2/>, part 3
  <https://yasmorita.com/blog/less-attention/part-3/>, part 4
  <https://yasmorita.com/blog/less-attention/part-4/>
- **Dan Mercede's supervisor guide**: one Claude Code session supervising four
  Codex threads with files, `codex queue` and cross-session messaging. **sourced**
  <https://www.danmercede.com/guides/build-a-supervisor-agent>
- **Gas Town** (steveyegge/gastown): Mayor, Witness, Deacon, Daemon patrols.
  **sourced**
  <https://github.com/steveyegge/gastown/blob/main/docs/design/polecat-lifecycle-patrol.md>
- **Batty**: a Rust supervisor daemon, with 19 days of unattended telemetry.
  **sourced**
  <https://dev.to/battyterm/i-let-an-ai-agent-supervisor-run-unattended-for-19-days-heres-what-the-telemetry-says-5f5i>
- **ryle.dev fleet lessons**: about 12,000 agent PRs over a few months.
  **sourced** <https://ryle.dev/blog/agent-fleet-lessons/>
- **Claude Code docs**: hooks, agent teams, cross-session messaging, scheduled
  tasks, `/goal`, `/btw`. **sourced** URLs at each use.
- **OpenAI**: Symphony's spec, Codex scheduled tasks, and the Codex plugin for
  Claude Code. **sourced**
  <https://github.com/openai/codex-plugin-cc/blob/main/README.md>, the others
  at each use.
- **Routers**: usage-guard, omnitrix, Quota Boss, cli-relay, Codync. **sourced**
  URLs in the routing page.
- **Multi-model**: PAL MCP `consensus`, karpathy/llm-council. **sourced** URLs
  in the routing page.
- **Other tools**: cezar <https://github.com/open-mercato/cezar/>, agentctl
  <https://github.com/OrgLoop/agentctl>, LOOP
  <https://github.com/LEO001020/codex-loop-orchestra>. **sourced**
- **Attention write-ups**, all **sourced**: Deemwar
  <https://deemwar.com/insights/every-agent-could-reach-me-so-all-of-them-did>,
  Agent Pulse
  <https://medium.com/@jainilgosalia/i-run-six-coding-agents-at-once-the-bottleneck-isnt-the-agents-it-s-me-a48c0bd27407>,
  Guangda Zhang <https://guangda.me/posts/coding-agent-fleet/>, Tmeister
  <https://tmeister.dev/posts/i-talk-to-one-agent>.

## The findings

- [Watching, and answering without acting (pain points 1 and 2)](super-agent-prior-art-watching-and-answering.md)
- [Other tasks, adoption and control (pain points 3 to 5)](super-agent-prior-art-tasks-and-control.md)
- [Needs, away mode and machines (pain points 6 to 8)](super-agent-prior-art-attention.md)
- [Routing, the review budget and a second view (pain points 9 to 11)](super-agent-prior-art-routing-and-models.md)
- [Ideas no pain point names](super-agent-prior-art-other-ideas.md)
- [What is not worth copying, and what is not verified](super-agent-prior-art-not-copied.md)
