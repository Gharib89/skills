# Standards: release, PR and commits

Every PR: the version a consumer reads comes from the PR title, so the grade,
the title, the body and the commits are reviewed here, beside the two rules
that bind every change whatever its paths.

## Every change

- [GLOSSARY.md](../../../GLOSSARY.md) is the glossary. Use its terms in prose,
  issue titles and commit subjects, and avoid the synonyms each entry lists.
- [docs/adr/](../../adr/) records decisions. Contradicting one is surfaced, not
  done silently.

## Grading a change

[docs/agents/ship.md](../../agents/ship.md) `## Public surface` enumerates what
a consumer repo depends on. **Grade a change to it before choosing the version
number**, because that number is what a consumer reads to decide whether
refreshing a derived copy is safe, alongside the separate schema check the
profile-structure bullet describes. While a skill is 0.x, every major grade
below lands as a minor
([ADR 0005](../../adr/0005-skills-stay-0x-until-public-release.md)):

- **Additive is a minor bump.** Something is added and nothing already there
  changes meaning: a mechanic added, an optional flag or a stop reason added, a
  key added to a mechanic's JSON, a line added to a `setup-skills` template or
  to the `### Ship` block, the profile's own structure, `ship`'s `composes` line
  and a new blocking precondition excepted by the bullets below. A consumer that
  refreshes keeps working without reading anything.
