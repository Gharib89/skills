# Owner rulings lapse, and lasting preferences live where a script reads them

A ledger ruling lapses a week after it is dated unless the owner pins it, and a preference meant to last (a per-repo cap, a reviewer order, the work week) moves to the fleet file or the repo's ship profile, where a script reads it. On 2026-11-18 the live ledger held 91 rulings, 88 of them unscoped, including contradictions ("launch on the second Claude account" beside "that account is gone"; "one ship at a time across all repos" beside the 3-per-repo cap), and since ADR 0020 no ruling reaches a run, so an unexpired ruling only steers the super agent's own judgement, and a stale one steers it wrong.

## Considered Options

- **Keep every ruling, add an expiry field only (rejected):** a lasting preference would still depend on the super agent remembering to apply prose, which the November sessions show it does not do reliably.
- **Purge all rulings at once (rejected):** loses the few that still hold before they have a home in the fleet file or a profile.

## Consequences

- This amends ADR 0020's "Rulings about the super agent stay in the ledger": they stay only until they lapse or move.
