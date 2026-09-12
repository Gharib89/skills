# Ship profile

Schema: 1

Every repo-specific fact `/ship` needs, one section per axis. Fourteen `##` headings, always present and in this order; a defaulted axis reads `None.` or `Default.`, never an omitted heading. Facts sit on `Label:` lines; the prose under a heading explains and never carries a fact. The `Schema:` line above is the profile schema `ship` checks at preflight; only a `setup-skills` re-run moves it. Vocabulary: the `ship` skill's source repo, `Gharib89/skills`, `CONTEXT.md`.

<!-- setup-skills: fill every `Label:` line, replace each <...>, delete these comments. -->

## Host

Host: <github | ado>

<!-- Derived from the origin remote and cross-checked at preflight. Org, project and repo always derive from the remote. -->

## Worktree

Carry: <comma-separated gitignored files copied one-way into the worktree, or None.>
Bootstrap: <command run once after isolate in every lane, or None.>

<!-- Location is core: <parent>/<repo>.worktrees/<slug>-<issue>. Only small dotfiles belong on Carry (.env, *.local); dependency install belongs to the local gate. -->

## Local gate

Location: <scripts/local-gate.sh>
Small node: <the syntax of one test node for --small, with an example>
Tripwires: <anything that must run before the gate, e.g. a bundle rebuild, or None.>

<!-- Output contract, flags and statuses are core. -->

## CI

Legs: <one `name: what it proves` per line; these names are what `## Verification` may defer to>
No-checks legal: <yes | no, with the reason: path-filtered workflows may legitimately report no checks>
Push policy: <e.g. one push per review round; minutes are metered, or Default.>

<!-- Only workflows with a pull_request trigger are legs. Name other workflows in prose here as non-PR. -->

## Reviewers

<!-- Zero or more `### <name>` blocks, or the single line `None.` Trigger fixes mechanics and convergence; brand never does. -->

### <reviewer name>

Login: <the login(s) it reviews under>
Trigger: <auto-once | on-push | on-request>
Request: <on-request only: the mechanic that requests a round, else None.>
Cap: <on-request only: max rounds, required, no default; else None.>
Resolve: <on-push only: how a dispositioned thread is resolved, else None.>
Gating: <yes | no>
Instructions: <path of the file this reviewer reads, or None.>

## Coding standards

<one doc path, e.g. docs/contributing/coding-standards.md>

<!-- The canonical file the self-review's Standards axis and every reviewer decline derive from. -->

## Verification

<!-- Zero or more `### <name>` blocks with exactly these seven lines, or the single line `None.` -->

### <verification name>

Proves: <what this proves against the real thing the repo integrates with>
Applies when: <prose the agent judges at classification, not path globs>
Run: <the command>
Needs: <the environment it needs and how to detect it>
Without it: <hand-off | defer-to-ci | blocked>
Also proven by CI: <a leg named in ## CI; required when Without it is defer-to-ci, else None.>
Claims to probe: <the external-system claims to check before building on them>

## Versioning and changelog

Tooling: <semantic-release | changesets | manual | none>
Reads: <what release tooling reads: the squash subject, a tag, a file, or None.>
In-PR requirement: <anything that must land in the PR itself, e.g. a version bump CI enforces, or None.>
Subject constraints: <reserved prefixes or formats for the squash subject, or None.>

## PR

Template: <path; honour it, never pass a raw body> | None.

<!-- `Closes #<issue>`, `## Deviations from plan` and `## Review` are core in every repo. The closing reference sits above the first `## ` heading, where a section rewrite cannot reach it. -->

## Public surface

Default.

<!-- Default. means exported or published API, CLI flags, config schema, file formats. Enumerate instead when the repo's surface is wider (gate rules, palettes, bundle inputs). -->

## Triage

File as an issue labelled `<the needs-triage label from docs/agents/triage-labels.md>`.

## Docs sync

Targets: <artifacts coupled to a change: README.md, docs/, CONTEXT.md, a shipped skill, examples/>
Agent-facing: <which of those go through writing-for-agents: docs/agents/, .claude/skills/>

## Current docs

Sources: <context7, plus Microsoft Learn where the stack is Microsoft>
Pinned: <libraries whose installed version matters, or None.>

## Cloud lane

PR cap: <number, default 3, or none>
Bootstrap: <path of a sandbox-only setup script, or None.>

<!-- The cloud bootstrap repairs the sandbox image; it never runs on a developer machine. -->
