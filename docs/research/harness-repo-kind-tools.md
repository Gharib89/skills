# Behaviour tools per repo kind for the agent harness catalog

Research for [Verification tools per repo kind](https://github.com/Gharib89/skills/issues/353), part of the map [setup-harness: a Setup skill for the agent harness](https://github.com/Gharib89/skills/issues/333). Question: for each repo kind (web UI, API/service, CLI, library), which tool from the trusted tiers checks behaviour beyond the test suite, and how does it reach a local and a cloud session?

Measured 2026-09-27 on Claude Code 2.1.283. Versions are the registry's latest that day. Timings come from one local 12-core Ubuntu 26.04 machine on toy projects (a static page, a three-route FastAPI app, the `zod` 4.6.5 tarball, a two-commit Python package and a two-commit Rust crate), never from a cloud VM, so treat them as lower bounds. Probe files stayed in the session scratchpad.

Terms: **tier** as in [Install-check procedure](https://github.com/Gharib89/skills/issues/340) (1 Anthropic-authored, 2 the tool's own vendor, 3 skill repos the target repo pins). **Cloud** reachability is cited from [Web-session probe of cloud setup unknowns](https://github.com/Gharib89/skills/issues/342) (`harness-web-probe.md` on `research/harness-web-probe`, "#342 item N" below) and [Web-session probe of container pulls](https://github.com/Gharib89/skills/issues/352) (`harness-container-pulls.md` on `research/harness-container-pulls`, "#352 item N"). A host neither probe measured is **unprobed**, even when the docs' Trusted list names it (`codeload.github.com` is listed yet blocked, #342 item 3). **Rungs** and budgets are from [Rung budgets and how a run measures them](https://github.com/Gharib89/skills/issues/343): edit 5 s per file, turn 60 s, commit 30 s, full 10 min, cloud setup 300 s.

Vocabulary note: `CONTEXT.md` reserves **Verification** for Ship's real-system check named in a ship profile. The tools here are what such a Verification, or an agent on demand, would drive. This file calls them **behaviour tools** to keep the two apart.

## Headline findings

1. **Claude Code already ships the tier-1 per-kind recipe.** The bundled skills `/run`, `/verify` and `/run-skill-generator` ([Skills, Run and verify your app](https://code.claude.com/docs/en/skills#run-and-verify-your-app)) classify the project and drive it. The `/run` prompt, read from the 2.1.283 binary, maps: CLI to "direct invocation, exit code, stdin/stdout"; Web server / API to "background launch + `curl` smoke"; TUI to tmux `send-keys` / `capture-pane`; Electron to Playwright `_electron` under xvfb; Browser-driven to "dev server + `chromium-cli` script"; Library / SDK to "import-and-call smoke script at the package boundary". `/run-skill-generator` records a working recipe as a committed `.claude/skills/run-<name>/` skill, which reaches the cloud (committed `.claude/skills/` carry over, [Cloud environments, What carries over](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)). It is registered `disableModelInvocation: true` and `/verify` runs only when the user invokes it, so the harness skill can offer them but cannot run them itself.
2. **No tier-1 unit fronts Playwright.** The official marketplace's `playwright` entry (`external_plugins/playwright`, marketplace commit `fa59bc9`) has `"author": {"name": "Microsoft"}` in its `plugin.json`, and its whole glue is `.mcp.json` running `npx @playwright/mcp@latest`. It is unpinnable and runs `@latest`, so under #340 it becomes a pinned `.mcp.json` entry at tier 2 (Microsoft publishes `@playwright/mcp`). The browser tool the bundled `/run` names, `chromium-cli`, is not a package it installs: the npm name `chromium-cli` is a third party's `0.0.1-placeholder` (maintainer `giuseppe-geordie`), so the catalog must never install it by that name. Claude in Chrome is tier 1 but needs the dev's own Chrome, its extension and `/login` ([Chrome](https://code.claude.com/docs/en/chrome#prerequisites)); it is user-level, not repo config, and local-only.
3. **Playwright's own agent CLI is built into `playwright` and uses the repo's pinned browsers.** `npx playwright cli` exists in `playwright` 1.63.0 (it prints "playwright-cli - run playwright mcp commands from terminal"). Microsoft's README for the standalone `@playwright/cli` says a CLI with a skill fits coding agents better than MCP because it keeps tool schemas and accessibility trees out of context. The standalone `@playwright/cli` 0.1.21 and `@playwright/mcp` 0.0.82 both depend on `playwright-core@1.64.0-alpha-1789764292000`, a prerelease whose Chromium revision (1246) differs from `playwright` 1.63.0's (1243), so either package pulls a second browser. Measured: `@playwright/cli` defaults to the branded `chrome` channel; with `--browser=chromium` and revision 1246 absent it fails with `Browser "chrome-for-testing" is not installed`.
4. **No cloud route for a browser exists on the `Default` network today without a human step or an unprobed host.** Every Chromium Playwright downloads comes from `cdn.playwright.dev` only (`playwright install --dry-run chromium` lists no fallback for Chrome for Testing or the headless shell), and all three Playwright CDNs are blocked (#342 item 3). The routes left: (a) a Custom allowlist entry `cdn.playwright.dev`; (b) the vendor image `mcr.microsoft.com/playwright:v<version>-noble`, whose blobs come from `<region>.data.mcr.microsoft.com` (both on the Trusted list, both unprobed); (c) Edge through `packages.microsoft.com` apt (listed, unprobed); (d) branded Chrome from `dl.google.com` (not listed). No registry carries a browser: `@playwright/browser-chromium` is a 15.6 kB postinstall downloader. Ubuntu noble's `chromium-browser` (`2:1snap1-0ubuntu2`) and `firefox` (`1:1snap1-0ubuntu5`) are snap transition stubs. Whether the cloud image preinstalls a browser is unverified: the Installed tools table lists only `chromedriver`.
5. **The MCR route works mechanically.** Measured locally: `docker pull mcr.microsoft.com/playwright:v1.63.0-noble` took 137.7 s (911 MB compressed, 3.5 GB unpacked); `docker cp <container>:/ms-playwright` took 1.1 s and produced revisions 1243, exactly `playwright` 1.63.0's. `PLAYWRIGHT_BROWSERS_PATH=<that dir>` then ran both a library smoke (0.56 s) and `npx playwright cli open --browser=chromium` plus click plus snapshot. So an image tag equal to the repo's `playwright` version is a browser pin with no CDN. Its cloud reach and cloud pull time are unprobed. The pull alone used 46% of the 300 s cloud setup budget on a fast local link.
6. **API/service needs no new unit by default.** The tier-1 pattern (background launch, readiness poll, `curl` the touched route, kill the port's listener) uses only preinstalled tools. With an OpenAPI or GraphQL schema present, Schemathesis (tier 2, PyPI with provenance) is the contract tool: 8.8 to 14.0 s wall for a full default run on three operations, 0.83 s for `--phases examples,coverage`, with a `--max-time` bound. It found 3 real conformance failures in the toy app.
7. **Library public-API checks are offline, seconds long, and sit on `full`.** Measured: publint 1.3 s and `attw` 1.2 s on the `zod` tarball (0 network connects under `strace`); griffe check 0.12 s warm, 1.7 s cold through `uvx`; cargo-semver-checks 0.8 s on a toy crate, but its only cloud-passing install (`cargo install --locked`) took **286 s** on 12 cores, which a 4-vCPU cloud VM will likely push past the 300 s cloud setup budget (inferred, not measured in the cloud). All exit non-zero on a finding.
8. **CLI needs no new unit.** The built binary is the tool. The repo's own test runner already drives it (bats is a stack tool, [Per-stack tool facts](https://github.com/Gharib89/skills/issues/348)). Golden and snapshot suites (`trycmd`, `testscript`) are test libraries the repo chooses, and the harness does not write tests.

## Summary table

"Rung" is where the tool can sit within the budgets; "on demand" means outside the ladder (an agent or `/verify` runs it when a change calls for it).

| Kind | Role | Tool (publisher) | Tier | Latest | Install route and pin | Cloud (`Default`) | Custom allowlist | Rung | Local timing |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| Web UI | agent browser driver | `playwright cli` in `playwright` (Microsoft) | 2 | 1.63.0 | repo lockfile dev dep; else `npm i -D playwright@<ver>` | npm passes (#342 item 3); browser blocked (below) | `cdn.playwright.dev` | on demand | open 1.1 s, click 1.1 s |
| Web UI | agent browser driver, alt | `@playwright/cli` + vendor skill (Microsoft) | 2 | 0.1.21 | `npm i -D @playwright/cli@<ver>`; skill written by `playwright-cli install --skills` to `.claude/skills/playwright-cli/` | as above; prerelease core pulls browser r1246 | as above | on demand | open 1.0 s, click 0.9 s, screenshot 0.4 s |
| Web UI | MCP browser driver, alt | `@playwright/mcp` (Microsoft) | 2 | 0.0.82 | `.mcp.json`: `npx -y @playwright/mcp@<ver> --headless --browser chromium` | `.mcp.json` carries over; browser as above | as above | on demand | not measured |
| Web UI | e2e suite (repo's own) | Playwright Test (Microsoft) | 2 | 1.63.0 | repo lockfile | as above | as above | `full`; `turn` only if `--only-changed` measures under 60 s | not measured on a real app |
| Web UI | library smoke | `playwright` launch + screenshot | 2 | 1.63.0 | repo lockfile | as above | as above | `full` (with the app's server) | 0.55 to 0.68 s wall, warm |
| Web UI | alt driver | `chrome-devtools-mcp` (Google) | 2 | 1.10.1 | `.mcp.json` pinned | needs Chrome: `dl.google.com` not listed | `dl.google.com` (unprobed) | on demand | not measured |
| API | smoke | background server + `curl` (tier-1 `/run` pattern) | 1 pattern | n/a | preinstalled | passes: no fetch | none | `full` | server ready 0.7 s, curl 0.00 s |
| API | contract | Schemathesis (schemathesis org) | 2 | 4.28.0 | uv dev dep or `uv tool install schemathesis==<ver>`; Docker Hub `schemathesis/schemathesis:v<ver>-trixie` | PyPI passes (#342 item 3); Docker Hub passes (#352 item 2) | none | `full` with `--max-time`, else on demand | 8.8 to 14.0 s default; 0.83 s examples+coverage |
| API | service deps | `docker compose` (Docker) | 2 | preinstalled | image digests in the compose file | Docker Hub passes, ghcr.io blobs blocked, no container egress (#352 items 2, 3, 5); dockerd must be started (#352 item 1) | `pkg-containers.githubusercontent.com` for ghcr images | `full` | not measured |
| CLI | smoke | built binary via the repo's runner (tier-1 `/run` pattern) | 1 pattern | n/a | the repo's build | passes: no fetch | none | `full` | trivial |
| Library (npm) | package shape | publint (publint org) | 2 | 0.3.24 | lockfile dev dep | npm passes | none | `full` (needs build) | 1.28 to 1.34 s |
| Library (npm) | types resolution | `@arethetypeswrong/cli` (arethetypeswrong) | 2 | 0.18.5 | lockfile dev dep | npm passes | none | `full` (needs `npm pack`) | 1.17 to 1.18 s |
| Library (npm) | API report | `@microsoft/api-extractor` (Microsoft) | 2 | 7.59.2 | lockfile dev dep | npm passes | none | `full` (needs `.d.ts`) | not measured |
| Library (Python) | API diff vs a git ref | griffe (mkdocstrings) | 2 | 2.3.0 | uv dev dep or `uvx griffe@<ver>` | PyPI passes | none | `full` | 0.12 s warm, 1.68 s cold |
| Library (Rust) | semver check | cargo-semver-checks (obi1kenobi) | 2 | 0.50.0 | `cargo install --locked cargo-semver-checks@<ver>` | crates passes (#342 item 3); install time likely over 300 s | none | `full` | install 286 s; run 0.8 s |
| Library (.NET) | package validation | SDK `EnablePackageValidation` (Microsoft) | 2 | SDK | project property; no unit | NuGet passes (#342 item 3) for the baseline | none | `full` (runs after `dotnet pack`) | not measured |
| Library (Go) | API diff | `gorelease`, `apidiff` in `golang.org/x/exp` (Go team) | 2 | pseudo-version `v0.0.0-20260908205506-85c1c2202aba` | `go install golang.org/x/exp/cmd/gorelease@<pseudo>` | Go proxy passes (#342 item 3) | none | `full` | not measured (no Go locally) |
| Library (JVM) | API diff | japicmp (siom79) | 2 | 0.23.1 | Maven Central plugin | Maven Central passes (#342 item 3) | none | `full` | not measured |

## Tier-1 units found

| Unit | What it is | Cloud | Verdict for the catalog |
|:--|:--|:--|:--|
| `/run`, `/verify`, `/run-skill-generator` | Bundled Claude Code skills (Anthropic); per-kind launch and drive patterns; the generator writes `.claude/skills/run-<name>/` | the bundled skills ship with Claude Code; a recorded `run-<name>` skill is a committed skill and carries over | The front for every kind. The harness offers `/run-skill-generator` to the human (the model cannot invoke it) and never duplicates its recipe. |
| `playwright` plugin | Official marketplace entry, `plugin.json` author "Microsoft", `.mcp.json` `npx @playwright/mcp@latest` | repo-enabled plugins never load in the cloud (#335, #342 item 5) | Not tier 1 (author is Microsoft). Vendor as a pinned `.mcp.json` entry, tier 2. |
| `chrome-devtools-mcp` plugin | Official marketplace, external source pinned by `sha`, no author field; npm maintainers include `google-wombot` | as above | Tier 2 through Google (#340's own example). Needs a Chrome; alternative only. |
| Claude in Chrome | Anthropic extension plus `--chrome`; drives the dev's own browser | needs the dev's local Chrome and `/login`; a browser on the dev machine cannot load a cloud VM's `localhost` | Tier 1 but user-level; not a harness unit. Mention as a local option. |

Other official entries touching this area, none a default: `browser-use` (Browser Use, needs its cloud or the user's Chrome), `postman` (needs a Postman account), `42crunch-api-security-testing` (42Crunch), `codspeed` (CodSpeed, benchmarking).

## Web UI

**Tool choice.** Playwright (Microsoft, tier 2) is the only vendor with a CLI, an MCP server, a test runner and a pinned container image, each with npm SLSA provenance (`playwright`, `@playwright/test`, `@playwright/mcp`, `@playwright/cli` all carry `https://slsa.dev/provenance/v1`). Default driver: `npx playwright cli` from the repo's own `playwright`, because it uses the lockfile's version and its browser revision, needs no second browser and no MCP process, and is the form Microsoft recommends for coding agents. When the repo has no `playwright`, add it as a pinned dev dependency rather than `@playwright/cli`, whose prerelease core breaks the one-browser-per-version property. `@playwright/mcp` stays the alternative for a repo that wants MCP, as a `.mcp.json` entry with an exact version, `--headless` (the server is headed by default) and `--browser chromium`.

**Vendor skill.** `playwright-cli install --skills` writes `.claude/skills/playwright-cli/SKILL.md` plus ten reference files and adds `.playwright-cli/` to `.gitignore`. Its frontmatter is `allowed-tools: Bash(playwright-cli:*) Bash(npx:*) Bash(npm:*)`, and its body tells the agent to `npm install -g @playwright/cli@latest` when no local copy exists. Under #340 that line is a run-time fetch the install check must rewrite to the pinned form or refuse, and the `Bash(npm:*)` grant is broader than the tool needs. `@playwright/cli` also checks `https://registry.npmjs.org/@playwright/cli/latest` once a day for updates.

**Cloud route for the browser.** Ranked:

| Route | Hosts | `Default` network | Cost | Status |
|:--|:--|:--|:--|:--|
| `npx playwright install --with-deps --only-shell chromium` | `cdn.playwright.dev` (browser and ffmpeg), apt archive | CDN blocked, `install-deps` passes (#342 item 3) | 81.6 s and 266 MB locally | Needs the Custom allowlist: `cdn.playwright.dev` |
| `PLAYWRIGHT_DOWNLOAD_HOST=<mirror>` | a mirror with the same path layout | depends on the mirror | as above | Measured: the variable rewrites every URL (`https://mirror.example.com/builds/cft/...`). No vendor mirror exists; third-party mirrors are untrusted. |
| MCR image, `docker cp /ms-playwright` | `mcr.microsoft.com`, `westeurope.data.mcr.microsoft.com` (measured redirect) | Trusted list names `mcr.microsoft.com` and `*.data.mcr.microsoft.com`; unprobed | 137.7 s pull, 911 MB compressed, 3.5 GB on disk, plus dockerd start (0.6 s, #352 item 1) | Works locally; cloud unprobed |
| `playwright install msedge` | `packages.microsoft.com` apt repo | listed, unprobed | not measured | Branded channel; runs as root needs `--no-sandbox` |
| `playwright install chrome` | `dl.google.com` | not on the Trusted list | not measured | Needs the Custom allowlist |
| Ubuntu apt `chromium` | snap store | snap stub | n/a | Unusable |
| Preinstalled browser | none | unverified | none | Docs list `chromedriver` only |

The catalog default is the vendor install with the rung labelled "needs the Custom allowlist: `cdn.playwright.dev`" ([Cloud-first rule and cloud setup form](https://github.com/Gharib89/skills/issues/339), item 2). The MCR route is the candidate that would need no human step, once a cloud probe shows the pull passes and fits 300 s.

**Rung.** The agent driver is on demand: a real check needs the app's dev server (the bundled recipe warns Vite and Next can take 10 s or more for a first paint) and a judgement about what to click. A repo's own Playwright Test suite belongs to `full`. `--only-changed` selects test files by the suite's import graph, and the vendor calls it "a heuristic and might miss tests" ([Playwright CI docs](https://github.com/microsoft/playwright/blob/main/docs/src/ci.md)), so it is a `turn` offer only when measured under 60 s, with `full` still running the suite.

**Traps.** The cloud runs as root (#342 item 8): bundled Chromium launches unsandboxed by default on Linux, branded channels need `--no-sandbox`. `@playwright/cli` picks `chrome` when it finds one, so a local run that passes on the dev's Chrome proves nothing about the cloud's Chromium. MCP's default profile is persistent, so parallel sessions need `--isolated`.

## API/service

**Default: the tier-1 smoke.** Launch in the background, poll readiness, `curl` the touched route, stop by the port's listener (`lsof -ti:<port> -sTCP:LISTEN | xargs -r kill`). Measured on uvicorn: ready in 0.7 s, `curl` in under 10 ms. The bundled recipe's warning about `pkill -f` held here: a `pkill -f 'uvicorn app:app --port 8766'` at the head of a compound command ended the whole call with exit 144 and no output, consistent with the pattern matching the command line that ran it. Scripted as a `smoke.sh` inside the recorded `run-<name>` skill, it fits `full`.

**Contract tool: Schemathesis** (schemathesis org, tier 2), proposed only when a schema is detected (an `openapi.json`/`.yaml` in the repo, or a framework that serves one). PyPI wheel carries a provenance attestation (`/integrity/schemathesis/4.28.0/...` answers 200). Its README runs it as `uvx schemathesis run <url>`, which the install check rewrites to `uvx schemathesis==<ver>`. The Docker Hub image `schemathesis/schemathesis:v4.28.0-trixie` is the no-Python route, and Docker Hub pulls pass (#352 item 2); a container reaching the host's server needs host networking, which is unprobed. Exit is non-zero on any failed check, so `check.sh` can map it directly.

**Service dependencies.** PostgreSQL 16 and Redis 7 are preinstalled but stopped ([Cloud environments, Start services](https://code.claude.com/docs/en/cloud-environments#start-services)). `docker compose` works for Docker Hub images; ghcr.io images fail (#352 item 3) unless `pkg-containers.githubusercontent.com` is on a Custom allowlist; a service that fetches at runtime fails (#352 item 5). dockerd must be started on `SessionStart`, not setup alone (#352 item 1).

**Not defaults.** Hurl, k6 and similar ship binaries through GitHub releases (blocked for unattached repos, [Cloud sandbox facts](https://github.com/Gharib89/skills/issues/334)); the official `postman` plugin needs a Postman account.

## CLI

The binary is the tool. The tier-1 pattern: put it on `PATH` the way the repo builds it, run two or three representative invocations, check exit codes and stdout. That is what the repo's own test runner does (bats, pytest with `subprocess`, Go `testscript`, Rust `trycmd` or `assert_cmd`), and those are test-suite choices the harness keeps, not units it adds. The harness contributes only a `full`-rung build step when the suite does not already build the binary, plus the `/run-skill-generator` offer so an agent knows the build and invocation. No cloud concern beyond the stack's own toolchain.

## Library

A library's behaviour beyond its tests is its public surface. Per stack, default first:

- **npm**: publint (package.json exports and files) then `@arethetypeswrong/cli` on the `npm pack` tarball (types resolution per module mode). Both are small, have SLSA provenance, run offline (measured: 0 `AF_INET` connects under `strace`), and exit 1 on a finding. `api-extractor` is the alternative when the repo keeps an `.api.md` report; it has no npm provenance and needs the `.d.ts` build.
- **Python**: `griffe check <pkg> -s <src> -a <ref>` reports removed objects and parameters against a git ref (measured on a toy break: "Parameter was removed", "Public object was removed", exit 1). No PyPI provenance for 2.3.0 (404). Needs git history holding the ref, so a shallow cloud clone must fetch the tag first (not probed).
- **Rust**: cargo-semver-checks, crates.io Trusted Publishing from `obi1kenobi/cargo-semver-checks`. Builds rustdoc JSON for the baseline (`--baseline-rev`, or the published version from crates.io) and the current tree. Constraint from its README: rustdoc JSON is unstable, each release supports the then-current stable and beta, so its pin must move with `rust-toolchain.toml`. `cargo binstall` fetches GitHub release assets (blocked), so the cloud route is `cargo install`, measured at 286 s locally: an install likely over the cloud setup budget, to be offered with the #343 item 6 choices or labelled local-only.
- **.NET**: `EnablePackageValidation` runs after `dotnet pack` with a `PackageValidationBaselineVersion` fetched from NuGet ([Package validation overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/apicompat/package-validation/overview)). SDK-built, so no unit to install.
- **Go**: `gorelease` (self-described "an experimental tool") and `apidiff` live in `golang.org/x/exp`, which has no tagged versions, only pseudo-versions; #349's cooldown rule reads the proxy's `.info` time, which pseudo-versions have. Alternative only.
- **JVM**: japicmp (Maven Central) as an alternative; not measured.

All go on `full`: each needs a build or a pack, and a check that flags an intended break belongs where the human reviews, not on every turn.

## What this means for the catalog

A repo kind is not a stack: it is a signal set over the detected stacks (a dev server script and HTML entry for web UI, a server framework or schema for API, a `bin` entry or `[[bin]]` or `console_scripts` for CLI, a publishable manifest for library), and one repo can be several kinds. The behaviour tools are either the repo's own suite wired into `full`, a public-API checker on `full`, or an on-demand driver; none fits `edit`, `turn` or commit. The catalog therefore needs a `## Kinds` shape (or a `behaviour` role) whose only rungs are `full` and on demand, and whose on-demand entries point at `/run-skill-generator` rather than a harness-written recipe.

## Unverified

- Whether the cloud image preinstalls Chrome, Chromium, Playwright browsers or `chromium-cli` (docs list only `chromedriver`).
- Cloud reach of `mcr.microsoft.com` and `*.data.mcr.microsoft.com`, and the MCR image's cloud pull time against the 300 s budget.
- Cloud reach of `packages.microsoft.com` (Edge apt) and `dl.google.com` (Chrome).
- Whether a Custom allowlist of `cdn.playwright.dev` alone makes `playwright install` pass in the cloud.
- Whether a container on host networking reaches a server on the cloud VM's `localhost` (MCR MCP image, Schemathesis image).
- cargo-semver-checks install time on a 4-vCPU cloud VM; griffe against a shallow clone.
- Playwright Test `--only-changed` timing on a real app; api-extractor, japicmp, gorelease and .NET package validation timings.
