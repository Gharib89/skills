# Prior art for the super agent: watching, and answering without acting (pain points 1 and 2)

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Pain point 1: sometimes it does not watch the threads

The skill's rule is prose: "No turn ends without a watcher running". Three
outside mechanisms move it out of prose.

### 1a. A turn-end guard (top pick)

How it works elsewhere:

- FirstMate's guard acts at the primary session's turn boundary when two things
  hold: something needs supervision, and "no identity-matched watcher has a
  fresh beacon". The beacon is a file its watcher touches every cycle. The
  harness hook must then block the turn end or force one bounded follow-up.
  **sourced**
  <https://github.com/kunchenguid/firstmate/blob/main/docs/turnend-guard.md>
- Its check is strict on purpose: "A stale beacon blocks even when a watcher pid
  is live", and a fresh beacon blocks when the lock is missing, dead or held by
  another identity. **sourced** (same page)
- A session that does not own the lock is let through with a diagnostic, because
  blocking a session that cannot repair the home "would create an unbounded
  loop". **sourced** (same page)
- On Claude Code this is "tracked Stop and StopFailure hooks for tokenless
  watcher re-arm and rewake, including API-error turn ends". **sourced**
  <https://github.com/kunchenguid/firstmate/blob/main/README.md>
- Claude Code: a `Stop` hook that exits 2 "Prevents Claude from stopping,
  continues the conversation"; `StopFailure` fires "When the turn ends due to
  an API error". **sourced** <https://code.claude.com/docs/en/hooks>
- The loop bound: "Claude Code overrides a Stop hook after it blocks eight times
  in a row with no tool call from Claude in between", and the hook input
  carries `stop_hook_active`. **sourced**
  <https://code.claude.com/docs/en/hooks-guide>
- `asyncRewake`: a hook that "runs in the background and wakes Claude on exit
  code 2", its stderr shown to the model as a system reminder. **sourced**
  <https://code.claude.com/docs/en/hooks>

Fit:

- `watch.sh` already holds a lock (a second start exits 1 `running`). Add a
  beacon touch per poll. A `Stop` hook script reads the ledger: with an open
  entry and no live lock holder with a fresh beacon, exit 2 with the one line
  that starts the watcher. **inferred**
- Scope it to the super agent thread only (the hook is user-scope and fires in
  every session): compare `T3CODE_THREAD_ID` with the thread id the ledger or a
  marker file records, and exit 0 everywhere else. FirstMate's foreign-owner
  exception is the same idea. **inferred**
- The skill already installs a `PreToolUse` hook into the Claude settings file
  (`scripts/guard.sh --install`), so the install route exists. **sourced** (this
  repo, `skills/super-agent/scripts/guard.sh`)
- Stronger variant: the hook starts the watcher itself (`asyncRewake`), so
  starting it is no longer the model's act at all. **guess**: it depends on
  whether a T3-hosted Claude session honours `Stop` blocking and `asyncRewake`
  while the thread is idle. Probe: a scratch T3 thread with a Stop hook that
  exits 2 once, and one with an `asyncRewake` hook that sleeps 60 s then exits
  2.
- Cost: one script of about 40 lines, one beacon line in `watch.sh`, a test with
  a fixture ledger, and the probe. The existing notify command stays as the
  alarm for a dead session, which no hook can cover. **inferred**

### 1b. Read the thread, not the ledger, and name the stop classes

- Fleet's Chief missed a worker that sat three hours on a folder-trust screen
  because "The Chief did read the ledger", and the ledger said `running`: that
  screen never calls a hook. **sourced**
  <https://yasmorita.com/blog/less-attention/part-2/>
- The fix, `fleet stalled`, reads each running worker's screen every five
  minutes "without using a model" and looks for four kinds: a known
  confirmation screen, a usage-limit notice, no output for 10 minutes with no
  running indicator, and "First instruction never arrived" (5 minutes after
  launch the input box is still empty). "When it can't read a screen properly,
  it decides nothing." **sourced** (same page)
- Gas Town keeps its mechanical thresholds "intentionally generous" (30 minutes
  for a stall) because "False positives (the 'Deacon murder spree' bug) are
  worse than slow detection", and leaves the stuck-or-thinking call to an agent.
  **sourced**
  <https://github.com/steveyegge/gastown/blob/main/docs/design/polecat-lifecycle-patrol.md>

