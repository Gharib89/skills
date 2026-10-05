# Standards: prose

Read by a diff touching Markdown: a skill's `SKILL.md` or reference file, a
template a skill lands, the glossary, an ADR, a doc under `docs/`, or the prose
inside a script's header. Every file here is read by an agent, so these rules
bind as hard as the shell ones.

## Sources

- [GLOSSARY.md](../../../GLOSSARY.md) is the glossary. Use its terms in prose,
  issue titles and commit subjects, and avoid the synonyms each entry lists.
- [docs/adr/](../../adr/) records decisions. Contradicting one is surfaced, not
  done silently.
- The `writing-for-agents` skill governs every document here: context pointers,
  the information hierarchy, leading words, pruning.

## What a skill may lean on

- **A skill is self-contained: everything its run reads installs with it.** A
  derived copy carries `skills/<name>/` and nothing above it, into a consumer
  repo that has none of this repo's files, tracker or history. So a pointer
  inside `skills/<name>/` names only a file under it, and a term the skill uses
  is defined where the skill uses it. None of these stands in for that: a
  relative link above the skill's directory, which dangles in every
  `.claude/skills/<name>/`; a URL to this repo's `GLOSSARY.md`, ADRs, docs or
  scripts, which a running agent does not fetch and which drifts from the pinned
  copy; an issue or PR number, which is tracker state gone stale once it closes,
  so the reason it records is written out instead; and "this repo" meaning the
  source repo, which in an installed copy names the consumer. The source repo's
  URL appears only as a destination (where to file an issue, an install line),
  never as material to read. Maintainer-only facts (which gate enforces a file,
  how an entry is trialled) live here or in `docs/agents/ship.md`, not in the
  skill. `CHANGELOG.md` and code comments carry provenance and are exempt. The
  `self-contained` gate holds the links and numbers; a bare `#N`, a borrowed
  term and "this repo" are the reviewer's. A skill's vocabulary shipped as a
  link to this repo's glossary, or its frozen lines as an issue link, reaches a
  consumer as a pointer to nothing.
- **A command or YAML block a skill hands a consumer runs as written.** Every
  placeholder is named and explained beside the block, a secret is read from
  stdin rather than passed on the command line, where shell history and `ps`
  keep it, and every token, permission or scope asked for is the least the step
  needs. A recipe that needs a fix before it runs teaches the consumer to edit
  every recipe.
- **A setup-skill change says what happens to a file its previous version
  wrote.** `setup-skills` and `setup-harness` land files in consumer repos, so a
  change to a landed file's shape names, in the skill's own prose, whether a
  re-run migrates the old shape, keeps it, or reports it for the owner. A
  consumer otherwise stays on the old shape with nothing telling it so.

## Words and claims

- **A vocabulary the change extends is swept across the whole `skills/` tree,
  sibling spellings included.** Grep the new term and the ones it sits beside
  (`defer-to-ci` beside `deferred-to-ci`), across every file rather than the
  ones the diff already opened; a stale spelling left in the copy nobody grepped
  reads as the current rule to the agent that finds it first.
- **History keeps the old word through a rename.** The sweep above stops at
  history: a `CHANGELOG.md` entry, an ADR and a `retired-terms.md` row keep the
  word as it was, since the row is what `update-skills` searches consumers for.
- **A word a skill retires gets its `retired-terms.md` row in the same diff.**
  The row is the version the PR title's grade cuts from the current
  `metadata.version` (corrected in the same PR if the `major` label lands), the
  retired word, and its replacement or `None.`; it is how `update-skills` finds
  the word in consumer repos, so a retirement without its row survives in every
  one of them.
- **An `only`, `never`, `every` or `nothing` is grepped for its exception before
  it is written.** An absolute claim about the code is checked against the tree
  at this head, and an exception it finds is written into the sentence. The
  claim is read as a rule, so a single exception the sentence denies sends the
  next reader the wrong way.
- **A mechanic's header is its contract.** The header comment of a mechanic or
  gate script lists its output keys and exit meanings, and each moves in the
  same hunk as the code that changes it. A header that drifted is what the next
  author reads instead of the code.

## Rule-shaped changes

- **A rule-shaped prose change reaches every item it governs, one outcome
  each.** Enumerate the items the rule names (every mechanic, every
  verification, every trigger) and check the change lands on each exactly once;
  an item the rewrite skipped, or one left carrying two answers, is where a
  reviewer finds five rounds of work. Grep the twin pairs this repo keeps, since
  a rule stated in one is usually stated in the other:
  - a reviewer scaffold under `skills/setup-skills/reviewers/` and the live
    workflow it produced, `.github/workflows/claude-review.yml`;
  - the profile's `## Reviewers` block in `docs/agents/ship.md` and the
    scaffold's "Profile block this produces";
  - a glossary entry and the reference file it summarises;
  - `.github/copilot-instructions.md` and these standards.

  A PR that rewrites a rule over a named set lists each item with its one
  outcome under `## Special things to note`, so self-review and the Reviewer
  check a list rather than a memory. A fix a review finding proposes is such a
  change too: the finding names one item, and the next round finds its siblings
  still carrying the old answer.
- **A prose change to ship's SKILL.md or a reference file names what it removed
  or folded next to what it added.** One bullet under the PR body's
  `## Special things to note` names the lines the change cut, or folded into
  another file or a mechanic's output, beside the lines it wrote. A retro tends
  to add a clause without deleting one, so the prose a run reads grows unless
  each change shows its direction; one that adds more than it removes says why
  in that bullet. The `prose-budget` cap bounds SKILL.md alone, and this check
  covers the reference files too.
