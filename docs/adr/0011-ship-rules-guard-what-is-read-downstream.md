---
status: accepted
---

# Ship's rules guard what is read downstream, and judgment takes the rest

Before launch, Ship's prose carried hundreds of musts, refusals and fixed formats, written for agents that needed every step spelled out. A rule audit in the #666 triage grilling grouped them by what each one guards. About half guarded only themselves: `run-file close 4` refusing until Near-miss, Dropped and Probe lines existed, a PR body's sentence and bullet counts, a 30-row summary layout, retry counts, model tiers, announcements. No script, gate, merge or later run read their result, yet they produced stops, refusals and a steady stream of issues.

So a rule in Ship stays only where something downstream reads its result or the action cannot be undone: the claim and admission, the grade and PR title, the merge's authorization and order, the review loop's stops, the local gate, CI waits, unmet criteria and waivers, Verifications and head coverage, tracker drafts after the merge, composed-skill pins, the unattended lane, the inline lane's 20-line cap, gating calls (0010), and the PR body's `Closes` line, template headings and attribution order. Everything else is a default the agent applies with judgment: what a section says and how long it is, how the merge summary is laid out, when to stop retrying, how to split work among subagents, how deep a self-review probes. A new rule must name the reader that needs it.

## Considered options

- Keep the full rule set: stable only in the sense of being predictable, and each rule that guards nothing costs a stop or an issue when a run meets a case it did not foresee.
- Loosen everything, guard rules included: an unmet criterion or an unreviewed head could reach an irreversible merge.
- Keep the rules a reader depends on (chosen).
