# The gap report: a re-run on an existing harness

## Contents

- [Dispositions](#dispositions)
- [Files the skill wrote](#files-the-skill-wrote)
- [Pins](#pins)
- [Deleted pieces and standing choices](#deleted-pieces-and-standing-choices)
- [Timing on a re-run](#timing-on-a-re-run)
- [The report](#the-report)

A run that finds `docs/agents/harness.md` is a re-run. Explore runs in full, as on a first run, and what it finds is compared with what the harness already has: each difference is a **gap**, the report lists them, and the run writes only the gaps the human approves. Every re-run ends in the confirm step, or in `harness: no gaps`.

## Dispositions

Each gap kind takes exactly one disposition:

- **Write**: a row in the proposed-writes table, applied on the one approval; droppable by number unless the row says otherwise.
- **Offer**: a numbered question with a recommendation, asked before the table; its answer adds, changes or removes rows.
- **Install-check row**: a row in the same table carrying the install-check columns ([install-check.md](install-check.md) `## Presenting`), the unit passing the install check before the row is shown.
- **Report only**: listed under Not acted on or Standing choices; nothing is written.

| Gap | Disposition |
|---|---|
| The profile's `Schema:` trails the skill's `metadata.harness-schema` | Write: the migration, row 1, undroppable |
| A piece the skill writes is missing: `scripts/check.sh`, `.claude/hooks/check-hook.sh`, a hook entry, the cloud setup or its `SessionStart` entry (cloud-first only), a vendored language server, the `CLAUDE.md` block | Write |
| A file the skill wrote lacks what its current template says | Write |
| A step the skill wrote whose evidence is gone (a `TURN_ROWS` row for a removed member, a runner hook for a file kind no longer tracked, a cloud setup step for a removed stack) | Write: the removal |
| A hook `timeout` off deadline plus max(10 s, deadline / 4) | Write |
| A new root whose stack has a catalog entry | Write: its `TURN_ROWS` row and runner additions |
| A now-available role: a role with no tool that its catalog entry now fills, or a `Constraints:` `Unavailable:` that no longer holds | Write |
| `check.sh` breaks its contract, and no Write above explains it | Offer: rewrite onto the current template, keeping every check the old file ran |
| A warm `edit` or `turn` time over budget | Offer: narrow, demote or override ([check-ladder.md](check-ladder.md) `## Timing the rungs`) |
| A new candidate ([detection.md](detection.md)) | Offer |
| `cloud: unproven`, or `unproven (changed since <sha>)`, on a cloud-first repo | Offer: the proof ([cloud.md](cloud.md) `## The proof`) |
| A broken pin | Offer: re-pin or remove |
| Evidence gone from an evidence-backed `Local-only:` line | Offer: set it up for the cloud (recommended), or keep it as `operator's choice: <why>` |
| A third-party unit a Write above adds or re-pins (the Write keeps its own row), and a pin that is behind | Install-check row |
| Unclaimed extensions and stacks, unwired tools, Found-not-installed units | Report only |
| Standing choices | Report only |

Not gaps: a line the repo added to a file the skill wrote (kept); a red check during timing (`<rung>: fail (<check>)`); a skill pin in `skills-lock.json` (tier 3, never proposed: that bump is `update-skills`'); a profile `Schema:` ahead of the skill, which stops the run at step 2.

## Files the skill wrote

`scripts/check.sh`, `.claude/hooks/check-hook.sh`, `.claude/hooks/cloud-setup.sh`, the hook entries in `.claude/settings.json`, a vendored plugin and the `CLAUDE.md` block are each compared whole with the current template **by what they say**: there is no version stamp and no old template to diff against. What the template says outside a configuration block and the copy lacks is a Write that restores it in place; the configuration block is compared with the block Explore would fill now. A line the repo added is kept, in the Write's proposed text too. A line the repo reworded to the same effect is no gap.

`scripts/check.sh` is also run against its contract, the cold timing run of `edit`, `turn` and `full` going through this skill's `scripts/check-contract.sh scripts/check.sh <rung> [<file>...]` (commit is the runner's own hook, with no `check.sh` subcommand): it prints the entry point's own JSON line when the contract holds, one line per violation (exit 1) when it does not, and exits 2 when the entry point answered no line with exit 2, which is the repo's tooling failing, not the contract. A violation that a Write from the comparison explains (the JSON `printf` deleted) is that Write. Any other (a repo-added check echoing to stdout, an exit code off its verdict) is the Offer: the current template with a configuration block that runs every check the old file ran, the repo's own additions moved into `TURN_ROWS` or `FULL_ROWS`. Either way the rung's budget verdict is `not judged: contract` until the rewrite lands.

## Pins

Every pin the harness carries is read: runner config `rev`s, the dev dependency pins of catalog tools, versions in launch and install commands, vendored plugin SHAs, direct downloads.

- **Broken**: the version is yanked or gone from its registry, its SHA is not reachable from the tag it names, its provenance or checksum fails, or its publisher no longer matches the catalog `Publisher:`. Offer: re-pin to the newest version passing the install check, or remove the tool when no version passes. Keeping it is not an option.
- **Behind**: `scripts/pick-version.sh` (for a hook repo, the newest tag at least 7 days old) picks a newer version than the pin. Install-check row, droppable, showing old and new. Skipped for an ecosystem the repo's Renovate config (`renovate.json`, `.renovaterc*`, `.github/renovate.json*`) or `.github/dependabot.yml` already updates.
- **Tier 3**: skill pins are never proposed.

## Deleted pieces and standing choices

A missing piece is proposed again every run, until the human drops its row with a reason and step 5 records it `Declined:`; that line stops the proposal, and removing it re-opens it.

**Standing choices** are listed and never re-asked: every `Declined:`, every `Local-only:` whose reason is `operator's choice`, budget overrides, the `Verdict:` and `Allowlist:`. A `Local-only:` line whose reason names a file, target or host is re-checked against the repo; when that evidence is gone it is the Offer above, and "keep" rewrites its reason to `operator's choice: <why>`.

## Timing on a re-run

Every rung is timed in Explore, before the report, as [check-ladder.md](check-ladder.md) `## Timing the rungs` says, the cold run of `edit`, `turn` and `full` through `check-contract.sh`. Timing is read-only: fix mode on a clean file writes nothing. A rung that fails is the repo's code: `<rung>: fail (<check>)` with its time "not judged", and no gap or offer follows from it.

After the writes, in place of step 6's first timing, every rung the batch touched is timed again: a `check.sh` configuration change re-times the rungs whose rows changed, `check-hook.sh` or a hook entry the rung it runs, a runner config change `edit`, commit and `full`. A write to a file the proof covers turns a standing `Proof: <sha>` into `cloud: unproven (changed since <sha>)`, and the proof is offered again.

## The report

Step 4's message on a re-run, in this order:

1. **Header**: skill version, `Schema: N` (and "migrates to M" when it trails), the Claude Code floor against the installed version, the step-1 warnings.
2. **Offers**, numbered, each with its recommendation.
3. **Proposed writes**: one table, `| # | Gap | Path | Now | Proposed |`, with the install-check columns filled on unit rows and each unit's glue in full after it; the migration is row 1, marked undroppable.
4. **Budgets**: rung, cold, warm, budget, verdict.
5. **Not acted on.**
6. **Standing choices**, with the cloud state.

With no gaps: `harness: no gaps`, then the budgets table and the standing choices. Nothing is written, and the run ends after this message.
