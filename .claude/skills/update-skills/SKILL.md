---
name: update-skills
description: "Refresh this repo's skills in one PR: the Gharib89/skills skills, every skill they compose at its pinned ref, and any other repo-scoped skill the owner picks; report upstream drift to the source repo and summarise what changed. In the source repo, move the drifted pins instead. Attended only."
disable-model-invocation: true
metadata:
  version: 1.0.0
---

# update-skills

Refresh a repo's skills as one PR the repo's own CI, reviewers and merge gate
see, with a body that says what moved. Vocabulary:
[CONTEXT.md](https://github.com/Gharib89/skills/blob/main/CONTEXT.md) of the
source repo (source repo, consumer repo, derived copy, pinned ref, upstream
drift, refresh).

**Attended only.** It asks the repo owner which skills to take and re-runs
`/setup-skills`, which interviews; no cloud routine runs it.

**It calls Ship's generic mechanics by path**, `S=.claude/skills/ship/scripts`
and `U=.claude/skills/update-skills/scripts`, from the worktree (ADR 0004):
after step 2 those are the scripts it just installed, so it never drives a Ship
other than the one the PR ships. Each mechanic answers `--help` with its flags.
Plan files and body files go in your scratchpad, outside the repo.

## Process

### 1. Isolate

From the main checkout, `$S/isolate.sh none chore update-skills`, then work
from the path it prints. Record `old=$(git rev-parse HEAD)`: the tree before
the refresh, which the plan reads as the old side.

### 2. Refresh the source-repo skills

In a consumer repo:

```sh
npx skills add Gharib89/skills --skill ship --skill cloud-ship --skill setup-skills --skill update-skills --agent claude-code -y
```

In the source repo, whose `skills-lock.json` records `ship`'s source as `.`,
run the refresh line its CLAUDE.md carries instead. Project scope always: no
`-g`.

### 3. Plan

```sh
$U/heads.sh . > <scratch>/heads.json
$U/plan.sh . <scratch>/heads.json --old "$old" > <scratch>/plan.json
```

`heads` reads GitHub's public API with curl, so it needs no credentials. Exit 1
means an upstream was unreachable: write `{}` to `heads.json`, continue, and
carry its `error` to step 8 as "drift not checked". The plan's fields drive
every later step; its header comment in `plan.sh` defines each one.

Nothing moved (every `source_skills` entry at its old version, every
`composed` entry's `old_ref` equal to its `pin`, and `drift`, `others` and
`sections` empty): tell the owner the repo is current, run `$S/cleanup.sh none`
from the main checkout, and stop.

### 4. Composed skills at their pins

Run every `composed[].install` line, then `$S/preflight.sh none` and keep its
`reasons`; a `worktree exists` reason naming this run's own worktree is
expected. A consumer repo never installs a drift row's `head`: that version is
one nobody tested Ship against, and the row reaches the source repo in step 7
instead.

### 5. Other skills

`others` lists the repo-scoped lock entries, neither from the source repo nor
composed, whose upstream moved. Non-empty: ask once, with one multi-select
question per four skills in a single AskUserQuestion call, each option the
skill's name with `<old_ref, or "no ref"> → <head>` as its description. Run the
`install` line of each skill ticked. Personal skills under `~/.claude/skills`
are never in the lock and never touched.

### 6. setup-skills sections

`/setup-skills` re-runs when step 4's `reasons` carry `profile missing` or
`profile invalid`, or `sections` is non-empty. Ask the owner to run it from a
new session opened at the worktree, and wait: it takes no model invocation, and
this session's copy predates the refresh. Tell them what to redo: its Re-run
path for a profile refusal, and for each section only the step-5 item its
template feeds:

| `section` | setup-skills item |
|---|---|
| `pr-template` | **PR template** |
| `reviewer-scaffolding` | **Reviewer scaffolding** |
| `local-gate` | **Local gate** |
| `coding-standards` | **Coding standards** |
| `dimension-labels` | **Triage labels on the host** and **The `## Dimension labels` section** |
| `ado-tracker-doc` | step 1.1's Azure DevOps tracker doc |

A change to setup-skills' `SKILL.md` alone is not a section: its prose moving
costs no interview. The re-run ends with preflight clean. Note the profile
schema move for step 8: the `Schema:` line of `docs/agents/ship.md` at `$old`
against the one now.

### 7. Report upstream drift (consumer repo)

`drift` non-empty, and `mode` is `consumer`: the source repo keeps one open
issue for it. Write a body file holding a `## Drift` section and nothing else,
its table `| Skill | Pinned | Upstream head |` with one row per `drift` entry.
The source repo is public, so the body carries skill names and refs only: not
this repo's name, nor anything else about it (ADR 0004). Then:

```sh
$S/file-issue.sh --repo Gharib89/skills --title "Upstream drift: composed skills" --body-file <body> --label needs-triage
```

- `filed: true`: that is the drift issue.
- `filed: false`: the candidate titled exactly `Upstream drift: composed
  skills` is the drift issue. Rewrite its table in place, with a file holding
  the table alone: `$S/update-issue-body.sh <n> --repo Gharib89/skills
  --section Drift --body-file <table>`. With no candidate of that exact title,
  re-run `file-issue` with `--distinct-from` naming every candidate.
- Exit 1: the source repo is unreachable from here, which is every Azure
  DevOps repo without GitHub credentials. Print the answer's `command` for the
  owner, verbatim, and carry it to step 8. No retry.

In the source repo, drift moves pins instead: step 9.

### 8. Summary and PR

Commit the refresh and every setup-skills write. The PR body carries these
sections in this order:

1. `## Source-repo skills`: for each `source_skills` entry whose version moved,
   its `changelog` sections above `old_version` up to `new_version`, verbatim,
   every breaking change lifted to the top. A null `old_version` is a skill new
   to this repo: its version alone.
2. `## Composed skills`: for each `composed` entry whose `old_ref` differs from
   its `pin`, `<skill>: <old_ref> → <pin>`, then the upstream commit subjects
   that touched its folder between the two. A null `old_ref` reads "previously
   unpinned → `<pin>`", with no subjects.
3. `## setup-skills`: the sections step 6 re-ran and the profile schema move,
   or "none".
4. `## Other skills`: each skill step 5 took, `<old_ref> → <head>`, with its
   subjects the same way.
5. `## Upstream drift`: the drift issue's link and the rows held at their pins,
   or the printed command, or "drift not checked: <error>", or "none".

The subjects are a read, not a gate: the folder is the lock's `skillPath`
without `/SKILL.md`, and the commits are those of
`https://api.github.com/repos/<source>/commits?sha=<new>&path=<folder>` newer
than the old ref, which `.../commits/<old_ref>` dates.

Open it with `$S/open-pr.sh none --title "<subject>" --body-file <body>`, a
Conventional-Commit subject honouring the profile's `Subject constraints:`
(`chore(skills): refresh derived skills` where it has none), then
`$S/read-pr.sh <pr>`. Hand the owner the link. The PR merges the way the repo
merges anything; after it has, `$S/cleanup.sh none` removes the worktree.

### 9. Source-repo mode

`mode` is `source`: this is Gharib89/skills, and each `drift` row is a pin to
move, in this one PR. Steps 5, 6 and 8 run unchanged; step 7 does not. Per row:

1. Read what moved: `https://api.github.com/repos/<source>/compare/<pin>...<head>`,
   the files under the skill's folder with their patches.
2. Re-add the skill at the head, its install line with `#<head>` in place of
   the pin, and move the pin on the `composes` line that names it
   (`skills/ship/SKILL.md` or `skills/setup-skills/SKILL.md`), plus the sha on
   every printed install line in setup-skills' step 1.2 that installs it. A
   printed line installing several skills at one sha is split when their pins
   part.
3. Judge the upstream diff against what Ship's prose relies on in the phase
   that composes the skill. Where it breaks a reliance, rework that prose
   through `/writing-for-agents` in this same change: Ship never ships against
   a pin it does not fit.

Then the refresh line, and `scripts/local-gate.sh`, whose `derived-copies` gate
holds every pin to the lock. The PR body opens with `Closes #<n>`, the open
issue titled `Upstream drift: composed skills`
(`gh issue list --search 'in:title "Upstream drift: composed skills"' --state open`),
and its title is scoped to the skill whose pin moved, e.g. `fix(ship): move
show-me to <short sha>`, so the release run records the move in that skill's
CHANGELOG.
