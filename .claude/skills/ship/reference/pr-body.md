# Phase 6: the PR body

## Contents

- [What the body carries](#what-the-body-carries)
- [The Summary opens with a Shape](#the-summary-opens-with-a-shape)
- [Two halves, and a mechanic reaches each](#two-halves-and-a-mechanic-reaches-each)
- [Reading the body back](#reading-the-body-back)

The body is written once at `open-pr` and rewritten a section at a time after
that, so it is the one artifact of the run a human reads without the
transcript. Phase 6 opens it; phase 7 rewrites two of its sections at exit
([review-loop.md](review-loop.md)); phase 9 reads it at the gate.

## What the body carries

The repo's template per the profile's `## PR`, filled honestly through its own
headings rather than a raw body that bypasses it; with no template, a plain
body. Every variant carries:

- **`Closes #<issue>` on its own line above the first `## ` heading.** The
  mechanic translates it for the host, and puts it there itself when the body
  arrives without one. Above the first heading is where no section rewrite
  reaches it.
- **A `Deviations from plan` section**: the phase-2 log verbatim, `None` only if
  the plan held. Phase 7 rewrites it where the rounds grew the log.
- **A `## Verification` section**: one line per applicable verification, read
  from the phase-3 results in the merge summary's `Verification` row format, or
  `None applicable: <reason>` where none applied. There are three such reasons
  and no fourth: `class docs` and `small lane` skip the phase; a full-lane
  change where no `Applies when:` line matches is the third, and a profile
  listing zero verifications is that case. [merge-gate.md](merge-gate.md) reads
  the same result into the summary, so the two agree by construction.
- **A `## Review` section**, one placeholder line per reviewer at open, filled
  at phase-7 exit with that reviewer's exit word.
- **The attribution footer**, where the environment provides one for pull
  request descriptions. It belongs to **the body file `open-pr` is handed**, and
  the body **ends** with it, under a `## ` heading of its own that ship adds
  where no template carries one (`## Attribution`), placed after every section a
  later phase rewrites. That placement is the whole rule, and
  [update-pr-body](../scripts/update-pr-body.sh) carries why it is the one that
  survives. The footer's lines are the environment's; ship says where they sit.

## The Summary opens with a Shape

Draw it from the diff at phase 6, not from phase 2's design; a redraw is not a
deviation. It is the first thing under `## Summary`, above the prose, and where
no template gives that heading the plain body opens with it instead.

It is a `diff` fence over a call tree, file tree, control flow, pseudocode or
component tree. Text forms only, which rules out mermaid and HTML: Azure DevOps
renders neither, and the `diff` fence is the one form that shows the before and
the after in a single view. One shape, about 15 lines or fewer; a change that
needs two is a PR spanning two concerns. Every node is a real symbol, each
tree's root node carries its file path, and no line carries a line number: the
first review-round push rots them and nothing rewrites the Summary.

A change that moves no logic and no layout (a rename, a constant, a config
value, docs alone) opens with the visible line
`Shape: none, mechanical (<kind>).` instead, so the self-review and the reviewer
can dispute the call. The small lane takes no exemption: a one-line behaviour
fix is where four lines of control-flow diff pay for themselves. `show-me`
supplies the form; these constraints are ship's, and its menu of other uses is
not.

## Two halves, and a mechanic reaches each

`update-pr-body <pr> --section <name> --body-file <path>` replaces one section.
`--preamble` replaces everything above the first heading, where the closing line
sits and, where no template gives `## Summary`, where the Shape sits. A body
with no heading at all is preamble entire, so a `--preamble` write replaces the
whole of it. A preamble write carries the old closing line over when the new
content lacks one, so the link to the issue survives the rewrite. Each
`--body-file` holds the section's content and not its heading, per
[review-loop.md](review-loop.md).

## Reading the body back

**Every title or body write to an open PR ends with `read-pr <pr>`.** After a
body write, check the `## ` headings of the body it returns against the ones the
body is supposed to carry: a section the rewrite swallowed is missing from them,
and that is the only place a swallowed `## Attribution` shows while the PR is
still open. `update-pr-body` answers with a `sections` list, which is that same
check one write earlier. Read the headings the way the slice does, fence-aware:
the fence trap is a Shape fence over a markdown change carrying `## ` lines of
its own, which are example text and not sections.
