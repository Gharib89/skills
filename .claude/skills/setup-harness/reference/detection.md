# Stack detection

## Contents

- [What is detected](#what-is-detected)
- [The scan](#the-scan)
- [Evidence per member](#evidence-per-member)
- [What detection reports](#what-detection-reports)

## What is detected

- A **stack** is one language plus package manager at a root whose manifest owns a lockfile, or that a workspace config names (pnpm, npm or yarn workspaces, a uv workspace). One stack per root. Install and tool versions are once per root.
- Its **members** are its workspace packages; a stack with no workspace is its own single member. Typecheck and affected tests run per member.
- A **file kind** (shell and the like) is detected by extension, shebang, file name (`Names:`, a tracked basename at any depth, such as `azure-pipelines.yml`) or path (`Paths:`, a glob on the repo-relative path, such as `.github/workflows/*.yml`) and takes the edit and commit rungs only, never `turn`.

## The scan

Tracked files only, from the repo root:

```sh
git ls-files -- . ':!:.claude/skills/'         # the whole tree detection reads
git submodule status                           # reported, never scanned
git ls-files -- . ':!:.claude/skills/' | sed -n 's|.*/||; /^\./d; s/.*\.\([^.]*\)$/\1/p' | sort | uniq -c | sort -rn   # extension counts, dotfiles skipped
```

- A **root** is a directory holding a stack's `Manifest:` with one of its `Lockfile:` names beside it, or a member a root's `Workspace:` config names. A directory holding a `Workspace:` file but no `Manifest:` (a `*.sln`, a `go.work`, a `settings.gradle` with no build file) is not a root: it is the **stack root** of the members that file names, where a row whose `Constraints:` name the stack root runs, and each member is a root or a candidate by its own lockfile. A `Manifest:` or `Workspace:` name with `*` (`*.csproj`, `*.sln`) is a glob on the basename.
- A lockless manifest is a **candidate** unless a root's `Workspace:` config names it; a stack root is not a root, so a lockless member its `Workspace:` file names is a candidate. Ask the human to mark it a root or ignored. Marked lands as `Root: <manifest>: <reason>` in the profile, ignored as `Declined: <manifest> as a root: <reason>`, `<manifest>` being its repo-relative path (`api/pom.xml`), so a re-run does not ask again: a candidate with either line is answered, and one with neither is **new**.
- A root with no lockfile the human marked a root, in this run or by a `Root:` line, is reported `unlocked` and installed from its manifest as it stands. Never generate a lockfile: that changes the repo's dependency resolution.
- **Installed skills** under `.claude/skills/` are derived copies pinned by `skills-lock.json`: not scanned, and excluded from the runner config (`exclude: ^\.claude/skills/`), because a fix-mode tool rewriting one breaks its `computedHash`. A `harness-<upstream>/` directory there is a vendored plugin instead: excluded the same way, and read as a language server's evidence per [language-servers.md](language-servers.md).
- A shebang is read from the first line of an extensionless tracked file with the executable bit (`git ls-files -s` mode `100755`).
- A file a `Names:` or `Paths:` line claims is that file kind's alone, whatever its extension.
- Every tracked extension no stack or file kind claims is `unclaimed: *.<ext> (<N> files)`, with no guessed tools. It adds nothing to `edit` or `turn`; `check.sh full` still calls the repo's own check target.
- A stack with no catalog entry is `unclaimed` the same way, with a pointer to file an issue on [Gharib89/skills](https://github.com/Gharib89/skills/issues) asking for its entry.

## Evidence per member

For each member, with inheritance from its root (root dev dependencies, a root `tsconfig.base.json`), per role (every role its catalog entry carries), each tool with the path that proves it:

- **A config file or table**: `ruff.toml`, `[tool.ruff]` in `pyproject.toml`, `biome.json`, `eslint.config.*`, `.prettierrc*`, `tsconfig.json`, `vitest.config.*`, `[tool.pytest.ini_options]`.
- **A declared dependency**: `devDependencies`, `[dependency-groups]`, `[tool.uv] dev-dependencies`.
- **An invocation**: a tool run only in CI or a script counts as used but `unpinned`, the gap being its pin.

Also record per stack the runtime version source, the first of its entry's `Runtime version:` files present, and for the repo its own check target: a `package.json` script `check`, a `check:` target in `Makefile`, a `check` recipe in `justfile`.

## What detection reports

Shown on the present step and consumed while writing; nothing of it enters the profile but the human's answers to candidates, as `Root:` and `Declined:` lines, because a re-run detects again. The report, in this order:

1. Roots: path, stack, lockfile or `unlocked`, members, runtime version source.
2. Per member and role: the tool, `default` or its evidence path, and `unpinned` or `unwired: <tool> (<evidence path>)` where either applies.
3. File kinds: extension, name or path, file count, tools, and each `Unavailable:` tool with its reason.
4. New candidates, each with its question.
5. Submodules: `submodule <path>, not scanned`.
6. Unclaimed extensions and stacks.
7. The repo's check target, or `None.`
