# Harness profile

Schema: 2

Written by `/setup-harness`, which reads it back on a re-run. Facts sit on `Label:` lines; prose under a heading is yours and nothing parses it. A budget override reads `override <N>s: <reason>`.

## Claude Code

Floor: 2.1.277

## Check entry point

Location: scripts/check.sh

## Budgets

Edit: default
Turn: default
Commit: default
Full: default
Cloud setup: default

## Cloud

Verdict: cloud-first
Setup: .claude/hooks/cloud-setup.sh
Allowlist: None.
Proof: 07c01e59276af3a29e3ea8151bbddf41a589930d

## Roots

Root: None.

## Local-only

Local-only: None.

## Declined

Declined: tests/fixtures/catalog/rust/clean/Cargo.toml as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/python/clean/pyproject.toml as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/js-ts/clean/package.json as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/js-ts/bad/attw/package.json as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/js-ts/bad/publint/package.json as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/go/clean/go.mod as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/java-kotlin/clean/pom.xml as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/java-kotlin/clean/build.gradle as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/dotnet/clean/src/Seed/Seed.csproj as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/dotnet/clean/tests/Seed.Tests/Seed.Tests.csproj as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: tests/fixtures/catalog/dotnet/bad/package-validation/src/Seed/Seed.csproj as a root: catalog-trial fixture, a deliberately bad or byte-exact input scripts/catalog-trial.sh reads, not code this repo ships
Declined: shfmt: its default tab indent rewrites every indented line of this repo's two-space scripts, a change to all five skills; no Go toolchain on the maintainer's machine
Declined: markdownlint-cli2: 264 findings over the skills' prose (MD024 fires on the catalog's repeated tool headings by design); adopting it is its own ticket, and house-style and prose-budget already hold these files
Declined: Prettier on Markdown: rewrites 40 files across all five skills; its own ticket, as markdownlint-cli2
