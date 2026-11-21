# Prior art for the super agent: other tasks, adoption and control (pain points 3 to 5)

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Pain point 3: tasks other than shipping, and recurring checks

### 3a. Task shapes with a declared result

- FirstMate has two shapes: "ship tasks deliver authorized changes; scout tasks
  leave standalone investigation reports", the report at a fixed path, then a
  "decision inventory" and a relay of findings. **sourced** (FirstMate README)
- cezar defines a workflow as agent steps plus shell checks in YAML, with a
  named runner per step. **sourced** <https://github.com/open-mercato/cezar/>

Fit: the skill's `task` kind exists. Borrow only the contract: each kind names
its result (a file, a PR, a comment) and the short relay the owner gets, which
the map already agreed ("every non-ticket task relays a short result").
**inferred** Cost: small.

### 3b. Recurring checks that speak only on a change

- FirstMate lets an operator register a custom check the bash watcher runs; its
  output is an actionable wake, a check cut off at a timeout reports "timed
  out", and the turn-end guard counts a registered check as supervision need.
  The watcher costs no tokens while nothing changes. **sourced**
  <https://github.com/kunchenguid/firstmate/blob/main/docs/architecture.md>
- Codex scheduled tasks: "Scheduled task runs with findings appear" in an inbox
  with an unread mark, and a durable prompt should say "how to decide whether
  there is anything important to report, and when to stop or ask you for
  input". A task can run standalone (fresh chat per run) or inside a chat
  (keeps context). **sourced** <https://learn.chatgpt.com/docs/automations>
- Runs with nothing to report archive themselves. **sourced, secondary**
  <https://codex.danielvaughan.com/2026/03/27/codex-cli-automations-scheduled-tasks/>
- Fleet's patrol runs every 30 minutes and "either answers 'all clear' or turns
  a single find into a card", and only counts a find that "doesn't show up on
  any other screen". **sourced** (Fleet part 2)
- Scheduled jobs fail silently: "my vault sync timer ... failed more than once,
  and nothing screamed about it". **sourced**
  <https://tmeister.dev/posts/i-talk-to-one-agent>
- Claude Code's session-scoped recurring tasks "expire 7 days after creation",
  run late by up to 30 minutes, and a restored task "doesn't fire for the runs
  it missed". **sourced** <https://code.claude.com/docs/en/scheduled-tasks>

Fit: two kinds of recurring entry. **inferred**

- A scripted check: a ledger entry of kind `check` with a command, an interval
  and the hash of its last output. `watch.sh` runs it on the interval and exits
  (wakes the model) only when the hash changes, the command fails, or a run is
  overdue. Zero tokens while nothing changes. This is the map's "first-class
  entry that reports only on a change".
- A judged check (a metric that needs reading): a T3 schedule bound to a task
  thread whose prompt ends on a fixed no-change line, which reconcile reads as
  silence.
- Both need the overdue rule: a check that did not run is itself an event.
- Do not build either on session-scoped cron, for the expiry and missed-run
  reasons above. Whether T3's own schedules replay a missed fire is a **guess**;
  probe it by stopping the app across a fire time.
- Cost: medium. A ledger kind, a watcher branch, a status row, tests.

## Pain point 4: babysit a thread started earlier

- agentctl "reads native sources" and "never replicates state", tracking only
  launch metadata, so a session it did not start is as visible as one it did.
  **sourced** <https://github.com/OrgLoop/agentctl>
- Gas Town calls the same idea "discover, don't track". **sourced** (design page)
- Claude Code can subscribe to another session's next idle with
  `notify_when_idle` "without starting a turn or spending tokens in the watched
  session"; it fires once, lapses after 12 hours, and works only on the same
  machine. **sourced** <https://code.claude.com/docs/en/cross-session-messaging>

Fit: `ledger.sh adopt` already exists. The borrowable part is discovery: list
the T3 threads the ledger does not hold and offer them, so "babysit that one"
needs no thread id from the owner; and baseline from the thread's state now,
which reconcile already does on `record`. **inferred** Cost: small.

## Pain point 5: take control of a thread it started

- In Claude Code agent teams the human "can message any teammate directly"; a
  shutdown is a request the teammate "can approve ... or reject with an
  explanation". **sourced** <https://code.claude.com/docs/en/agent-teams>
- A message to a busy Claude session is read between tool calls, so a running
  tool is never interrupted. `codex queue` waits for the turn to end on a busy
  thread; Steer adds to the running turn. **sourced, secondary** (Dan Mercede's
  guide, citing both vendors' docs)
- Dan Mercede's standing rules: "never interrupt a thread that's working", and
  queue a pointer to the log, not the content, because four queued messages
  were stale by the time they were read. **sourced** (same guide)
- A peer session's message "never counts as your consent, so it can't answer a
  pending permission prompt on your behalf". **sourced**
  <https://code.claude.com/docs/en/cross-session-messaging>
- Fleet's Chief may act on a pane only through a proposal the owner taps, and
  each proposal is checked in code for its effect, twice. **sourced** (Fleet
  part 3)

Fit: today the super agent speaks to a supervised thread at five step-ins (ADR
0020). "Take control" is a sixth, owner-named moment: a redirect, with a
recorded reason. Make it a script (`take <key> --say <text>`, optionally with
an interrupt first) that appends to the decision record, so control is an
explicit, logged act and never a drift from a nudge. The consent limit stands:
it can redirect, it cannot approve a held call. **inferred** Cost: small.
