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
  shapes"), with the `map` scratch directory below, and read only the exact
  lines you will edit. A file body you only
  need to *understand* never enters main context; only the hunk you *change*
  does.
- **Mechanics already project.** Every host read comes through a mechanic that
  returns a small JSON; there is no bare host CLI call to over-fetch with.
- **Investigate inside the worktree from the start**, so you never read a file
  in the main checkout and re-read it in the worktree to edit it.
- **Targeted test nodes during the loop; the full suite only at the local
  gate.** Re-running the whole suite every cycle is slow noise.
- **Delegate noisy verification runs.** A phase-3 verification that dumps
  volumes goes to a cheap-tier subagent, with the `verify` scratch directory
  below, returning `pass | fail` plus the failing lines. The local gate,
  `base-fresh`, `poll-pr` and `ci-wait` project their own output: run them
  inline.
- **One Run file** for the checklist and the design and plan. It survives a
  mid-run context summary; the same summary repeated across turns does not.

**Every subagent prompt names the scratch directory that subagent writes in.** A
subagent handed nowhere to write reaches for the scratchpad its own environment
block names, which is the Run file's parent, and a scratch file written there
can overwrite the checklist with no failure signal. So every prompt carries one
line naming `<scratchpad>/scratch/<role>/` as the one place that subagent writes
scratch of its own, `<role>` being its job in the run (`map`, `execute`,
`verify`, `standards`, `spec`). Edits to the repo are
separate, and go under the worktree prefix. It is a **sibling** of the Run file's
directory rather than a child, so a path a subagent invents below the one it was
given still lands clear of the record. Pass it the way you pass the model tier:
written into the prompt, every dispatch, never inferred.

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
`ship-<issue>/run.md` (`ship-<slug>/run.md` when the argument was a task
spec), in a directory of its own under the scratchpad directory the harness
names in its environment block, or under the OS temp directory when none is
named. Never inside the repo. A directory of its own because the scratchpad is
also where a subagent puts its scratch, and one that reaches for the run's own
name overwrites the record with no failure signal; every subagent you dispatch
is given the scratch directory named above instead. It holds the
ten-item checklist below and, as they form, the design and plan. It is the
**source of truth** for where the run is: it survives a mid-run summary and
depends on no tool the harness might withhold. Without it a summarized run
cannot tell which phase it was in, and skips or repeats one. The window is
managed, not scarce: the harness compacts long runs and the Run file carries
state across that boundary, so never stop, narrow a phase or suggest a new
session over context; keep working. It is the run's **record**; the harness
task list is its **display**, kept in step by the mirror rule below.

**Stamp every flip by reading the clock inside the edit command**, so the
stamp is a measurement rather than a recollection:

```sh
RUN="<scratchpad>/ship-<issue>/run.md"
stamp() {  # $1: a sed script; fails rather than recording a flip that did not happen
  sed "$1" "$RUN" > "$RUN.t" \
    && ! cmp -s "$RUN" "$RUN.t" \
    && [ "$(grep '^- \[.\] ' "$RUN.t" | grep -o 'in_progress (..:..→)' | wc -l)" -le 1 ] \
    && mv "$RUN.t" "$RUN" \
    || { rm -f "$RUN.t"; echo "stamp: no line matched, or a second phase would be open" >&2; return 1; }
}
# the wildcard in \[.\] also matches the x of a phase being re-opened
phase_open()  { stamp "s|^- \[.\] \($1 · .*\)|- [ ] \1 in_progress ($(date -u +%H:%M)→)|"; }
phase_close() { stamp "s|^- \[ \] \($1 · .*\) in_progress (\(..:..\)→)|- [x] \1 (\2→$(date -u +%H:%M))|"; }

phase_open 5      # ... run the local gate ...
phase_close 5
```

The double quotes are the whole trick: the shell expands `$(date -u +%H:%M)`
each time `phase_open` or `phase_close` runs, so the time comes from the clock
and a call site has no place to put one of its own. The rest of `stamp` guards
the three ways a flip goes missing in silence: `cmp` fails the call when the
script matched no line, rather than writing an unchanged file back; the
open-marker count, over the `in_progress (HH:MM→)` shape on checklist lines
alone so neither the plan's prose nor a profile-supplied phase label feeds it,
holds the file to the one-open-phase invariant below, so
re-running an open, or opening a second phase while one is open, fails instead
of appending a suffix nothing will close; and the redirect with `mv` stands in
for `sed -i`, whose in-place flag takes an argument on the BSD sed a macOS
machine runs. A `stamp` that fails is a phase line that is not where you think
it is: read the file before flipping again. Stamps go at the end of the line, after the `in_progress` suffix, one
range per parentheses:

