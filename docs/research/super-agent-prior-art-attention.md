# Prior art for the super agent: needs, away mode and machines (pain points 6 to 8)

Part of [the prior-art research for issue #1312](super-agent-prior-art.md),
which holds the ranked summary and the list of systems read. Each claim carries
its basis: **sourced** (read at the URL given; "secondary" when a third party
describes someone else's system), **inferred** (reasoning from sourced facts
and the skill's own files) or **guess** (not checked, with the probe named).
A source named without a URL here has its URL in the index's "Systems read".

## Pain point 6: clearer communication, and clear when it needs the owner

- Group by attention state, not by session: "Needs attention", "Working",
  "Idle", "Stale". "In practice this is the only group I look at." **sourced**
  <https://medium.com/@jainilgosalia/i-run-six-coding-agents-at-once-the-bottleneck-isnt-the-agents-it-s-me-a48c0bd27407>
- A needs-you section reserved for genuine questions: "It's usually empty, and
  that's the point; when something shows up there, it's real". **sourced**
  <https://guangda.me/posts/coding-agent-fleet/>
- A decision card carries "the check results, the blast radius and the agent's
  recommendation", answered Yes or No. **sourced** (Fleet part 1)
- Identical questions are batched: "If five agents ask the same thing, I answer
  once and the answer reaches all five." **sourced** (Fleet part 2)
- An ask line carries who, an id, the question, what the answer needs, and
  "whether the worker is blocked"; the supervisor answers most asks itself and
  batches the owner's "into one structured question". **sourced** (Dan Mercede)
- Stale escalations crowd out real ones: Batty's digest "kept top-billing
  escalations whose underlying tasks had already moved to done", fixed by a
  function that demotes them. **sourced** (Batty)
- Report a dead thing once: FirstMate found two finished lanes with 226 and 203
  consecutive escalations, "which is what drowns the alarms that matter".
  **sourced** (FirstMate architecture)
- Put the conclusion first: what changed, why, the impact, the risk; logs go in
  a collapsed section. **sourced**
  <https://yasmorita.com/blog/less-attention/part-4/>

Fit: the status block already has `Needs you` first, and a need already names
one action. Borrow four fields and one rule, all in `ledger.sh need` and
`status.sh`: `blocking` (yes or no), the need's age in the row, the
recommendation as its own field, a dedupe key so the same question from three
threads prints once, and a reconcile rule that demotes a need whose cause is
gone. **inferred** Cost: small to medium.

## Pain point 7: less verbosity while the owner is away

- FirstMate's away mode "is a POSTURE of the one supervision session". "The
  posture is a file ... written only by `bin/fm-afk-contract.sh` in the same
  turn as `/afk`; nothing infers the posture from chat." **sourced**
  <https://github.com/kunchenguid/firstmate/blob/main/.agents/skills/afk/SKILL.md>
- "It never changes the authority set." Being away changes two things: how the
  owner is informed, and what happens at an owner-owned decision (hold for
  return). Destructive, irreversible and security-sensitive actions "are never
  pre-authorizable whatever the words say". **sourced** (same file)
- The entry records an expected return and a spend cap, and the first unmarked
  message while away renders "the return brief". **sourced** (same file)
- A second posture, `/quiet`: "Keep routine wakes off main while staying and
  chatting". **sourced** (FirstMate README)
- A user's summary of the same system: "Away mode never adds powers, it only
  holds things", and outside it he hears about three things only: decisions
  only he can make, failures, and work ready for review. **sourced** (Tmeister)
- One egress: "no autonomous process messages the human directly"; one notifier
  collects, deduplicates, drops the routine, and emits "at most one
  consolidated digest on a real change. The default is silence." "Deduplicate
  at the throttle, not at the source." **sourced**
  <https://deemwar.com/insights/every-agent-could-reach-me-so-all-of-them-did>
- Alertmanager's three verbs for the same job: grouping "categorizes alerts of
  similar nature into a single notification", inhibition suppresses some alerts
  "if certain other alerts are already firing", silences "mute alerts for a
  given time". **sourced** <https://prometheus.io/docs/alerting/latest/alertmanager/>
- A safety property: away mode "can never leave an agent more stuck than it
  would have been without it". **sourced** (Agent Pulse)

Fit (**inferred**): the map already agreed "away" is an explicit switch with
the work week as fallback. Borrow the shape exactly.

- `away.sh on [--until <time>] | off` writes one file in the state directory.
  The work week in the fleet file is the fallback read by the same function.
- `status.sh` and `pulse.sh` read it: while away, a wake posts no block and
  pushes only a new `blocking` need; everything else accumulates.
- The owner's first message while the file exists gets the return brief: one
  digest of what merged, what waits on them and what was held. A
  `UserPromptSubmit` hook can inject the instruction, so the brief does not
  depend on the model remembering.
- Away changes reporting and holds; it grants nothing. State that in the skill
  in FirstMate's words.
- The quiet posture (present, routine wakes off) is the same file with a mode
  field, and nearly free once away exists.
- Cost: medium. One script, changes in two scripts, one hook entry. The look of
  the digest is the prototype the map already lists.

## Pain point 8: know the machines and check them over SSH

Prior art is thin here; most systems treat a remote machine as another place
to run agents, not as something to inspect.

- FirstMate's remote "secondmates" run on "another SSH-reachable host", with
  "recovery that never turns an unavailable remote route into a local
  replacement". **sourced** (FirstMate README)
- ryle.dev uses "a deterministic check of which image each pod is actually
  running as a floor the model can't override". **sourced** (ryle.dev)
- Tmeister reaches three machines over one private network, nothing open to the
  internet. **sourced** (Tmeister)

Fit: a `machine-check.sh <key>` that runs a fixed, read-only command list over
SSH (uptime, disk, memory, GPU, the agent CLIs' versions, the T3 service state)
and prints JSON, with hosts from the fleet file. The two borrowed rules: an
unreachable machine is reported as unreachable and never substituted, and the
command list is fixed in the script so "read-only" is a property of the script,
not of the model's restraint. **inferred** Cost: small, plus the fleet file
gaining a host per machine.
