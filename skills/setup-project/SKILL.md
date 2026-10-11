---
name: setup-project
description: >-
  Take a repo to a consumer repo ready for its first /ship: show the setup
  status, then follow setup-matt-pocock-skills, setup-harness and setup-skills
  in order, each in its first-run or re-run mode, and prove it with Ship's
  preflight. Run again to catch a repo up.
disable-model-invocation: true
metadata:
  version: 0.1.0
  composes: mattpocock/skills#49dd158d1076134a641b33efb035946536778336:setup-matt-pocock-skills
---

# setup-project

A **project setup** takes a repo to a consumer ready for its first Ship run by
following every setup skill in order. It keeps no record of its own: what is
done is read from the files those skills write and from `skills-lock.json`, so
running it again is how a repo catches up, and a stopped run resumes at the
first step not done.

Install it at user scope, because it must run in a repo that has no
project-scope skills yet; everything it installs goes in at project scope, where
the repo's derived copies are what runs:

```sh
npx skills add Gharib89/skills --skill setup-project --agent claude-code -g -y
```

## The setup status

The **setup status** is one row per step, in this order, each read from what the
step leaves behind:

| Step | Reads |
|---|---|
| `tools` | git, jq, node and npx, the stack's own tool by its lockfile, and `gh` signed in (`az` on an Azure DevOps origin) |
| `repo-and-remote` | `.git`, an `origin` on GitHub or Azure DevOps, and a stack manifest where the repo has no commits |
| `installed-skills` | the chain set in `skills-lock.json`, from its source, and under `.claude/skills/` |
| `matts-setup` | `docs/agents/issue-tracker.md`, `triage-labels.md`, `domain.md` |
| `harness` | `docs/agents/harness.md`'s `Schema:` against setup-harness's |
| `ships-setup` | `docs/agents/ship.md`'s `Schema:` against ship's |
| `proof` | Ship's preflight, at the run's end only |

Each row reads `run` (what the step leaves is missing: its first run),
`re-run audit` (present but behind) or `done`, with the evidence it read. Matt's
docs carry no schema to compare, so `matts-setup` reads only `run` or `done`.
The **source repo** is `Gharib89/skills`, where these skills are written. The
**chain set** is what setup-skills needs before it runs: `ship`, `cloud-ship`,
`setup-skills`, `update-skills` and `setup-harness` from the source repo,
`setup-matt-pocock-skills`, and every skill those compose, each at its pinned
ref. A source-repo skill is behind when its version trails the source
lock; a composed skill is behind when the lock records it at another source or
ref than its pin.

`scripts/setup-status.sh <root> [<source-lock>]` prints the rows, one JSON line
each, reaching no host. `scripts/source-lock.sh` fetches the source lock: the
source repo's `skills-lock.json` with each of its own skills' versions. Both
answer `--help`.

## Process

`S` below is this skill's `scripts/` directory, and every command runs from the
repo root. Write `S` out as the full path in each command: a shell variable does
not survive from one command to the next.

### 1. Version check

```sh
"$S/source-lock.sh" > "${TMPDIR:-/tmp}/setup-project-source-lock.json" \
  || rm -f "${TMPDIR:-/tmp}/setup-project-source-lock.json"
```

When it left no file, say the source repo was unreachable, so versions go
uncompared and no extras are offered, and go on. Otherwise compare its
`.skills["setup-project"].version` with this skill's own `metadata.version`.
When the source lock's is higher, print the install line above for the owner to
refresh this copy, and go on: the skills this run follows are read fresh from
project scope.

### 2. Clean tree

In a repo with commits, `git status --porcelain` must print nothing. Else stop
before any step: ask the owner to commit or set the changes aside, then rerun
`/setup-project`. Never stash for them: setup-project's writes must be the
whole diff.

### 3. Show the status, confirm once

```sh
"$S/setup-status.sh" . "${TMPDIR:-/tmp}/setup-project-source-lock.json"
```

Drop the second argument when step 1 left no file. Show the rows as a table:
step, state, and the evidence that decided it. Under it, offer the **extras**:
each source-lock entry that step 5's install lines do not install, that is not
`setup-project` itself (it stays at user scope), and that this repo's
`skills-lock.json` does not hold yet, as opt-in choices beside an explicit "no
extras". Confirm the table and the extras once. Every followed skill below
still asks its own confirmations before it writes.

### 4. Where the writes land