Fit: `watch.sh` already has the limit stop, the waiting line and the stall
window. The two classes it lacks are a launch whose first run never started and
a permission hold, which the skill says wakes nothing. **inferred** Whether the
watcher can read a pending permission request from a script is a **guess**;
probe the T3 CLI for it. The "unreadable means decide nothing" rule is worth
stating in `watching.md` as is. Cost: small.

### 1c. Overlapping patrols that share no private state

- Gas Town runs four patrols over the same observable state (beads, git, tmux),
  so "If any single patrol agent fails, the others detect the resulting state
  degradation". "No agent maintains private state that others depend on."
  **sourced** (same Gas Town design page)
- Fleet's conclusion after adding four supervisors: "Adding a supervisor only
  moves the bottleneck to the next supervisor", and "Reducing what a supervisor
  has to notice works better than making the supervisor smarter". **sourced**
  <https://yasmorita.com/blog/less-attention/part-1/> and part 2

Fit: the skill already has three layers (watcher, hourly backstop, notify
command). Do not add a fourth agent. Borrow the audit instead: a patrol receipt,
one machine-readable line per backstop pulse saying what it found, which gives
the incident evidence ticket a record of when watching lapsed. **inferred**
Cost: a few lines in `pulse.sh`.

## Pain point 2: asked "why did you do that", it corrects instead of answering

No system read has this as a named feature. Three primitives combine into one.

### 2a. An answer-only posture enforced on effects

- Claude Code's `/btw` answers "from what's already in the conversation" with
  "No tool access", and the exchange never enters the history. **sourced**
  <https://code.claude.com/docs/en/interactive-mode>
- Cursor's Ask mode is "a read-only mode": the agent "answers questions and
  explores code without making any edits". **sourced**
  <https://cursor.com/help/ai-features/ask-mode>
- A `UserPromptSubmit` hook's stdout is added "as context that Claude can see
  and act on"; a `PreToolUse` hook can return `permissionDecision` deny with a
  reason shown to the model. **sourced** <https://code.claude.com/docs/en/hooks>
- Fleet's lesson on why the block must be on effects: a prompt rule said never
  offer a button that pushes; the Chief offered a button that pressed 1, and
  when that was blocked, a button that sent the message "1". "What the rule had
  closed off was a kind of button, not the effect of approving." **sourced**
  <https://yasmorita.com/blog/less-attention/part-3/>

Fit (**inferred** throughout):

- A `UserPromptSubmit` hook, scoped to the super agent thread, matches a short
  fixed list of question openers ("why did you", "why didn't you", "what made
  you", "explain why") and writes an answer-only flag file for the turn, plus
  one context line: answer from the ledger and the decision record, change
  nothing, offer the fix as a question.
- The existing `guard.sh` gains one branch: while the flag exists, refuse the
  mutating entry points (`ledger.sh` writes, `launch.sh`, a send into a
  supervised thread). The next prompt without a match clears the flag.
- The owner's override is one word in the same message ("and fix it"), so a
  question that is also a request still works.
- Whether `/btw` itself is reachable in a T3 thread is a **guess**; it would not
  help anyway, since it has no tools and so cannot read the ledger.
- Cost: medium. One hook entry, one guard branch, tests for the matcher. The
  risk is a false match; a short opener list keeps it rare.

### 2b. A decision record to answer from

- Batty logs every refusal to auto-merge under a categorized reason
  (`WrongStatus`, `MissingPacket`, `NoBranch`) and writes a confidence score
  per candidate: "I trust the outcome because I can audit the process."
  **sourced** (Batty)
- Gas Town's Witness ends each patrol with a "patrol receipt", a
  "Machine-readable summary of findings". **sourced** (Gas Town design page)
- Dan Mercede's supervisor keeps a running log, and a `decisions.md` it reads
  "before asking": "Each entry is settled until I change it." **sourced**
  <https://www.danmercede.com/guides/build-a-supervisor-agent>
- ryle.dev's instruction to the orchestrating session: restate every claim as
  "claim X, verified Y by doing Z". **sourced**
  <https://ryle.dev/blog/agent-fleet-lessons/>

Fit: the scripts that act for the super agent (a step-in send, a rethread, a
gate ruling, a cleanup) append one JSON line: time, key, action, the rule or
waiver that allowed it, the inputs read. A `ledger.sh why <key>` prints the
lines. The answer to "why" is then a read, not a reconstruction from context,
which is where the urge to correct comes from. **inferred** This is the "decision
log" the map lists as not yet specified; the outside evidence says every
long-running supervisor that published numbers kept one. Cost: small.

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
