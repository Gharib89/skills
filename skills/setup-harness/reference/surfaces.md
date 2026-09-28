# Surfaces and behaviour tools

## Contents

- [Evidence](#evidence)
- [Web UI](#web-ui)
- [Library](#library)
- [API and CLI](#api-and-cli)
- [The run recipe](#the-run-recipe)

A **surface** is what the repo lets someone drive from outside its test suite: a web UI, an API, a CLI or a library's public API. Surfaces are worked out afresh on every run from the evidence below and never written to the profile. Each detected surface's tools are proposed on their own; with none detected, nothing here is proposed, the run recipe Offer included. A **behaviour tool** drives one surface, on `full` or on demand, never on a faster rung.

## Evidence

Tracked files only, per member, as detection scans them:

| Surface | Evidence |
|---|---|
| web UI | a `playwright.config.*`, or `playwright` or `@playwright/test` among a member's declared dependencies |
| library | the member's root matches its catalog entry's `Library:` signal |
| API | a server framework among the declared dependencies (FastAPI, Flask, Django, Express, Fastify, Spring Boot, a `Microsoft.NET.Sdk.Web` project), or a tracked OpenAPI or GraphQL schema |
| CLI | an npm `bin`, a pyproject `[project.scripts]`, a Cargo bin target (`src/main.rs`, `[[bin]]`), a Go `package main` |

The header of the present step, and of the gap report, lists each surface with its member and evidence paths (`web UI: web/ (web/playwright.config.ts)`), or `surfaces: none`.

## Web UI

The catalog's `browser` role names the tool. The repo's own Playwright Test suite goes on `full` only, one `FULL_ROWS` row per member (`e2e-web|cd web && pnpm exec playwright test`): it needs the app's server and a build, so it never runs on `turn`, and `--only-changed` is never offered. The harness installs no Playwright of its own: a web UI without one has no suite to wire, and the on-demand driver is `npx playwright cli` from the repo's own `playwright`. Standalone `@playwright/cli` and `@playwright/mcp` are not defaults, because each pins a prerelease core with a second browser revision, and npm `chromium-cli` is a third party's placeholder, never installed.

**The cloud browser step**, cloud-first only, written whenever web UI evidence exists, since both the suite and the on-demand driver need a browser: one `BROWSERS` row per member in `.claude/hooks/cloud-setup.sh` ([cloud.md](cloud.md) `## Writing the cloud setup`). The cloud image sets `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` and ships only one Playwright revision there, so a repo on any other Playwright version cannot launch until its own revision is installed into that directory. The step never overrides the variable, so no environment has to reach the agent's Bash tool. It reads the version at run time from the member's installed Playwright, after the frozen install, and does nothing when that revision's directories are already complete. Its route:

- **`vendor`**, when `Allowlist:` names `cdn.playwright.dev`: `playwright install --with-deps chromium`.
- **`mcr`**, otherwise: the browser directories copied out of the vendor image `mcr.microsoft.com/playwright:v<version>-noble` (about 70 s on the Default network), which needs dockerd, so the cloud setup carries the `dockerd` row of cloud.md's step 5.

At write time, check the MCR tag for the member's locked Playwright version exists: `curl -s -o /dev/null -w '%{http_code}' -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' https://mcr.microsoft.com/v2/playwright/manifests/v<version>-noble` answers `200`. The `Accept` header is required: recent tags exist only as an OCI index, which a bare request answers `404`. Any other answer labels the browser part `needs the Custom allowlist: cdn.playwright.dev`, and the human is asked whether their environment admits it. The browsers belong to the repo's own locked Playwright, so neither route is an install-check unit: they are exempt as the frozen install is. A hand-placed Chrome for Testing binary is never written, since no vendor documents that route.

## Library

The catalog's `public API` role names the tool, `Rung: full` only: each needs a build or a pack, and a finding may be an intended break the human weighs. Each is a `FULL_ROWS` row per library member and an install-check row, droppable, so a repo that does not publish from this tree drops it with a reason. Defaults: publint plus `@arethetypeswrong/cli` for npm, griffe for Python, cargo-semver-checks for Rust (its catalog `Local-only:` line holds unless the human overrides the `Cloud setup:` budget with a reason), package validation for .NET. Go and Java get no default.

## API and CLI

Nothing is written for either. An API's check is the run recipe's launch-and-`curl` smoke; a CLI's is its built binary under the repo's own test runner.

## The run recipe

When at least one surface exists and the repo has no `.claude/skills/run-*/`, the report carries an Offer: "type `/run-skill-generator`", Claude Code's bundled skill that records how to launch and drive the app as a committed `run-<name>` skill a cloud session also carries. The skill cannot run it for the human, since it takes no model invocation. Declined with a reason, it is recorded `Declined: run recipe: <reason>`; otherwise it is offered again every run.
