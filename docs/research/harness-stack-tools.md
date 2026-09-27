# Per-stack tool facts for the agent harness catalog

Research for [Per-stack tool facts](https://github.com/Gharib89/skills/issues/348), part of the map [setup-harness: a Setup skill for the agent harness](https://github.com/Gharib89/skills/issues/333). Question: per stack, what does a catalog entry need to know (vendor tools and their trust tier, hook repo or local hook, a cloud-passing install route, how to find affected tests)? This file gathers facts; the catalog design belongs to the tickets that consume it.

Measured 2026-09-27. Versions are the registry's latest that day. Timings come from one local 12-core Linux machine on small real or synthetic projects (caddy for Go, ripgrep for Rust, the `rich` sdist for Python, this repo's 41 shell scripts, an 800-file synthetic TS project, toy .NET and Gradle projects), never from a cloud VM, so treat them as lower bounds. Probe scripts stayed in the session scratchpad.

Terms: **tier** as in [Install-check procedure](https://github.com/Gharib89/skills/issues/340) (1 Anthropic-authored, 2 the tool's own vendor, 3 skill repos the target repo pins, none otherwise). **Cloud** facts build on [Web-session probe of cloud setup unknowns](https://github.com/Gharib89/skills/issues/342) (registries, apt and public `git clone` pass; unattached GitHub release assets, `codeload.github.com`, NodeSource, LLVM apt and the Playwright CDNs are blocked). **Rungs** and budgets are from [Rung budgets and how a run measures them](https://github.com/Gharib89/skills/issues/343): edit 5 s per file, turn 60 s, commit 30 s, full 10 min.

## Headline findings

1. **TypeScript 7 is `latest`, and the tier-1 `typescript-lsp` plugin breaks on it.** `npm view typescript dist-tags` gives `latest: 7.0.2` (the native Go compiler). The plugin runs `typescript-language-server`, which needs `tsserver.js`; TS 7 ships none, and the server exits with "provides no tsserver.js" (reproduced, also in the side-by-side TS 6 layout Microsoft's blog recommends). Microsoft's own `tsc --lsp --stdio` from `typescript@7` answers `initialize` (probed; the flag is absent from `tsc --help --all`). typescript-eslint 8.70.1 still requires `typescript >=4.8.4 <6.1.0`.
2. **Gradle's wrapper cannot bootstrap in the cloud.** `services.gradle.org` is allowlisted, but every distribution URL answers `307` to `github.com/gradle/gradle-distributions/releases/download/...` (`curl -sI https://services.gradle.org/distributions/gradle-9.1.0-bin.zip`), an unattached release asset. Not probed in a cloud VM; inferred from the release-asset rule. The preinstalled `gradle` (version undocumented) is the route; noble's apt `gradle` is 4.4.1.
3. **A tier-1 LSP plugin can name a binary no vendor publishes.** The plugin config is Anthropic-authored, but `typescript-language-server` (typescript-language-server org) and `csharp-ls` (razzmatazz) are third-party. Every other official LSP binary is its vendor's (pyright Microsoft on npm, gopls Go team, rust-analyzer Rust project, jdtls Eclipse, kotlin-lsp JetBrains). The catalog must decide whether "named by tier-1 glue" admits a binary.
4. **Vendor hook repos are the minority, and several are unusable in the cloud or in a lockfile repo.** Vendor-published `.pre-commit-hooks.yaml`: ruff, ty, golangci-lint, ESLint, Biome, oxlint, oxfmt, ShellCheck. None for mypy, pyright, shfmt, Prettier, TypeScript, gofmt/vet, staticcheck, rustfmt/clippy, nextest, dotnet, any Java/Kotlin tool. ShellCheck's vendor hook is `docker_image`. So `local`/`system` hooks from the repo's lockfile or toolchain are the default for every stack.
5. **Many vendor-documented install routes are blocked; a registry route exists for everything except kotlin-lsp.** Blocked: golangci-lint `install.sh`, nextest `get.nexte.st`, ShellCheck, ktlint, detekt and google-java-format release binaries, Astral curl installers, the Gradle wrapper, `dotnet-install.sh` (redirects to `builds.dotnet.microsoft.com`, not allowlisted). kotlin-lsp downloads only from `download.jetbrains.com` (not allowlisted) and its brew formula is `depends_on :macos`, so the Anthropic plugin's install line fails on Linux. Moot for the cloud (LSP never starts there) but it breaks a local Linux install.
6. **Typecheckers are project-scoped in every stack**, so they belong to the turn rung, not the edit rung. `tsc` refuses file arguments with a tsconfig (`TS5112`); `go vet file.go` fails on sibling symbols; clippy and `cargo check` are per crate; `dotnet build` and `gradle compileJava` are per project. Formatters and most linters do accept one file.
7. **Exact, dependency-graph affected-test selection is native only in Go (test cache) and Gradle (up-to-date checks); plugins give it for Python (pytest-testmon), JS (Vitest `related`, Jest `--findRelatedTests`) and Rust (nextest `rdeps()`).** Shell (bats), node:test, Maven and .NET have name filters only, so the harness maps changed files to test targets itself.
8. **Registry provenance is uneven.** Attested: Biome, oxlint, oxfmt, typescript-language-server, vitest, Playwright, bash-language-server (npm SLSA), pytest and pytest-xdist (PyPI), cargo-nextest (crates.io Trusted Publishing), roslyn-language-server (Microsoft author signature). Not attested: ruff, ty, mypy on PyPI (`0 of 18` ruff 0.16.9 files carry provenance), typescript, eslint, prettier, jest, pyright on npm, Go modules (sumdb integrity only), csharp-ls (nuget.org repository signature only), Maven Central jars (PGP `.asc` only).

## Summary table

"Hook" names a vendor hook repo, or `local` when the tool runs as a `repo: local`, `language: system` hook. "Route" is the cloud-passing install.

| Stack | Role | Tool (publisher) | Tier | Latest | One file? | Hook | Route |
|:--|:--|:--|:--|:--|:--|:--|:--|
| Shell | lint | ShellCheck (koalaman) | 2 | 0.11.0 | yes, 0.85 s | `koalaman/shellcheck-precommit` (Docker only), else `local` | apt `shellcheck` 0.9.0; latest only via third-party `shellcheck-py` wheel |
| Shell | format | shfmt (mvdan) | 2 | 3.14.1 | yes, 0.02 s | `local` | `go install mvdan.cc/sh/v3/cmd/shfmt@v3.14.1`; apt 3.8.0 |
| Shell | LSP | bash-language-server (bash-lsp) | 2, no Anthropic plugin | 5.8.1 | n/a | n/a | `npm i -g bash-language-server@5.8.1` |
| Python | lint + format | ruff (Astral) | 2 | 0.16.9 | yes, 0.03 s | `astral-sh/ruff-pre-commit` (`ruff-check`, `ruff-format`) | uv dev dep / `uv tool install ruff==0.16.9` |
| Python | typecheck | mypy (python org) | 2 | 2.3.1 | project, 0.21 s warm, 3.5 s cold | `local` (only `pre-commit/mirrors-mypy`, not vendor) | uv dev dep |
| Python | typecheck | pyright (Microsoft, npm) | 2 | 1.1.414 | 4.3 s warm per call | `local` | `npm i -g pyright@1.1.414` (PyPI `pyright` is third-party) |
| Python | typecheck | ty (Astral), beta | 2 | 0.0.84 | project, 0.2 s | `astral-sh/ty-pre-commit` (can mutate `uv.lock`) | uv dev dep |
| Python | LSP | `pyright-langserver` via `pyright-lsp` | 1 config, 2 binary | 1.1.414 | n/a | n/a | npm, as above |
| JS/TS | typecheck | `tsc` (Microsoft) | 2 | 7.0.2 | no (`TS5112`), project 0.6 s cold / 0.2 s warm on 800 files | `local` | repo lockfile (`npm ci`) |
| JS/TS | lint | ESLint (OpenJS) | 2 | 10.11.0 | yes, 0.35 s | `eslint/eslint` (`eslint`, isolated env) | lockfile |
| JS/TS | format | Prettier | 2 | 3.9.9 | yes, 0.26 s (6 s for 800 files) | `local` (mirrors archived) | lockfile |
| JS/TS | lint + format | Biome (biomejs) | 2 | 2.5.14 | yes, 0.07 s | `biomejs/pre-commit` | lockfile (binary via npm optionalDependencies) |
| JS/TS | lint / format | oxlint 1.85.0, oxfmt 0.70.0 (oxc-project) | 2 | see left | yes, 0.07 s | `oxc-project/mirrors-oxlint`, `mirrors-oxfmt` | lockfile (binary via npm) |
| JS/TS | LSP | `typescript-language-server` via `typescript-lsp` | 1 config, binary third-party | 6.0.1 | n/a | n/a | npm; **fails on TS 7**; needs Node >=22.22.2 |
| Go | format | gofmt (Go team) | 2 | toolchain (go1.27.1) | yes, 0.01 s | `local` | preinstalled Go |
| Go | vet / typecheck | `go vet`, `go build` (Go team) | 2 | toolchain | package only; 0.3 s warm, 10 s cold | `local` | preinstalled Go |
| Go | lint | staticcheck (dominikh) | 2 | 0.8.1 (2026.2.1) | package only | `local` | `go tool` directive or `go install ...@v0.8.1` |
| Go | lint | golangci-lint (golangci) | 2 | 2.14.0 | package; `fmt` per file 0.15 s | `golangci/golangci-lint` (`language: golang`) | `go get -modfile=tools/go.mod -tool ...@v2.14.0` (vendor discourages) |
| Go | LSP | gopls via `gopls-lsp` | 1 config, 2 binary | 0.23.0 | n/a | n/a | `go install golang.org/x/tools/gopls@v0.23.0` |
| Rust | format | rustfmt (Rust project) | 2 | 1.9.0 (stable 1.98.1) | yes, 0.02 s (needs `--edition`) | `local` | `rust-toolchain.toml` components |
| Rust | lint / typecheck | clippy, `cargo check` | 2 | 0.1.98 | crate only | `local` | `rust-toolchain.toml` components |
| Rust | test runner | cargo-nextest (nextest-rs) | 2 | 0.9.146 | n/a | none | `cargo install --locked cargo-nextest@0.9.146` (219 s build) |
| Rust | LSP | rust-analyzer via `rust-analyzer-lsp` | 1 config, 2 binary | toolchain | n/a | n/a | `rustup component add rust-analyzer` |
| .NET | format + analyzers | `dotnet format` (Microsoft) | 2 | SDK | `--include`, but loads the project: 6.1 s; `whitespace --folder` 1.6 s | `local` | apt `dotnet-sdk-10.0=10.0.112-0ubuntu1~24.04.1` |
| .NET | typecheck | `dotnet build -warnaserror` | 2 | SDK | project, 1 s warm, 3 s cold | `local` | apt |
| .NET | LSP | `csharp-ls` via `csharp-lsp` | 1 config, binary third-party | 0.28.0 (needs .NET 10) | n/a | n/a | `dotnet tool install csharp-ls --version 0.28.0` |
| .NET | LSP | `roslyn-language-server` (Microsoft) | 2, no Anthropic plugin | 5.12.0-1.26426.8, prerelease only | n/a | n/a | NuGet dotnet tool |
| Java | format | google-java-format (Google) | 2 | 1.36.1 | yes, 0.45 s | `local` | Maven Central `-all-deps.jar` or Spotless |
| Kotlin | lint + format | ktlint (ktlint org) | 2 | 1.8.0 | yes, 1.0 s | `local` | Maven Central `ktlint-cli-1.8.0-all.jar` |
| Kotlin | format | ktfmt (Kotlin org, group `com.facebook`) | 2 | 0.64 | yes, 0.73 s | `local` | Maven Central |
| Kotlin | lint | detekt (detekt org) | 2 | 1.23.8 | files; type rules need the build | `local` | Maven Central / Gradle plugin portal |
| JVM | wrapper | Spotless (DiffPlug) | 2 | 8.10.3 Gradle, 3.10.3 Maven | `-PspotlessIdeHook=<path>` | `local` | Gradle plugin portal |
| JVM | typecheck | `gradle compileJava` / `mvn compile` | 2 | build tool | project, 0.9 s warm, 13.6 s cold | `local` | preinstalled JDK 21 + Gradle/Maven |
| Java | LSP | jdtls via `jdtls-lsp` | 1 config, 2 binary | 1.61.0 | n/a | n/a | `download.eclipse.org` tarball (allowlisted, not probed) |
| Kotlin | LSP | kotlin-lsp via `kotlin-lsp` (JetBrains, Alpha) | 1 config, 2 binary | 263.4702.0 | n/a | n/a | **none**: `download.jetbrains.com` not allowlisted, brew macOS-only |

## Cloud image baseline

From [Cloud environments, Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools): "Python 3.x with pip, poetry, uv, black, mypy, pytest, ruff"; "Node.js 20, 21, and 22, with npm, yarn, pnpm, bun, eslint, prettier, chromedriver"; "Java: OpenJDK 21 with Maven and Gradle"; "Go with module support"; "Rust: rustc and cargo". ".NET SDK aren't pre-installed even when their package registries are on the default allowlist." ShellCheck is not preinstalled (the page's own setup-script example installs it). No versions are documented (`check-tools` on the VM reports them), so preinstalled tools are unpinned image versions: the harness pins and runs its own (`node_modules/.bin`, `uv run`), never the global copy.

Allowlist gaps that matter here: listed and relevant but **not probed**: `download.eclipse.org`, `ppa.launchpad.net`, `plugins.gradle.org`, `rustup.rs`, `dotnet.microsoft.com`, `packages.microsoft.com`. Not listed: `builds.dotnet.microsoft.com`, `ci.dot.net`, `download.jetbrains.com`, `open-vsx.org`, `get.nexte.st`. A listed host is not proof of reach: `codeload.github.com` and `storage.googleapis.com` are listed yet the web probe found them blocked.

## Shell

**Tools.** No language-project tooling exists; ShellCheck (koalaman) and shfmt (mvdan) are the dominant vendor tools, both tier 2. No typechecker. bash-language-server (npm, bash-lsp org, needs Node >=20) shells out to `shellcheck` and `shfmt` when on PATH and silently loses diagnostics without them (its README). No Anthropic shell LSP plugin (`gh api repos/anthropics/claude-plugins-official/contents/plugins`).

**Hooks.** `koalaman/shellcheck-precommit` (hook `shellcheck`, v0.11.0) is `language: docker_image` on `docker.io/koalaman/shellcheck:v0.11.0`, so it needs a Docker daemon. mvdan publishes no hook; `scop/pre-commit-shfmt` and `MaxWinterstein/shfmt-py` are third-party. `shellcheck-py/shellcheck-py` is third-party (asottile, ryanrhee). Use `local` hooks: `shellcheck` with `types: [shell]`, `shfmt -d`.

**Install.** apt on noble gives `shellcheck=0.9.0-1` and `shfmt=3.8.0-1` (Launchpad `getPublishedSources`), both behind. shfmt latest: `go install mvdan.cc/sh/v3/cmd/shfmt@v3.14.1` (its go.mod says `go 1.26.0`, so an older Go fetches a toolchain through the proxy). ShellCheck latest has no tier-2 registry route in the cloud: the release binaries are blocked; Hackage `cabal install ShellCheck-0.11.0` needs GHC (compile time unmeasured); the PyPI `shellcheck-py==0.11.0.1` wheel bundles koalaman's binary but is third-party. The catalog's honest default is apt's 0.9.0.

**Affected tests.** bats-core has no change-based mode (`libexec/bats-core/bats` usage: `--filter`, `--filter-tags`, `--filter-status failed`, `--jobs` with GNU parallel). Options: map `x.sh` to `x.bats` by name from `git diff` (heuristic, misses `source` dependencies) or run the whole suite. Install: apt `bats=1.10.0-1` or `npm i -g bats@1.13.0` (no provenance, lags 1.14.0).

**Traps.** `shellcheck -x` results depend on cwd and `source-path`; shfmt reads `.editorconfig`.

## Python

**Tools.** No official linter, formatter or typechecker: [PyPA tool recommendations](https://packaging.python.org/en/latest/guides/tool-recommendations/) cover packaging only; [typing.python.org](https://typing.python.org/en/latest/) lists mypy, pyrefly, pyright, ty and Zuban neutrally. ruff (Astral) lints and formats per file in milliseconds and has `ruff server`. mypy is the python org's; pyright's tier-2 route is npm (the PyPI `pyright` wrapper by Robert Craigie is called "community-maintained" in Microsoft's `docs/installation.md`; its wheel bundles the JS and still needs Node, downloading it via nodeenv when absent). ty (Astral) is beta ("ty is currently in beta", 0.0.x, classifier "4 - Beta"). basedpyright is a third-party fork.

**Hooks.** `astral-sh/ruff-pre-commit` v0.16.9: `ruff-check`, `ruff-format` (lint with `--fix` must precede format). `astral-sh/ty-pre-commit`: `ty` runs `uv check ... --ty-version=0.0.84`, whole project, and "may create or update `uv.lock`" unless `args: [--isolated]`. mypy and pyright: none from the vendor. For a uv repo: `local` hooks `uv run --frozen ruff check --force-exclude`, `uv run --frozen ruff format --force-exclude`, `uv run --frozen mypy .` (`pass_filenames: false`).

**Install.** PyPI via uv (`uv sync --frozen` from the lockfile, or `uv tool install ruff==0.16.9`). noble has no `ruff` or `pyright` package and `mypy=1.9.0`. Blocked: Astral's curl installers and release binaries.

**Affected tests.** pytest built-ins (`--lf`, `--ff`, `--nf`, `--sw`) reorder or rerun failures; none is change-based ([pytest cache docs](https://docs.pytest.org/en/stable/how-to/cache.html)). **pytest-testmon 2.2.0** (tarpas, Beta, needs `coverage<8`) is exact at block level from coverage data in `.testmondata`, "works independently of version control", needs a first full run, tracks env vars and package versions but not "static files" or external services ([testmon.org](https://testmon.org)); measured: after editing `a.py` only `test_a` ran. It crashes with `KeyError: 'lf'` under `-p no:cacheprovider`. pytest-picked selects only modified test files, so a source-only edit selects nothing: unfit for the turn rung. pytest-xdist `-n auto` speeds, it does not select.

**Traps.** Explicit file paths bypass ruff `exclude` without `--force-exclude`. `mirrors-mypy` runs in an isolated venv without project deps. pyright's CLI costs 4 to 10 s per call (Node start, no cache): turn rung or LSP only.

## JavaScript and TypeScript

**Tools.** No language-vendor linter or formatter; Microsoft publishes the compiler only. `typescript@7.0.2` is the native Go compiler, delivered as a Node shim plus a per-platform npm package (`@typescript/typescript-linux-x64`); [the TS 7 announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) retires `@typescript/native-preview` and says TS 7 has no stable programmatic API. `tsc --noEmit src/x.ts` fails with `TS5112: tsconfig.json is present but will not be loaded if files are specified on commandline`; `--ignoreConfig` drops the project's options, so only `tsc -p .` is correct. `--incremental` mainly speeds the no-change case (TS 7: 0.22 s warm vs 0.56 s after a mid-chain edit vs 0.61 s cold; TS 6.0.3: 3.2 s cold, 1.3 s warm). ESLint 10 resolves `eslint.config.*` from the file's directory upward.

**Hooks.** `eslint/eslint` ships `.pre-commit-hooks.yaml` (hook `eslint`, `language: node`, isolated env: flat-config plugins must be listed in `additional_dependencies`). `biomejs/pre-commit` (`biome-ci`, `biome-check`, `biome-format`, `biome-lint`), `oxc-project/mirrors-oxlint`, `oxc-project/mirrors-oxfmt`. Prettier: none (`prettier/pre-commit` and `pre-commit/mirrors-prettier` archived). TypeScript: none. In a lockfile repo all run as `local` hooks from `node_modules/.bin`.

**Install.** The repo's lockfile (`npm ci`, `pnpm install --frozen-lockfile`) from npm, which passes. Biome, oxlint, oxfmt and TS 7 bring native binaries through per-platform npm packages with no postinstall, so no GitHub download.

**LSP.** See headline 1. `typescript-language-server` 6.0.0 raised `engines.node` to `>=22.22.2`, exactly the cloud's Node (moot there since LSP never starts in the cloud, but a local floor). The `initializationOptions.tsserver.path` workaround toward a TS 6 `tsserver.js` is unverified.

**Affected tests.** Vitest 5.0.2: `vitest related <files> --run` ("works with static imports ... but not the dynamic ones") and `--changed [since]` (git, then the Vite module graph); `forceRerunTriggers` (`package.json`, vite/vitest config) forces a full run. Jest 30.5.2: `--findRelatedTests <files>` (no git, "useful for pre-commit hook integration"), `--onlyChanged`, `--changedSince` (git or hg, static graph); `--watchman` defaults true, use `--no-watchman` without it. node:test: no related or changed flag, only watch mode. Playwright 1.63.0 `--only-changed [ref]` follows imports but its browsers need the blocked CDNs. All measured selections were correct on synthetic chains (about 1.1 s Vitest, 0.56 s Jest).

**Traps.** Installing `typescript@7` and `@typescript/typescript6` under their real names makes `node_modules/.bin/tsc` resolve to 6.0.3 (reproduced on npm 11.19.0; npm 10 unverified); verify with `node_modules/.bin/tsc --version`. npm 11 gates transitive install scripts ("not yet covered by allowScripts").

## Go

**Tools.** Go team (tier 2): gofmt (per file), `go vet` (per package: "synthesizes a virtual package ... In most cases, it is an error" for file arguments, `go help packages`), `go build` as typecheck (caddy: 29 s cold, 4.5 s after an edit). gopls supports "only the two most recent major Go releases" ([go.dev/gopls](https://go.dev/gopls/)). staticcheck (Dominik Honnef) and golangci-lint (golangci org) are tier 2 as their own vendors, not language defaults. The edit rung works as `go vet ./<dir>/` only with a warm cache (0.3 s warm, 9.9 s cold).

**Hooks.** `golangci/golangci-lint` ships `golangci-lint` (`run --new-from-rev HEAD --fix`), `golangci-lint-full`, `golangci-lint-fmt`, `golangci-lint-config-verify`, all `language: golang`; its own comment warns `unused` "won't work as expected" on modified files only. None for gofmt, vet, staticcheck. Pinned tools run as `local` hooks via `go tool`.

**Install.** Pin tools with the tool directive in a separate modfile: `go get -modfile=tools/go.mod -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0`, run `go tool -modfile=tools/go.mod golangci-lint` (first run 2.8 s, then 0.4 s; main `go.mod` untouched). golangci-lint's docs recommend binaries from GitHub releases (blocked) and say `go install` and `go tool` "aren't guaranteed to work" ([install docs](https://golangci-lint.run/docs/welcome/install/local/)); it built cleanly with go1.27.1, so the discouraged route is the only cloud route. `GOTOOLCHAIN` auto-switch downloads `golang.org/toolchain` through the module proxy ([go.dev/doc/toolchain](https://go.dev/doc/toolchain)), which passes. noble apt is too old (Go 1.22, gopls 0.18, no golangci-lint).

**Affected tests.** The test result cache is exact by dependency graph with no git: `go test ./...` reruns only packages whose test binary or opened files changed ([cmd/go, test caching](https://pkg.go.dev/cmd/go#hdr-Test_packages)); `-count=1` disables it. caddy: 18.7 s cold, 8.2 s rerun, 4.1 s after a one-file edit. For an explicit list, `go list -test -deps` gives reverse deps. Fits 60 s warm; a cold first run (29 s build plus 19 s test) is borderline.

**Traps.** The cache (1.8 GB GOCACHE for caddy) only helps if it persists between turns (it does across an idle resume per the web probe). Set `GOTOOLCHAIN=local` to fail fast instead of downloading a toolchain mid-turn.

## Rust

**Tools.** Rust project (tier 2), all rustup components: rustfmt (per file), clippy and `cargo check` (per crate; `clippy-driver` takes only a standalone crate root, [clippy usage](https://doc.rust-lang.org/stable/clippy/usage.html)), rust-analyzer ([binary docs](https://rust-analyzer.github.io/book/rust_analyzer_binary.html)). Stable 1.98.1 per `channel-rust-stable.toml`. ripgrep: `cargo check` 6.1 s cold, 1.2 s after an edit.

**Hooks.** None from the Rust project or nextest (404 on `rust-lang/rustfmt`, `rust-lang/rust-clippy`, `rust-lang/rust`, `nextest-rs/nextest`). `doublify/pre-commit-rust` is third-party (last push 2024-08). `local` hooks: `cargo fmt --check`, `cargo clippy --workspace -- -D warnings`.

**Install.** Pin in `rust-toolchain.toml` (`channel = "1.98.1"`, `components = ["rustfmt","clippy","rust-analyzer"]`, [rustup overrides](https://rust-lang.github.io/rustup/overrides.html)); components come from `static.rust-lang.org`, which passes. Whether the cloud image has `rustup` at all is undocumented ("rustc and cargo"). noble apt is Rust 1.75 with no rust-analyzer. cargo-nextest: `cargo install --locked cargo-nextest@0.9.146` (`--locked` mandatory since 0.9.124, [from-source docs](https://nexte.st/docs/installation/from-source/)) took 219 s, so it belongs in the cloud setup, never in a turn; the recommended `get.nexte.st` redirects to GitHub releases (blocked).

**Affected tests.** Cargo has no changed-files mode and no result cache: map files to crates (`cargo metadata`) and run `cargo test -p <crate>` plus reverse deps. nextest `cargo nextest run -E 'rdeps(<crate>)'` selects the crate and its transitive dependents ([filterset reference](https://nexte.st/docs/filtersets/reference/)); doctests "are currently not supported" ([running](https://nexte.st/docs/running/)). ripgrep: `cargo test --workspace` 6.5 s warm, `rdeps(globset)` 3.5 s; cold `--no-run` 13.6 s. A larger workspace's cold compile can blow 60 s (unverified).

**Traps.** Standalone `rustfmt` defaults to edition 2015 and reads `rustfmt.toml`, not `Cargo.toml`: pass `--edition` or set it in `rustfmt.toml` (false diffs measured otherwise). `rustfmt file.rs` also formats that file's out-of-line `mod` children. `--all-targets` fails on stable when benches use `#![feature(test)]`. The `rust-analyzer` rustup proxy exists before the component does, so probe with `rust-analyzer --version`, not `which`.

## .NET

**Tools.** Microsoft (tier 2): `dotnet format` in the SDK ([docs](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-format)), Roslyn analyzers configured in `.editorconfig` (IDE rules fail the build only with `EnforceCodeStyleInBuild=true`), `dotnet build -warnaserror` as typecheck. `dotnet format --include <file>` still loads the solution (6.1 s full, 3.7 s whitespace on a toy); only `dotnet format whitespace --folder . --include <file>` (1.6 s, no analyzers) fits the edit rung. `csharp-ls` 0.28.0 targets `net10.0` ("requires the .NET 10 SDK or later"; the Anthropic plugin README's ".NET SDK 6.0 or later" is stale). Microsoft's `roslyn-language-server` is on NuGet as a prerelease-only dotnet tool, author-signed by Microsoft, needs `--stdio`.

**Hooks.** None from the vendor (404 on `dotnet/format`, `dotnet/sdk`, `dotnet/roslyn`). `local` hook: `dotnet format --no-restore --verify-no-changes --include` with the SDK pinned by `global.json`; LSP tools pinned in `.config/dotnet-tools.json`, restored with `dotnet tool restore`.

**Install.** apt on noble: `dotnet-sdk-10.0=10.0.112-0ubuntu1~24.04.1` (and `dotnet-sdk-8.0`); .NET 9 only via `ppa:dotnet/backports`. Microsoft says "The Microsoft package repository no longer contains .NET packages for Ubuntu" 24.04 ([install doc](https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu-install)). `dotnet-install.sh` redirects to `builds.dotnet.microsoft.com`, not allowlisted. Canonical ships the 1xx feature band only, so a `global.json` pinning a 4xx SDK breaks on apt.

**Affected tests.** `dotnet test --filter` selects by name or trait only ([selective tests](https://learn.microsoft.com/dotnet/core/testing/selective-unit-tests)). Azure Pipelines Test Impact Analysis lists ".NET Core" as not supported ([TIA](https://learn.microsoft.com/azure/devops/pipelines/test/test-impact-analysis)). So: map changed files to their project and run the test projects that reference it; MSBuild skips unchanged projects. Toy: 2 to 4 s.

**Traps.** `dotnet format` restores implicitly (network) unless `--no-restore`, and "may restore, compile, and run analyzers": trusted code only.

## Java and Kotlin

**Tools.** No language-vendor linter or formatter; the [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html) name only IntelliJ and `kotlin.code.style=official`. Each tool is tier 2 as its own vendor: google-java-format 1.36.1 (needs JDK 21+), palantir-java-format 2.99.0, ktlint 1.8.0 (repo moved to `ktlint/ktlint`; 2.0 alphas under `io.github.ktlint.core`), ktfmt 0.64 (repo `Kotlin/ktfmt`, group still `com.facebook`), detekt 1.23.8 (2.0 alphas under `dev.detekt`), Spotless 8.10.3, Checkstyle 14.1.0, PMD 7.28.0, Error Prone 2.50.0 (versions from `repo1.maven.org` metadata; `search.maven.org` is stale). Formatters take one file in 0.5 to 1 s of JVM start. Gradle 9.8.0 toy: `compileJava` 13.6 s first, 0.9 s warm; cold daemon offline 5.1 s. jdtls 1.61.0 needs a Java 21 runtime and python3 for `bin/jdtls`; it is not on Maven Central. kotlin-lsp is "JetBrains official", Alpha, "partially closed-source".

**Hooks.** None from any vendor (404 on google-java-format, palantir-java-format, ktlint, ktfmt, detekt, spotless, checkstyle, pmd, error-prone, eclipse.jdt.ls, kotlin-lsp). `local` hooks: `java -jar <pinned jar> --dry-run --set-exit-if-changed`, or `./gradlew spotlessCheck` with `pass_filenames: false`.

**Install.** JDK 21, Maven and Gradle are preinstalled (versions undocumented); noble apt `gradle` 4.4.1 is useless, `maven` 3.8.7. Jars from Maven Central (allowlisted, passes) with `.sha1`/`.asc` signatures, or better, pinned through the build (Spotless, detekt plugins from `plugins.gradle.org`). `mvnw` distributions come from `repo1.maven.org` (HTTP 200) and should pass; `gradlew` does not (headline 2). Blocked: ktlint, detekt and google-java-format release binaries. jdtls: `download.eclipse.org/jdtls/milestones/1.61.0/...tar.gz` with a `.sha256` alongside (allowlisted, not probed).

**Affected tests.** Gradle up-to-date checks skip a task when input fingerprints are unchanged ([incremental build](https://docs.gradle.org/current/userguide/incremental_build.html)), so `./gradlew test` reruns only affected modules: exact at module level, no git; `--tests` filters by name. Toy: 0.8 s up-to-date, 1.5 s after an edit. Develocity Predictive Test Selection is ML over build history on a commercial server ([docs](https://docs.develocity.ai/predictive-test-selection/)), not a default. Maven has no test up-to-date skip: map changed files to modules and run `mvn -pl <module> -amd test`; `-Dtest=` filters by name.

**Traps.** Spotless `ratchetFrom 'origin/main'` fails on a shallow clone ("No such reference") until `git fetch origin main`. detekt type resolution and Error Prone need compilation, so they are turn-rung tools.

## Where evidence is thin

- **No timing is from a cloud VM**; core count there is unknown. Mid-size repo fits for the 60 s turn rung are reasoned, not measured, for every stack (toys and small real projects only).
- **Cloud reachability not probed**: Gradle wrapper failure (inferred from the redirect plus the release-asset rule), `download.eclipse.org`, `ppa.launchpad.net`, `plugins.gradle.org`, `rustup.rs`/`sh.rustup.rs`, and the unlisted `builds.dotnet.microsoft.com`, `download.jetbrains.com`, `open-vsx.org`.
- **Cloud image contents**: whether `rustup`, rustfmt, clippy, gopls, Docker daemon or cabal/GHC are present, and the preinstalled Go, Gradle and Maven versions.
- Whether the TypeScript team or Node.js recommend any linter or formatter (not fetched).
- Biome and oxc docs' installer routes (the "blocked vendor route" flag rests on the general rule, not a re-read).
- The `typescript-language-server` `tsserver.path` workaround for TS 7 repos.
- ESLint speed with typed linting (typescript-eslint `projectService`) on one file.
- How prek builds `language: golang` hooks (system Go or a downloaded toolchain).
- Provenance of rustup components beyond the channel manifest's sha256.
- Change-based modes in shell test runners other than bats (shellspec not researched).
