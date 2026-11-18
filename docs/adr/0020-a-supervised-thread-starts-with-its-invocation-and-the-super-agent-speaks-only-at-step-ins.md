# A supervised thread starts with its invocation, and the super agent speaks only at step-ins

A supervised thread's launch message is its owner-skill invocation (`/ship <n>`, `/triage <n>`) plus one `Note:` line only when the owner gave one for that ticket (a `/triage` message also carries one contract line, see Consequences). Until this decision the super agent sent a launch brief after the invocation: measured with `brief.sh` against the live fleet and ledger for Gharib89/skills, 19 lines of merge allowance, standing waivers, gate-hold and ruling lines, shared-machine rules, seven owner rulings (two about the super agent itself, three for crm PRs only, two restating a Codex rule this repo's ship profile already holds) and the watcher's output contract. Most of it either repeated what the skill or profile already enforced or applied to a moment the run might never reach, and every rung-2 stall resent all of it. So each rule now lives where the run reads it anyway, and the super agent posts only when a thread reaches the situation a message answers.

## Considered Options

- **The up-front brief (rejected):** no round trip at a gate hold, since the run knows every waiver in advance. It cost every thread the full text, grew with every ruling marked brief-bound, and could disagree with the repo's own profile.
- **A short fixed contract (rejected):** only the lines the watcher parses. Those lines are ship's output contract, true for a hand-started run as well, so they belong in ship.

## Consequences

- Ship's SKILL.md carries the waiting line, staying on the worktree's branch, ending on the PR URL and gate state, and acting on a ruling that arrives after its gate stop.
- Each repo's ship profile decides merge-on-clean and carries ship-behaviour rulings (when a reviewer is requested). Rulings about the super agent stay in the ledger; gate-hold rulings and the standing waivers stay with the super agent, which cites the one that matches at the hold.
- The shared-machine rules (stop only your own PIDs, the per-repo lock, the memory cap) are global rules every session loads.
- A step-in happens at exactly five moments: the stall 1 nudge, the stall 2 missing fact, a gate hold, the owner's answer to a need the thread raised, and a hard finding from verification. Nothing is broadcast to running threads. A thread that merges on a waiver names the waiver in its PR body.
- `brief.sh` is deleted, and `ledger ruling --brief` with the fleet's `repos.<r>.brief` and `machines.<m>.brief` lines follows it (#1268), so nothing can ride the launch message again by accident. A ruling's `--repo` scope stays, so the gate-hold step-in can find the ruling for its repo.
- A `/triage` launch message carries one contract line after the invocation (and before any `Note:`), asking the run to end a turn that only waits on its own background work on the waiting line and to keep its final message the triage outcome. The triage skill is upstream (`mattpocock/skills`), so no `SKILL.md` this repo owns can carry the contract, and the watcher would otherwise read a resting triage run as a stall. A `/ship` message stays the invocation alone. The line is built from `sa_waiting_line` (#1270).
- Ship's slice lands before the super agent's, so no run stops hearing the waiting line before ship tells it.
