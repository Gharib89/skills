# Context discipline: a ship run is long; protect the main thread

A full ship touches many files across many turns. What bloats the window is raw
tool output landing in the main thread, not the work itself, so spend tokens on
decisions, not dumps.

**The delegation rule: delegate noise, not size.** A subagent earns its cost
only when the raw output you would otherwise ingest is much larger than the
conclusion you need: a multi-file map, a verification run, CI logs. When you
can already point at the target (one or two known files, a single test node,
one mechanic's projected JSON) work inline; a subagent there costs more than it
saves. A small-lane run typically spawns none of its own; a large or unfamiliar
change may spawn several. The rule is a lever, never a dependency: a session
with no subagent tools runs everything inline and is still a complete run.
Every lever below is subject to it, in rough order of impact:

- **Delegate reading, not just review.** Send the investigation to a cheap-tier
  subagent ("map how X, Y, Z connect; return signatures, call sites and data
  shapes") and read only the exact lines you will edit. A file body you only
  need to *understand* never enters main context; only the hunk you *change*
  does.
- **Mechanics already project.** Every host read comes through a mechanic that
  returns a small JSON; there is no bare host CLI call to over-fetch with.
- **Investigate inside the worktree from the start**, so you never read a file
  in the main checkout and re-read it in the worktree to edit it.
- **Targeted test nodes during the loop; the full suite only at the local
  gate.** Re-running the whole suite every cycle is slow noise.
- **Delegate noisy verification runs.** A phase-3 verification that dumps
  volumes goes to a cheap-tier subagent returning `pass | fail` plus the
  failing lines. The local gate, `base-fresh`, `poll-pr` and `ci-wait` project
  their own output: run them inline.
- **One Run file** for the checklist and the design and plan. It survives a
  mid-run context summary; the same summary repeated across turns does not.

## While a subagent is out, end the turn

Dispatch a composed skill's subagents, then **end the turn**. The completion
notification is what resumes the run, and it arrives on its own: every call
spent asking whether the result is ready yet (a poll loop, a sleep, a status
ping, an agent listing, a read of the output file) buys nothing the
notification does not deliver.

A turn that ends with work dispatched has already acted: this is the one place
where having nothing to do is the correct next action.

## First action: the Run file

**Before phase 0, before the worktree**, write the **Run file**:
`ship-<issue>.md` (`ship-<slug>.md` when the argument was a task spec) in the
scratchpad directory the harness names in its environment block, or the OS
temp directory when none is named. Never inside the repo. It holds the
ten-item checklist below and, as they form, the design and plan. It is the
**source of truth** for where the run is: it survives a mid-run summary and
depends on no tool the harness might withhold. Without it a summarized run
cannot tell which phase it was in, and skips or repeats one. The window is
managed, not scarce: the harness compacts long runs and the Run file carries
state across that boundary, so never stop, narrow a phase or suggest a new
session over context; keep working. It is the run's only checklist: a second
copy of it anywhere else is bookkeeping that buys nothing.

**Stamp every flip by reading the clock inside the edit command**, so the
stamp is a measurement rather than a recollection:

```sh
RUN=<scratchpad>/ship-<issue>.md
# open phase 5; the `[.]` also picks up the `[x]` of a phase being re-opened
sed "s|^- \[.\] \(5 · .*\)|- [ ] \1 in_progress ($(date -u +%H:%M)→)|" "$RUN" > "$RUN.t" && mv "$RUN.t" "$RUN"
# close it
sed "s|^- \[ \] \(5 · .*\) in_progress (\(..:..\)→)|- [x] \1 (\2→$(date -u +%H:%M))|" "$RUN" > "$RUN.t" && mv "$RUN.t" "$RUN"
```

The double quotes are the whole trick: the shell expands `$(date -u +%H:%M)`
as it runs the command, so the file can only ever hold a time this run passed
through. The redirect and `mv` stand in for `sed -i`, whose in-place flag takes
an argument on the BSD sed a macOS machine runs. Stamps go at the end of the line, after the `in_progress` suffix, one
range per parentheses:

```
- [ ] 5 · Local gate: ... in_progress (10:12→)   # opened
- [x] 5 · Local gate: ... (10:12→10:19)          # closed, suffix gone
```

A phase that re-opens appends a second range,
`(08:31→09:40) (10:20→10:33)`. A close stamped earlier than its open crossed
midnight UTC; append `+1d` to it (`(23:58→00:12+1d)`) so the range still reads
left to right and the `Timing:` row needs no special case. The merge summary's
`Timing:` row is computed from these stamps, and they are the only way to see
which phase a slow run spent its hours in.

One item per phase, exactly one `in_progress`, each `completed` only when its
verification passed. A **small-lane** run keeps all ten and marks each
collapsed phase `completed` with `skipped (small lane)`, so the record shows a
decision, not a gap. The wording of items 2, 3, 7 and 8 comes from the profile
(`Tripwires:`, the applicable verifications, the reviewer list, the CI legs);
write it in when you create the file. Create exactly these ten:

- [ ] 0 · Isolate: preflight, worktree (or in place) on a fresh branch off the default
- [ ] 1 · Understand: read the issue, derive success, claim, apply spec precedence
- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires <from the profile>
- [ ] 3 · Verify: <applicable verifications from the profile> scoped to what changed
- [ ] 4 · Docs-sync + self-review: sync docs first, then `code-review` on the diff, auto-triage
- [ ] 5 · Local gate: base-fresh, then the repo's gate, all green
- [ ] 6 · Open PR: non-draft, Conventional-Commit title, Closes, reflect on the issue
- [ ] 7 · Reviewers: <each reviewer and its trigger from the profile> to convergence
- [ ] 8 · CI: resolve any conflict, land <legs from the profile> green
- [ ] 9 · Merge gate: hard stop for human approval (unattended: summary as PR comment, return)
