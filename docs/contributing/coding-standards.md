# Coding standards

The standards every change in this repo is reviewed against. The `code-review`
skill's Standards axis and every automated reviewer read this file; the ship
profile names it under `## Coding standards`. This file is the index: read the
reviewer section below whole, then the sub-file each area of your diff routes
to, and only those.

This repo ships bash and Markdown. Every file in it is read by an agent, so
prose is the product as much as the scripts are. **The source is `skills/`,
and `.claude/skills/` carries install output alone:** a change lands in
`skills/<name>/` and reaches `.claude/skills/` only through
`npx skills add . --skill <name> --agent claude-code -y`. **`.claude/skills/`
is exempt from every rule here but the `derived-copies` gate**, which holds the
copy of each skill this repo writes byte-identical to its source. The rest is
install output from other people's repos and is refreshed rather than edited, so
its prose and its em dashes are not this repo's to fix.

## Reviewer section

Every Reviewer reads this section, and so does the author self-reviewing.

**A finding needs its evidence.**

- **A claim about external behaviour cites a probe or a doc.** How a tool, an
  API or a format behaves (a `gh` flag, an Azure DevOps response, a CommonMark
  rule, a semantic-release option) is a finding only beside the exact command
  you ran and its output, or a link to the current doc. Without either, phrase
  it as a question; the author answers a question with one probe, where a wrong
  finding costs a rebuttal round.
- **A ShellCheck finding names its code and severity** (`SC2086`, `warning`),
  since the gates fail at `warning` and above outside the landed scripts, so a
  `style` or `info` finding there is no failure. Whether a gate failed is the
  Local gate's JSON verdict to settle, never a reading of the diff: on a green
  head, a gate failure is not a finding.
- **A finding cites the rule by its bold lead.** The lead survives the next edit
  to the file; a line number or a paraphrase does not.
- **A finding anchors on `skills/<name>/`, never on `.claude/skills/<name>/`.**
  The derived copy is byte-identical by gate, so one defect is one thread.

**What the rules cover.** These are the scope facts reviewers most often got
wrong; each sub-file's rule holds inside them.

- **Portability scope.** The Bash 3.2 rule in shell.md binds `skills/` alone,
  because only it reaches consumer machines. Scripts under `scripts/` and
  `tests/` run in this repo alone and may require Bash 4, behind a version
  guard; they are not held to consumer portability.
- **Quoting exceptions.** Bash never word-splits or globs the right side of an
  assignment (`x=$y`, `local x=$1`), the word of a `case`, or an operand inside
  `[[ ]]` other than the right side of `=`, `==`, `!=` and `=~`, where an
  unquoted expansion is a pattern. An unquoted expansion in these places is not
  a finding.
- **The clock exception.** An elapsed-time bound proving a watchdog or timeout
  fired may read the real clock: its result does not depend on the time of day.
  The stub rule binds only results that do.
- **Split code spans.** An inline code span broken across a line wrap in
  hard-wrapped prose is house style, not a rendering defect.

## Routing by path

Always read [standards/gates.md](standards/gates.md), what the Local gate and
the CI leg already enforce, and [standards/release.md](standards/release.md),
the version grade, the PR title and body, commits, and adding a skill this repo
writes. Then read each file below whose condition a path in the diff meets:

- A diff touching a shell script (`*.sh`, or a shell block in a workflow):
  [standards/shell.md](standards/shell.md), the mechanic contract and its
  header, Bash 3.2, traps, host calls, quoting, failed reads and matching.
- A diff touching `tests/` or a `*.test.sh`:
  [standards/tests.md](standards/tests.md), proving a test, fixtures, fakes and
  stubs.
- A diff touching Markdown (`*.md`: a skill's prose, a template, the glossary,
  an ADR, a doc): [standards/prose.md](standards/prose.md), self-contained
  skills, runnable recipes, vocabulary, claims and rule-shaped changes.
