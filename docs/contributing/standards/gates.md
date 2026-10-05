# Standards: what the gates enforce

The author reads this before pushing. These rules are enforced by
`scripts/local-gate.sh` or the `bump-guard` CI leg, so a reviewer cites the gate
rather than the rule. What each gate checks in full is its script and the ship
profile's `## Local gate` section in
[docs/agents/ship.md](../../agents/ship.md); this file keeps what an author must
do to pass.

- `shellcheck -x -s bash -P SCRIPTDIR -S warning` over every tracked shell
  script outside `.claude/skills/` and `tests/fixtures/`, per the `shellcheck`
  hook in `.pre-commit-config.yaml`, which the commit hook and
  `scripts/check.sh` run. Warnings fail; suppress one only with a
  `# shellcheck disable=<code>` carrying the reason on the same line, and only
  where the warning actually fires.
- A second, plain `shellcheck` over the **landed scripts**, the ones
  setup-harness and setup-skills write into a consumer
  (`skills/setup-harness/templates/*.sh`, `skills/setup-skills/*.sh`), per the
  `shellcheck-landed` hook beside it: a consumer wiring the Shell catalog entry
  runs exactly that, at ShellCheck's default severity `style`, so a finding
  below `warning` fails there. In a landed script, remove a finding's cause
  rather than disabling it where the code differs by ShellCheck version: a
  function called only indirectly is SC2317 on 0.10 and SC2329 on 0.11, so a
  disable must name every version's code and still hides real unreachable code
  later. A version-stable code may be disabled under the rule above, its reason
  on the same line. `skills/setup-harness/templates/check.sh` dispatches its
  rungs with a `case` rather than `"rung_$rung"` for this reason.
- `gitleaks detect` over the branch's commits, per the `secrets` gate.
- `.claude/skills/<name>/` byte-identical to `skills/<name>/` for every skill
  whose `skills-lock.json` entry has `source: "."`, per the `derived-copies`
  gate: run the refresh line in CLAUDE.md's `### Ship` block and commit both
  trees together.
- No em dashes and no trailing whitespace in any file this repo authors, and
  every non-empty text file there ends in a newline, per the `house-style` gate.
  The last two are what a consumer repo's stock `trailing-whitespace` and
  `end-of-file-fixer` hooks demand of the copies it installs.
- No `chmod 000` in a `tests/*.test.sh` outside an `id -u` root guard, per the
  `house-style` gate: root reads a mode-000 file, so the case proves nothing.
- Prose wrapped at 80 columns in the files this repo hard-wraps, the `wrapped`
  list in `scripts/house-style-check.sh`, per the `house-style` gate.
  Frontmatter, fences, tables, changelogs and a line holding only a link, a code
  span or a link reference definition are exempt. The rest of the tree puts one
  paragraph on a line, and a profile's `Label:` line must stay one line because
  the profile is parsed line by line; a file that starts hard-wrapping joins the
  list.
- No source-repo URL but the repo root and its issue tracker in a skill's
  Markdown, and, outside a code span or a fenced block, no `PR #N`, no
  `issue #N` and no relative link leaving `skills/<name>/`, `CHANGELOG.md`
  exempt, per the `self-contained` gate. It is the greppable part of
  **A skill is self-contained** in [prose.md](prose.md).
- The mechanics' malformed-invocation contract, per the `contract` gate: no
  `${N:?}` or `${N?}` expansion under the mechanics, a bare invocation answering
  one JSON `error` object and exit 2, a leading-dash value in a positional slot
  answering the usage line and exit 2, and `--help` answering the usage line on
  stdout, exit 0. Keep a new mechanic's guards where the existing ones fire,
  before the adapter loads: that placement is what keeps the gate off the host,
  and the `--help` check runs each mechanic where no origin remote resolves, so
  a `ship_help` below `ship_load_host` fails. The same gate holds every shell
  file under `skills/` to the four Bash 4 constructs **Everything under
  `skills/` targets Bash 3.2** in [shell.md](shell.md) names, refuses any
  mention of `SHIP_HOST_ADAPTER` under `skills/` outside `_lib.sh`, whose
  `ship_load_host` is its one reader, and holds two sentences of ship's prose,
  matched as substrings with their line wraps joined: phase 4's instruction
  that each axis reads the Local gate's JSON and never runs the suite itself,
  and context discipline's `Read one reference file per call.`
