# Pre-commit runner options for the agent harness

Research for [#336](https://github.com/Gharib89/skills/issues/336), part of map [#333](https://github.com/Gharib89/skills/issues/333). Question: which pre-commit runner fits a harness that is fast, polyglot and cloud-installable? This file gathers the facts; the choice belongs to grilling ticket #338.

Versions examined (latest releases on 2026-09-26): pre-commit 4.6.2, prek 0.5.3, lefthook 2.1.14, husky 9.1.7, lint-staged 17.6.0. All five are MIT-licensed and none is archived (`gh api repos/<r>`).

## Summary table

| | pre-commit | prek | lefthook | husky + lint-staged |
|:--|:--|:--|:--|:--|
| Runner needs | Python >= 3.10 plus 5 PyPI deps | nothing (single Rust binary) | nothing (single Go binary) | Node (lint-staged 17 needs `>=22.22.1`) plus a `package.json` |
| Install footprint (measured) | 15 MB venv | 14.7 MB binary | 14.5 MB binary | 1.8 MB `node_modules` (6 packages) |
| Cloud install route on the default allowlist | PyPI | PyPI, npm, crates.io | npm, PyPI, proxy.golang.org | npm |
| Staged files only | yes, stashes all unstaged changes | yes, same as pre-commit | `{staged_files}` per job; hides unstaged parts of partially staged files | yes; backup stash, hides unstaged parts of partially staged files |
| Parallelism | hooks serial; one hook's files split across CPUs unless `require_serial` | same, plus same-`priority` hooks and same-depth workspace projects run concurrently | opt-in `parallel: true` per git hook | tasks for different globs concurrent by default; subtasks serial |
| Manages each tool's install | yes, per-hook envs for many languages | yes, shared toolchains, uv for Python | no (runs commands; `setup:` step since 2.1.2 is DIY) | no (runs commands) |
| Hook pinning | `rev` per repo; `autoupdate --freeze` writes SHAs | `rev`; `update --freeze`, impostor-commit check, `--cooldown-days`, `update --check` | `remotes[].ref` is a branch or tag; local jobs pin nothing themselves | package.json plus lockfile |
| Release provenance | none on PyPI 4.6.2 | GitHub attestations, PyPI provenance, npm provenance | GitHub attestations, checksums, npm provenance | npm provenance (both) |
| Reads existing `.pre-commit-config.yaml` | native | unchanged (drops only `hazmat`) | no, rewrite as `lefthook.yml` | no |
| Framework overhead, local hooks (measured) | ~120 ms | ~20 ms | ~45 ms | ~117 ms (~320 ms via `npx`) |

## Install footprint and cloud installability

**Measured footprint.** Installed with `uv tool install` into the scratchpad: pre-commit venv 15 MB (excluding the interpreter), prek venv 15 MB of which the `prek` binary is 14,702,472 bytes, lefthook venv 14 MB. `npm i -D husky@9.1.7 lint-staged@17.6.0` gave 1.8 MB `node_modules`. Release archives: prek Linux x86_64 tarball 6.0 MB; lefthook Linux x86_64 binary 14.5 MB (5.8 MB gzipped) (`gh api repos/<r>/releases/latest`).

**Runtime dependencies.** pre-commit `requires_python >=3.10` and depends on cfgv, identify, nodeenv, pyyaml, virtualenv (PyPI JSON for 4.6.2). prek: "A single binary with no dependencies, does not require Python or any other runtime" ([prek README](https://github.com/j178/prek#features)). lefthook: "single dependency-free binary which can work in any environment" ([lefthook README](https://github.com/evilmartians/lefthook)). husky has zero dependencies, engines `node >=18`; lint-staged 17.6.0 has three dependencies and engines `node >=22.22.1` (`npm view`).

**Packaging.** prek's npm package `@j178/prek` and lefthook's npm package `lefthook` both deliver the binary through per-platform `optionalDependencies` (`@j178/prek-linux-x64-gnu`, `lefthook-linux-x64`), so an npm install fetches only from the npm registry. Both also publish PyPI wheels that embed the binary (prek 6.2 MB, lefthook 5.4 MB for manylinux x86_64). lefthook's npm package runs a `postinstall` script (it installs the git hooks; pnpm needs `onlyBuiltDependencies` for it to run, [lefthook node install doc](https://github.com/evilmartians/lefthook/blob/master/docs/installation/node.md)).

**Cloud sandbox, from docs only (not probed).** Per [Cloud environments](https://code.claude.com/docs/en/cloud-environments):

- The VM is Ubuntu 24.04 x86_64 with Python 3.x (pip, poetry, uv, ruff, black, mypy), Node 20/21/22 (22 on PATH), Go, Rust, Ruby and more preinstalled. None of the four runners is listed as preinstalled.
- The Trusted allowlist includes `pypi.org`, `files.pythonhosted.org`, `registry.npmjs.org`, `crates.io`, `static.crates.io`, `proxy.golang.org`, `rubygems.org`, `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`.
- But the GitHub proxy scopes requests: "GitHub API and release-asset requests reach only repositories attached to the session, so a setup script that downloads release assets from an unattached repository gets a 403." So prek's standalone installer (`github.com/j178/prek/releases/download/...`), `prek self update`, and lefthook's GitHub release binaries are expected to fail; the PyPI, npm, crates.io and Go-proxy routes should work.
- The doc is silent on `git clone` of a public repository that is not attached to the session. pre-commit and prek fetch every remote hook repo (`repo: https://github.com/...`) with git, and lefthook `remotes:` does the same. **This is the load-bearing unknown for cloud use of any remote-hook config.**
- Node 22's patch level in the image is not documented, so lint-staged 17's `>=22.22.1` floor is unverified there.
- A cloud session starts from a fresh clone, so git hook shims exist only after an install step runs (`pre-commit install`, `prek install`, `lefthook install`, or husky's `prepare` script) in the setup script or a SessionStart hook.

## Staged files and parallel execution

- **pre-commit** runs against staged files by default and, before running, saves all unstaged changes to a patch and removes them, restoring after (`pre_commit/staged_files_only.py`, `commands/run.py:421`). Hooks run one after another (`_run_hooks` loop); within one hook, filenames are split across processes unless `require_serial: true` ("this hook will execute using a single process instead of in parallel", [pre-commit hooks docs](https://pre-commit.com/#hooks-require_serial)).
- **prek** keeps the same staging semantics ("Unstaged changes are temporarily stashed while the hooks run", prek `docs/running-hooks.md`). It adds hook concurrency: "hooks with the same `priority` may run concurrently", bounded by `PREK_CONCURRENT_HOOKS` (default CPU count), and independent same-depth workspace projects run concurrently ([prek diff doc](https://prek.j178.dev/diff/)).
- **lefthook** passes `{staged_files}` (or `{all_files}`, `{push_files}`, a custom `files:` command) per job, filtered by `glob`/`exclude`. For a pre-commit hook that uses staged files, it hides the unstaged parts of partially staged files and restores them afterwards (`internal/run/controller/guard.go`, `withHiddenUnstagedChanges`, enabled in `controller.go` when `config.HookUsesStagedFiles`). `stage_fixed: true` re-adds files a fixer changed. Jobs run sequentially unless `parallel: true` ([parallel doc](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/parallel.md)).
- **lint-staged** runs tasks only on staged files, takes a backup `git stash` first, hides unstaged changes of partially staged files by default (`--hide-unstaged` hides all), and auto-stages task modifications. "By default lint-staged will run configured tasks concurrently": commands for different globs start together; commands within one glob's array run in sequence ([lint-staged README](https://github.com/lint-staged/lint-staged#task-concurrency)). husky only wires the git hook to a shell script; it does no file selection.

## Multi-language support without a Node or Python dependency

- **pre-commit** itself needs Python. It then builds an isolated env per hook for many languages (python, node, golang, rust, ruby, dotnet, docker, and more) and bootstraps some toolchains: "pre-commit will bootstrap `go` if it is not present" (3.0.0+); node hooks "work without any system-level dependencies" via nodeenv ([supported languages](https://pre-commit.com/#supported-languages)).
- **prek** covers "every language available in `pre-commit`, plus Bun, Deno, mise, and PHP", and "automatically installs managed toolchains when needed for Python, Node.js, Bun, Deno, Go, mise, Rust, and Ruby". `language_version: system` (or `only-system`) forbids downloads and uses the machine's toolchain ([language support](https://prek.j178.dev/reference/language-support/)). Downloaded toolchains are checksum-verified against the upstream's published checksum; "`uv` downloads are not covered by this behavior yet" ([prek diff doc](https://prek.j178.dev/diff/)).
- **lefthook** is language-agnostic: a job is a shell command, so it runs anything already on PATH, and installs nothing. Its `setup:` list (2.1.2+) runs before jobs, and the doc's example is an `if ! command -v ...; then go install ...` guard ([setup doc](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/setup.md)).
- **husky + lint-staged** can run any language's commands, but the runner itself requires Node and a `package.json`, which a Go, Rust or Python repo does not otherwise have.

## Hook pinning and supply-chain posture

- **pre-commit**: `rev` per remote repo; the docs state pre-commit "assumes that the value of `rev` is an immutable ref" and caches a mutable ref at install time without updating it ([advanced docs](https://pre-commit.com/#using-the-latest-version-for-a-repository)). `autoupdate --freeze` stores commit hashes instead of tags. No PyPI provenance attestation on 4.6.2 (PyPI integrity API returned 404).
- **prek**: same `rev` model plus `prek update --freeze`, validation of pinned SHAs against upstream refs "including impostor-commit detection", `--cooldown-days` to hold back fresh releases, and `update --check` for CI. Its [security guide](https://prek.j178.dev/security/) calls a full SHA "the strongest Git pin" and notes tags can be moved. prek's own releases carry GitHub attestations (2 found for the Linux gnu tarball digest), PyPI provenance (HTTP 200), and npm provenance.
- **lefthook**: remote configs pin via `ref`, documented as "An optional *branch* or *tag* name" ([ref doc](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/ref.md)); a commit SHA is not documented. Local jobs run tools the repo already pins (lockfile, go.mod), so lefthook adds no pin of its own. Releases ship `lefthook_checksums.txt` and GitHub attestations via `actions/attest` (`.github/workflows/release.yml`); npm has provenance; PyPI does not (404).
- **husky + lint-staged**: pinned by package.json and the lockfile; both have npm provenance. Tools they call are pinned however the repo pins them.
- **Maintainer concentration** (share of commits among the top 100 contributors, `gh api repos/<r>/contributors`, approximate): pre-commit asottile 86%, prek j178 86%, husky typicode 87%, lefthook mrexox 71%, lint-staged iiroj 62% plus okonet 21%. Every option leans on one or two people.

## Adoption by the tool vendors

**Vendor-published hook manifests** (`.pre-commit-hooks.yaml`, usable unchanged by pre-commit and prek): astral-sh/ruff-pre-commit, astral-sh/uv-pre-commit, biomejs/pre-commit, golangci/golangci-lint, gitleaks/gitleaks, koalaman/shellcheck-precommit, rhysd/actionlint, DavidAnson/markdownlint-cli2, adrienverge/yamllint, psf/black-pre-commit-mirror, hadolint/hadolint, crate-ci/typos, trufflesecurity/trufflehog, google/yamlfmt. Prettier and ESLint publish none: `pre-commit/mirrors-prettier` is archived and `pre-commit/mirrors-eslint` is run by the pre-commit org, not ESLint. Rust's rustfmt/clippy have only third-party wrappers (e.g. doublify/pre-commit-rust). No linter vendor was found publishing a lefthook or lint-staged config; those runners call the tool's CLI directly, so they need no manifest.

**What vendor docs recommend:** Prettier's pre-commit page lists lint-staged first, then pretty-quick, Husky.Net, git-format-staged, Lefthook, a shell script ([prettier/docs/precommit.md](https://github.com/prettier/prettier/blob/main/docs/precommit.md)). Biome's git-hooks recipe lists Lefthook first, then Husky (with lint-staged or git-format-staged), then pre-commit ([biomejs/website recipes/git-hooks.mdx](https://github.com/biomejs/website/blob/main/src/content/docs/en/recipes/git-hooks.mdx)).

**What vendors use in their own repos** (probed root files and package.json):

| Repo | Runner found |
|:--|:--|
| astral-sh/ruff | `.pre-commit-config.yaml` using prek-only `priority:` keys and `# frozen:` SHAs, so it runs under prek, not upstream pre-commit |
| eslint/eslint | yorkie + lint-staged |
| typescript-eslint/typescript-eslint | husky + lint-staged |
| vitejs/vite | simple-git-hooks + lint-staged |
| astral-sh/uv, biomejs/biome, prettier/prettier, golangci/golangci-lint, rust-lang/rust-clippy, microsoft/TypeScript, oxc-project/oxc, denoland/deno | none detected |
| anthropics/claude-code, anthropics/anthropic-sdk-python, anthropics/claude-code-action | none detected |

prek's README lists adopters including CPython, Airflow, FastAPI, ruff, ty, Sentry, Home Assistant and Godot (self-reported; not re-verified per repo except ruff).

**Harness-adjacent features.** lefthook 2.x has a beta `ai:` key that makes `lefthook install` write Claude Code hooks into `.claude/settings.json` (event name mapped to a lefthook hook), preserving user entries. The doc says generated commands use the `lefthook` config value when set, "otherwise the absolute path of the lefthook binary that ran `install`" ([ai doc](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/ai.md)), which would put a machine-specific path into a committed file. prek ships an agent skill (`gh skill install j178/prek prek`).

## Reuse of an existing `.pre-commit-config.yaml`

- pre-commit: native.
- prek: "Existing `.pre-commit-config.yaml` and `.pre-commit-config.yml` files work in `prek`", as do hook repos' `.pre-commit-hooks.yaml`; only `pre-commit hazmat` is unimplemented. Using prek-only keys (`priority`, `repo: builtin`, `env`, `groups`, glob mappings) or `prek.toml` breaks portability back to upstream pre-commit ([compatibility](https://prek.j178.dev/compatibility/)).
- lefthook: no importer found in its docs; a pre-commit config must be rewritten as jobs, and remote-hook repos become direct tool invocations the repo must install.
- husky + lint-staged: no reuse.

## Speed

The docs do not disagree so much as not overlap: prek publishes a benchmark against pre-commit only (macOS M3 Pro, 960 files, 13 `pre-commit-hooks` hooks: pre-commit 1,737 ms, prek 1,438 ms without its fast path, 135 ms fully optimized; framework-only 1 no-op hook 3.30x faster, 10 hooks 1.80x) ([prek benchmark](https://prek.j178.dev/benchmark/)). lefthook's README claims "Fast" with no published numbers (its benchmark wiki links are commented out). husky claims "runs in ~1ms", which covers husky alone, not lint-staged. So I measured.

**Setup.** Scratch clone of this repo (292 tracked files: 154 `.sh`, 23 `.json`, 94 `.md`), Intel i7-10750H (12 threads), Linux, git 2.53.0, Node 24.20.0, shellcheck 0.10.0, jq 1.8.1. Three staged files (2 `.sh`, 1 `.json`) and one partially staged `.sh` with an unstaged tail, so every runner exercises its stash/hide path. Harness: 3 warmups, then 20 (or 15) interleaved runs per command, wall time of `subprocess.run`, median reported. Script and configs lived in the scratchpad only.

**Run A: identical local hooks in all four runners** (`shellcheck -S error` on shell files, `jq empty` on JSON, one always-run `true`):

| Command | Median | Overhead over bare tools |
|:--|--:|--:|
| bare tools, invoked directly | 52 ms | 0 |
| `prek run` (sequential) | 72 ms | ~20 ms |
| `prek run`, all three at one `priority` | 70 ms | ~18 ms |
| `lefthook run pre-commit`, `parallel: true` | 96 ms | ~44 ms |
| `lefthook run pre-commit`, sequential | 99 ms | ~47 ms |
| `node_modules/.bin/lint-staged` | 170 ms | ~117 ms |
| `pre-commit run` | 171 ms | ~119 ms |
| `npx lint-staged` | 373 ms | ~321 ms |

**Run B: remote `pre-commit/pre-commit-hooks` v6.0.0 pinned by SHA** (trailing-whitespace, end-of-file-fixer, check-yaml, check-json, check-merge-conflict, check-added-large-files), pre-commit vs prek only since the others cannot consume it:

| Command | Median |
|:--|--:|
| `pre-commit run -a` (292 files) | 448 ms |
| `prek run -a` | 32 ms |
| `PREK_NO_FAST_PATH=1 prek run -a` | 355 ms |
| `pre-commit run` (staged) | 270 ms |
| `prek run` (staged) | 35 ms |
| cold `install-hooks`: pre-commit / prek | 3.84 s / 2.92 s |
| hook cache after install: pre-commit / prek | 14 MB / 6.3 MB |

**Reading.** Framework overhead ranks prek < lefthook < pre-commit ≈ lint-staged, but every runner stays under 0.2 s on this repo; a real linter or typechecker dominates the total, as prek's own benchmark notes. prek's large win in run B comes from its Rust re-implementations of `pre-commit-hooks` (fast path), not from generic hook dispatch. Concurrency gained little here because shellcheck is the only non-trivial hook.

## Where evidence is thin

- **Cloud `git clone` of unattached public hook repos** is undocumented; it decides whether any `repo: https://github.com/...` config (pre-commit, prek, lefthook `remotes:`) works in a cloud session. Needs a probe in a user-opened web session.
- Node 22's exact version in the cloud image (against lint-staged 17's `>=22.22.1`) is undocumented.
- Speed was measured on one small repo, one machine, warm caches; no large monorepo and no cold cloud VM. Commit-time cost through the git shim was not measured separately from `run`.
- Vendor adoption is a sample of well-known repos, not a census; "none detected" means no runner file at the paths probed, not that the project forbids hooks.
- lefthook `ref` accepting a commit SHA is undocumented, not tested.
- prek's adopter list is self-reported.
