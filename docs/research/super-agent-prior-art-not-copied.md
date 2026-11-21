# Prior art for the super agent: what is not worth copying, and what is not verified

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Not worth copying

- **A daemon, a database or a dashboard.** Symphony is "a long-running
  automation service"; Batty, repomon and ReverbCode are daemons with SQLite;
  Railyard keeps state in MySQL. **sourced**
  <https://github.com/openai/symphony/blob/main/SPEC.md>,
  <https://github.com/AliHamzaAzam/repomon>,
  <https://github.com/zulandar/railyard> The map rules a daemon out, and T3 is
  already the owner's screen. Their ideas are borrowed in the other pages as scripts.
- **A role hierarchy of many small agents.** A user who tried Gas Town first:
  "The Mayor would forget it was the orchestrator and start doing the work
  itself", and work "got split into far too many tickets". Its author is
  quoted as having "given up on building reusable harnesses". **sourced,
  secondary** (ryle.dev) One thread per ticket is the safe case the earlier
  research already chose.
- **Agent teams as the substrate.** They are experimental, "One team per
  session", in-process teammates are not restored on resume, the lead is
  fixed, and "In non-interactive mode ... including Agent SDK sessions, Claude
  doesn't spawn teammates". **sourced**
  <https://code.claude.com/docs/en/agent-teams> A pinned thread that must
  survive a daily handover cannot rest on that.
- **A model-judged stop condition for watching (`/goal`, a prompt Stop hook).**
  The evaluator "doesn't run commands or read files independently", is billed
  per turn, and pauses on a usage limit. **sourced**
  <https://code.claude.com/docs/en/goal> Whether a watcher is alive is a fact a
  script reads; use a command hook.
- **Codex's stop-time review gate.** It "can create a long-running Claude/Codex
  loop and may drain usage limits quickly". **sourced** (codex-plugin-cc
  README) It is the opposite of pain point 10.
- **Repeated review rounds.** Per ryle.dev, the loop feels responsible and
  was "the most expensive mistake I made". **sourced**
- **A small model that approves permission prompts.** Guangda Zhang routes
  routine prompts to a cheaper model returning APPROVE, DENY or WAIT. **sourced**
  (Guangda Zhang) The super agent cannot approve a held call at all, a peer
  message is not consent, and Fleet's ghost-text deletion shows the failure
  mode. Keep permission holds with the owner; reduce them with allow rules.
- **Reading state from terminal text.** Pane scraping is what made grey ghost
  text look like an instruction. **sourced** (Fleet part 3) T3 gives structured
  thread reads; keep to them.
- **Mid-task handoff to another vendor.** Relay and cli-relay move a running
  task across providers with a continuation brief. **sourced**
  <https://dbisina.github.io/relay/index.html>, and <https://github.com/mustikon/cli-relay>. A
  supervised thread is one worktree on one model, and T3 resumes a limit stop
  by itself (the glossary's limit stop). Borrow the skip and rest rules only.
- **Learned success-rate routing.** Quota Boss and omnitrix update a per-model
  success score from accepted results. **sourced** At a handful of threads a
  day the sample is too small to beat a fixed kind table. **inferred**
- **Worker-to-worker mail.** Gas Town and agent teams let workers message each
  other. **sourced** ADR 0020 already chose step-ins only, and a fleet user
  found that "the messages between them fill everyone's context". **sourced**
  (ryle.dev)
- **Session-scoped cron for recurring work.** Seven-day expiry and no replay of
  missed runs. **sourced** <https://code.claude.com/docs/en/scheduled-tasks>

## Not verified

- No probe was run in this research; every "fit" is a design inference. The
  four that gate a design are: whether a `Stop` hook block and an `asyncRewake`
  hook work in a T3-hosted Claude session; whether a script can read a pending
  permission request; whether T3 replays a missed schedule fire; whether the
  Codex review allowance reads apart from the general Codex quota.
- FirstMate's guard and away posture were read from its docs, not run. Its T3
  Code backend is labelled experimental, and the away daemon is refused there
  for a Codex captain. **sourced** (FirstMate README and afk skill)
- Gas Town's per-agent defaults (5 minute patrols, 15 minute stall threshold,
  2 nudges) come from a third-party docs site, not the repo, and are not used
  in this research. **sourced, secondary** <https://docs.gt.villamarket.ai/docs/agents/witness>
- The numbers in the write-ups (Batty's 258 self-heals, Fleet's 78%, LOOP's
  token reduction) are each author's own measurements, not reproduced here.