- Each mechanic's header synopsis naming the same flags and leading `<slots>`
  as its `--help` usage line, per the `contract` gate.
- Every value-taking flag answering a leading-dash value (`--title --x`) with
  its usage line and exit 2, per the `contract` gate: take the value through
  `ship_flag_value` in `_lib.sh`.
- A mechanic's host failure, driven through the Host fake, printing exactly one
  JSON object on stdout, per the `contract` gate.
- A mechanic invoked in a skill's Markdown code span carrying every option its
  usage line requires, per the `contract` gate.
- No `curl` without `--max-time` in a shell file under `skills/`, per the
  `contract` gate: a hung download hangs the run that called it.
- No `bash -c`, `sh -c` or `eval` without an input redirect inside a
  `while read` loop fed by a heredoc or here-string under `skills/`, per the
  `contract` gate: it drains the loop's remaining rows on Bash 3.2 and 5.3.
- No hand-rolled three-backtick fence pattern in a shell file under `skills/`
  outside `_lib.sh`'s `SHIP_AWK_FENCE`, per the `contract` gate.
- Ship's own documents inside their line budget, per the `prose-budget` gate:
  `skills/*/SKILL.md` at most 350 lines, and every `skills/*/reference/*.md`
  over 100 lines opening with a `## Contents` list that matches its `## `
  headings both ways. The profile's `## Local gate` section stays at 11000
  bytes or fewer. A rule that outgrows the file it lives in moves to a reference
  file and is pointed at, rather than being cut.
- Every tracked path inside the top-level entries this repo owns, per the
  `stray-files` gate. A new top-level entry is a decision, so it joins the
  allowlist in `scripts/stray-file-check.sh` in the commit that tracks it.
- No `metadata.version` line under `skills/` moved by the diff, per the
  `version-lines` gate: the release run on main owns that number and writes it
  from the squash subject. `metadata.profile-schema` is exempt and stays a hand
  edit, and so is the one-time renumber to 0.x
  ([ADR 0005](../../adr/0005-skills-stay-0x-until-public-release.md)). A
  *removed* version line is what makes a finding, so a new skill's first one
  and a file that gains a metadata block both pass.
- The PR title a Conventional Commit of a type the release run reads, a title
  implying a major bump carrying the maintainer's `major` label, and the PR body
  carrying every `##` heading of the PR template, per the `bump-guard` workflow,
  the repo's one CI leg. A `BREAKING CHANGE:` footer in the description or in
  any commit on the branch implies a major too, because the squash body the
  release run grades is composed from one or the other. How to grade the title
  is [release.md](release.md).
- A `## Change outline` holding a Shape `diff` fence or a
  `Shape: none, mechanical (` line, per the `bump-guard` workflow's body check.
- That Shape fence at most 15 lines, per the same check.
- Each root of that Shape fence carrying its file path, per the same check.
- Each `Closes #N` issue's title printed on the check's stderr as evidence,
  never failing it.
- `tests/run.sh` green, per the `tests` gate. None of its tests reaches a host.
  The kinds of test it runs are listed in the ship profile's `## Local gate`
  section.
- The repo's copies of the shipped Local gate, cloud bootstrap and review
  workflow matching their setup-skills templates outside the consumer-owned
  regions, per `scripts/template-drift-check.sh` under the `tests` gate: mark a
  deliberate departure in the workflow between `# >>> repo-owned` and
  `# <<< repo-owned`.
- A `GLOSSARY.md` `_Avoid_` word in the diff's added Markdown lines, printed by
  `scripts/glossary-warn.sh` from the Local gate as a warning only.