- **Breaking is a major bump.** Something already there is removed, renamed or
  redefined: a mechanic or flag removed, a mechanic's JSON shape changed (a key
  renamed, removed or retyped), a mechanic's CLI signature changed so that an
  existing invocation stops working (a new required argument, an existing
  option's meaning or arity changed), a vocabulary value's meaning changed, the
  local-gate contract's flags, gate statuses or verdict changed, the profile's
  structure and `composes` excepted by the bullets below. This is what a
  consumer must read before refreshing.
- **A new precondition that stops a consumer's run is breaking.** A check that
  refuses a run until the consumer installs, migrates or configures something (a
  tool on PATH, a file's new shape, a label, a setting) is graded breaking,
  however small the check reads: a consumer that refreshes has its next run
  refused without having read anything. The profile-structure and `composes`
  bullets below are instances with their own mechanics. A refusal naming its fix
  is the mitigation, not a downgrade.
- **A reword that decides the same thing is a patch.** The test is whether what
  the text decides changed, not whether the words did. A skill's `description`
  is on the list because it decides when an agent reaches the skill, so a reword
  that keeps every condition under which an agent picks the skill is a patch;
  one that drops or adds a condition is the redefinition the breaking bullet
  grades, because a consumer that refreshes then gets different routing without
  reading anything, where every item the additive bullet lists is inert until
  something uses it. The same exceptions apply. A shortened `description` that
  keeps every routing clause and drops only a recitation of another skill's
  behaviour is a patch, since that behaviour is the other skill's surface.
- **The profile's structure is a ship major.** A heading or `Label:` line added,
  renamed, removed or reordered, a `Label:` vocabulary changed, or the `Schema:`
  number moved, is a major bump, additive or not. The same PR moves
  `metadata.profile-schema` in `skills/ship/SKILL.md` and the `Schema:` line in
  `skills/setup-skills/ship-profile.md` by hand, and adds the matching
  `## Schema N` entry to `skills/setup-skills/profile-schema.md`; a PR that
  edits `ship-profile.md`'s structure without that entry is incomplete. The
  `derived-copies` gate fails when the three disagree
  (`scripts/profile-schema-check.sh`). A behaviour change that leaves the
  profile alone moves none of them. Preflight refuses a schema mismatch in
  either direction, so an added heading stops an installed profile from running
  until `setup-skills` migrates it, which is what makes it breaking where an
  added optional flag is not. A line `ship` accepts without expecting, the
  optional lines paragraph of `profile-schema.md`, takes no entry and no bump.
- **The harness profile's structure is a setup-harness major.** A setup-harness
  PR that changes what the profile must contain (a heading or `Label:` line
  added, renamed or removed; a `Label:` vocabulary changed) adds an entry to
  `skills/setup-harness/harness-schema.md`, moves `metadata.harness-schema` in
  its `SKILL.md`, the `Schema:` line in
  `skills/setup-harness/templates/harness-profile.md` and the `schema=` literal
  and grammar in `skills/setup-harness/scripts/harness-profile-check.sh`, and is
  graded a setup-harness major. The `contract` gate's schema-equality check
  (check 9) fails when the four disagree. Two lines are frozen across every
  schema, because `setup-skills` reads them with no schema check: `Location:`
  under `## Check entry point` and `Setup:` under `## Cloud`. Renaming either is
  a major of both skills in one PR; the `contract` gate's frozen-lines check
  (check 8) fails when the profile template lacks either.
- **Adding to `composes` or moving a pin is breaking, removing is additive.**
  The direction is inverted relative to every other item, so read it before
  grading one. Adding a skill to `ship`'s `metadata.composes` line is a `ship`
  major bump: preflight collects one
  `skill missing: <skill>; run <install line>` reason per composed skill absent
  from the consumer's `.claude/skills/`, so a consumer that refreshes `ship`
  alone has its next run refused until it installs the new skill from that
  skill's own source repo. Moving a pin is breaking too: preflight collects
  `skill off pin: <skill> at <ref>, pinned <sha>; run <install line>` for a
  consumer whose lock records the old ref, until it runs that line. Moving
  setup-skills' `triage` pin is not breaking: nothing refuses on it, and
  setup-skills only prints the new line. Removing one is additive, a minor bump,
  because nothing already installed stops working. A minor bump taken for an
  added composed skill before this rule existed is not precedent. A skill `ship`
  newly composes is added to that line in the same PR: preflight checks only the
  skills the line names.
- **A change that touches no public surface is a patch.**

## The PR title and commits

- **The grade is the PR title's conventional-commit type, and the diff never
  carries the number.** The release run on main reads the squash subject, which
  is the PR title, so a change graded minor is titled `feat(...)`, and
  everything else takes whichever type describes it. A breaking change is titled
  by the skill's release state
  ([ADR 0005](../../adr/0005-skills-stay-0x-until-public-release.md)). While the
  skill is 0.x, `feat(...)`, which cuts the minor a 0.x break earns: the break
  is stated in plain words in the commit body and under Special things to note,
  and the title, every commit and the description carry no `!` and no
  `BREAKING CHANGE:` footer. The PR releasing it at 1.0, and every breaking
  change after, carries a `!` and the maintainer's `major` label. Grade first,
  then pick the type to match, rather than the other way round: a `feat(ship):`
  that only adds an optional flag is correctly minor, and a rename of a JSON key
  is breaking whatever verb describes it, so on a 0.x skill it is titled
  `feat(ship):` and not `fix(ship):`. A title whose type under-grades the change
  is a finding. One title grades every skill the diff touched, because
  `path_filters` route a commit to a skill by path and cannot route a grade:
  **the title carries the highest grade across those skills, and the others
  take that number.** A patch-sized reword riding
  along with a `feat` is released minor, which is the cost of one subject, and
  splitting the PR to avoid it is not worth a second review cycle.
- **Commit subjects** are conventional-commit prefixed and scoped to the skill:
  `fix(ship):`, `docs:`, `feat(setup-skills):`.
- **Commit messages** carry no em dashes either. The `house-style` gate reads
  files, not messages, so this one is on the author.

## The PR body

- **PR body: seven sections, in order.** `## Why the change`,
  `## Change outline`, `## Special things to note`, `## Needs attention`,
  `## Verification`, `## Review`, `## Attribution`. Every body carries all
  seven, template or not, because ship writes the headings it does not find; a
  missing one is a finding, and `## Attribution` last is what keeps a section
  rewrite from swallowing the footer.
- **PR body: `## Change outline` carries a Shape.** A `diff` fence over a call
  tree, control flow, pseudocode or component tree, under `## Change outline`,
  which every body carries because ship writes the heading where no template
  gives it. Text forms only; mermaid and HTML are out. One behavioural fence per
  PR, 15 lines or fewer, with a carrier file tree after it only where the
  same edit lands in more than two files. Every node is a real symbol, each
  tree's root node carries its file path, and no line carries a line number.
  `scripts/check-pr-body.sh` holds the fence limit, the root path and the
  symbols: a call node one level under a root must be a word of that root's
  file.
  `Shape: none, mechanical (<kind>).` replaces the fence only where the
  reviewer's question is "did the text change correctly", never where it is
  "what does X now do"; the diff being comments or prose does not settle which.
  Silent absence is a finding either way.
- **PR body: a `## Verification` line names the probe that measured it.** Each
  line gives the command or check whose output it reports, not the conclusion
  alone. The reviewer's evidence rule in the index binds the author's claims
  too: #768 called a 14 GB env "current" while the only probe was a `check` that
  printed "ready".
- **A fix landed after review has its hunk re-read before the push.** Read the
  changed lines back out of the file, not out of the reply you are about to
  post; a fix applied to the wrong copy or applied by half costs a whole round
  to discover.

## Adding a skill this repo writes

The set of skills this repo writes is the lock's `source: "."` entries, in
`skills-lock.json`. Five sites need a hand edit for each skill in that set:

1. The lock entry: add `--skill <name>` to the Refresh line in CLAUDE.md's
   `### Ship` block and run it, which writes the entry and the derived copy.
2. The release configuration, `.release/<name>.toml`.
3. The release workflow, `.github/workflows/semantic-release.yml`: its `SKILLS`
   list and the release-commit conditions above it.
4. The install lines in the skill's `SKILL.md`: a pinned line for each skill it
   composes, if any.
5. `.gitattributes`: `.claude/skills/<name>/** linguist-generated`, which
   collapses the derived copy in a GitHub PR diff.

The `derived-copies` gate fails until each `skills/<name>/` has its lock entry,
derived copy, release configuration, both places in the release workflow and
its `.gitattributes` line; `scripts/pin-check.sh` holds the fourth site's pinned
lines to the lock.