In a repo with no commits yet, the setup commits straight to the default branch.
In any other, switch to `chore/setup-project`, so all of setup-project's writes
land on one branch and one PR. Create it from the default branch. An existing
`chore/setup-project` is reused when it holds the default branch's head
(`git merge-base --is-ancestor <default> chore/setup-project`); one behind it is
left from an earlier setup or has fallen behind: stop, naming it for the owner
to merge the default branch in or delete, then rerun `/setup-project`. Commit
each step's writes before the next step starts, because setup-harness requires
a clean tree.

### 5. Each step, in order

Stop at the first step that stops, naming it and what the owner must do, then
rerun `/setup-project`; the next run resumes from the files. A row reading
`done` needs no action unless named below.

**Following a skill** means reading `.claude/skills/<name>/SKILL.md` from this
repo and carrying out its whole process here, in this session, as if it had
been invoked: its own references, gates and stops included, and a re-run audit
in full even when the row reads `done`, never a spot-check. These skills cannot
be started with the Skill tool, since each refuses model invocation, and none
is handed to another session.

- **`tools` or `repo-and-remote` reading `run`**: print the missing pieces from
  the row's evidence, then stop. setup-project acts on a repo that already has
  its tools, a `.git`, an `origin` remote and, before its first commit, a stack
  manifest.
- **`installed-skills` reading `run`**: run the install lines, then install the
  chosen extras.

  ```sh
  npx skills add Gharib89/skills --skill ship --skill cloud-ship --skill setup-skills --skill update-skills --skill setup-harness --agent claude-code -y
  npx skills add mattpocock/skills#49dd158d1076134a641b33efb035946536778336 --skill setup-matt-pocock-skills --agent claude-code -y
  npx skills add mattpocock/skills#f3fc5632f401156837ee3872f14fe33ccf1024ea --skill code-review --skill tdd --agent claude-code -y
  npx skills add mattpocock/skills#c55ee46073ed923f86ce59a5eb3b6d895095d1b7 --skill writing-for-agents --agent claude-code -y
  npx skills add mattpocock/skills#d81f3a183412e71a5b1e84ca21bc1a35eea03a60 --skill triage --agent claude-code -y
  npx skills add upstash/context7#522c4db4fa2e1e31f1b320f09fa8c8fab376987a --skill find-docs --agent claude-code -y
  npx skills add humanlayer/skills#ca7c8088db69e315a8b2deea43820270457f8f3c --skill show-me --agent claude-code -y
  ```

  Each extra installs at the ref the source lock records; this prints its line,
  `<name>` being the extra:

  ```sh
  jq -r --arg k "<name>" '.skills[$k] | "npx skills add \(.source)\(if .ref then "#" + .ref else "" end) --skill \($k) --agent claude-code -y"' "${TMPDIR:-/tmp}/setup-project-source-lock.json"
  ```

- **`installed-skills` reading `re-run audit`**: switch back to the default
  branch, deleting `chore/setup-project` when it holds no commits beyond it,
  then follow update-skills, which opens its own branch and PR, and stop: the
  owner merges the refresh, and the next run's steps read the refreshed copies.
  Extras wait for that run.
- **`installed-skills` reading `done`**: install the chosen extras only.
- **`matts-setup`, `harness`, `ships-setup`**: follow
  `setup-matt-pocock-skills`, `setup-harness` and `setup-skills` in turn, every
  row state included: a `run` row takes the skill's first run, any other its
  re-run audit, which proposes only what is missing or behind. Each skill
  chooses its mode from the same profile its row read.

### 6. Proof

Re-run step 3's `setup-status.sh`, then:

```sh
.claude/skills/ship/scripts/preflight.sh none
```

The setup is done only when every row but `proof` reads `done` and preflight
answers `ok: true`; the `proof` row is then done. Otherwise report the rows and
reasons that are not, which the next run takes up.

In a repo that had no commits, push the default branch. On
`chore/setup-project` with commits beyond the default branch, open its PR
through Ship's mechanics, which push the branch first and, when an earlier run
already opened its PR, return that one:

```sh
.claude/skills/ship/scripts/open-pr.sh none --title "chore: set up this repo for Ship" --body-file <body>
.claude/skills/ship/scripts/update-pr-body.sh <pr> --section "Setup status" --body-file <table>
```

The body follows the repo's PR template and the final status table goes under
`## Setup status`; the second command rewrites that table in a PR an earlier
run opened. With no commits beyond the default branch, there is nothing to
review: switch back and delete the branch.