```
- [ ] 5 · Local gate: ... in_progress (10:12→)   # opened
- [x] 5 · Local gate: ... (10:12→10:19)          # closed, suffix gone
```

**Every stamp has a mirror.** When you write the Run file, create its ten
items as harness tasks (`TaskCreate`, one per phase, the phase line as the
subject). A flip that landed is followed by the matching `TaskUpdate`:
`in_progress` after `phase_open`, `completed` after `phase_close` and after a
phase marked `skipped`. A `stamp` that failed leaves the task where it was.
The Run file is the record and carries the run across compaction; the task
list is the display the human watches in the terminal, the one view of
progress they read during an attended run. A harness that refuses either
task tool has answered: run on the file alone.

A phase that re-opens appends a second range,
`(08:31→09:40) (10:20→10:33)`. A close stamped earlier than its open crossed
midnight UTC; append `+1d` to it (`(23:58→00:12+1d)`) so the range still reads
left to right and the `Timing:` row needs no special case. The merge summary's
`Timing:` row is computed from these stamps, and they are the only way to see
which phase a slow run spent its hours in.

**A failed `stamp` on a file you no longer recognize is a clobbered Run file.**
Reading the file, as above, is how you find out: one that no longer holds the
ten checklist items, or carries someone else's content in their place, was
overwritten by a subagent that reached for the run's own path. Nothing checks
for that before a flip, because `stamp` has already caught it (the script
matched no line, the output is byte-identical, `cmp` fails the call), and a
read before every flip would buy the same answer at the price of a read per
flip. The recovery is what
is left, and it happens in place:

- **Rebuild the file** from what the run still holds: this transcript's stamps
  and decisions, the design and plan, and the harness task list, which is the
  file's mirror and says which phases opened and which closed.
- **Invent no range.** A closed phase whose range you cannot recover is written
  closed with no range. The phase that was running when the file went is
  re-opened at the current clock, so the file still holds exactly one
  `in_progress`. Both phases read `unverified` on the merge summary's `Timing:`
  row under the rule in [merge-gate.md](merge-gate.md), the first for the range
  it has not got and the second because the range it has starts at the rebuild.
- **Log it in the deviations log**: what stood in the file's place (which
  subagent's output, where that is identifiable), what was lost, what was
  rebuilt, and which ranges are unverified. From there it reaches the PR body
  and the merge summary.
- **Re-check the mirror** against the rebuilt file, then flip again.

Rebuild and record, in that order and every time: a Run file that can be
rebuilt does not end a run, so a fresh blank checklist and a stop are both the
wrong answer.

One item per phase, exactly one `in_progress`, each `completed` only when its
verification passed. A **small-lane** run keeps all ten and marks each
collapsed phase `completed` with `skipped (small lane)`, so the record shows a
decision, not a gap. The wording of items 2, 3, 7 and 8 comes from the profile
(`Tripwires:`, the applicable verifications, the reviewer list, the CI legs);
write it in when you create the file. Create exactly these ten:

- [ ] 0 · Isolate: preflight, read the issue, worktree (or in place) on a fresh branch off the default
- [ ] 1 · Understand: derive success, claim, apply spec precedence
- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires <from the profile>
- [ ] 3 · Verify: <applicable verifications from the profile> scoped to what changed
- [ ] 4 · Docs-sync + self-review: sync docs first, then `code-review` on the diff, auto-triage
- [ ] 5 · Local gate: base-fresh, then the repo's gate, all green
- [ ] 6 · Open PR: non-draft, Conventional-Commit title, Closes, reflect on the issue
- [ ] 7 · Reviewers: <each reviewer and its trigger from the profile> to convergence
- [ ] 8 · CI: resolve any conflict, land <legs from the profile> green
- [ ] 9 · Merge gate: hard stop for human approval (unattended: summary as PR comment, return)
