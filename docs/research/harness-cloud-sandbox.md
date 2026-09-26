# Cloud sandbox facts for a harness

Research for [#334](https://github.com/Gharib89/skills/issues/334), part of map [#333](https://github.com/Gharib89/skills/issues/333) (`setup-harness`). Read 2026-09-26 against the Claude Code docs and changelog at v2.1.283. Where this repo already measured a fact in a real cloud session ([#28](https://github.com/Gharib89/skills/issues/28), [#29](https://github.com/Gharib89/skills/issues/29), [#249](https://github.com/Gharib89/skills/issues/249)), the measurement is cited next to the doc claim, and conflicts are called out.

Sources, cited below by short name:

- **env**: [Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)
- **web**: [Use Claude Code in the cloud](https://code.claude.com/docs/en/claude-code-on-the-web)
- **quick**: [Get started with Claude Code in the cloud](https://code.claude.com/docs/en/web-quickstart)
- **hooks**: [Hooks reference](https://code.claude.com/docs/en/hooks)
- **vars**: [Environment variables](https://code.claude.com/docs/en/env-vars)
- **lsp**: [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence)
- **pinst**: [Install and manage plugins](https://code.claude.com/docs/en/plugins/install), **pload**: [Plugin loading reference](https://code.claude.com/docs/en/plugins/loading), **porg**: [Manage plugins for your organization](https://code.claude.com/docs/en/plugins/org)
- **routines**: [Automate work with routines](https://code.claude.com/docs/en/routines)
- **selfhost**: [Self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) and its [configuration](https://code.claude.com/docs/en/self-hosted-environments-configuration) page
- **cl**: [Changelog](https://code.claude.com/docs/en/changelog)

## 1. Setup script vs `SessionStart` hook

| | Setup script | `SessionStart` hook gated on `CLAUDE_CODE_REMOTE` |
|---|---|---|
| Lives in | The **environment** config at claude.ai/code (or the admin Cloud environments page for a shared one). **Not a repo file.** | The repo's `.claude/settings.json`, committed. |
| Runs | New session only, before Claude Code launches, as root on Ubuntu 24.04. Skipped when a cached snapshot exists. Resume never re-runs it. | After Claude Code launches, on every session including resume (`matcher: "startup\|resume"`). Local and cloud alike, so the script must exit early unless `CLAUDE_CODE_REMOTE` is `true`. |
| Persists | Its filesystem writes, as the environment cache (a filesystem snapshot). Running processes (a started database, `docker compose up`) are lost. | Nothing across sessions: it re-runs every start. Within a session, `CLAUDE_ENV_FILE` carries exported variables to later Bash calls. |
| Cache rebuild | When the setup script or the allowed hosts change, and on expiry after roughly seven days. | n/a |
| Time limit | Roughly five minutes, or the environment is **not cached** (and sessions may stall or fail with a container error). Must exit 0 or the session fails to start. | 600 s default per `command` hook, raised with `timeout`; not enforced with `async: true`. |
| Credentials | The agent proxy connects after the setup script, so API credentials are never attached to setup requests. | Same session network as Claude. |
| Does not run | Locally. | In a session with several repositories (hooks from no repo's settings load); in user-level `~/.claude/settings.json` (stays on the machine). |

Sources: env "Setup scripts", "Script requirements", "Environment caching", "Setup scripts vs. SessionStart hooks", "Limitations in cloud sessions", "Time limits", "Requests that never get the credential"; hooks line on `CLAUDE_CODE_REMOTE` ("`true` in remote web environments and not set in the local CLI") and `CLAUDE_ENV_FILE`; vars `CLAUDE_CODE_REMOTE` ("Read this from a hook or setup script"); quick "Clone and prepare" (repo cloned, then setup script runs).

Anthropic's own split: setup script provisions the VM (toolchains and CLIs not preinstalled), a `SessionStart` hook does project setup that runs everywhere (for example `npm install`). The documented escape for the five-minute budget is to parallelise installs with `&`/`wait` and move a single oversized download into a `SessionStart` hook that runs it in the background (env; quick "New sessions hang or time out during setup").

Other time limits (env "Time limits"): Bash commands use the tool defaults (2 min, up to 10 min; a command that times out moves to the background), raised per environment with `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`. Idle sessions stop and the VM is reclaimed; reopening gives a fresh VM with history restored but background work lost (web "Environment expired"). **The idle period and any maximum session length are not stated** anywhere in the docs; the changelog only mentions sessions running "longer than about six hours" (cl 2.1.268, persisted-folder fix).

Consequences for the harness:

- The skill **cannot commit a setup script**; it can only write one into the repo and tell the human to paste it (or a one-line call to it) into an environment. Environments are per account (or org-shared), not per repo, and one environment's cache serves every repo that uses it.
- Whether the setup script's working directory is the clone is **not stated**. quick says the repo is cloned before the setup script runs, so a setup script that calls a committed repo script is plausible, but untested: medium confidence.
- The committed, repo-owned half is the `SessionStart` hook. Keep it idempotent and fast, because it pays its cost on every start and resume.

## 2. What the default image preinstalls

Anthropic-hosted sessions get a fresh Ubuntu 24.04 x86_64 VM (env "What's available in cloud sessions"). The "Installed tools" table:

| Category | Included |
|---|---|
| Python | Python 3.x with pip, poetry, uv, black, mypy, pytest, ruff |
| Node.js | 20, 21, 22 (`/opt/node2x`, 22 on `PATH`), npm, yarn, pnpm, bun, eslint, prettier, chromedriver |
| Ruby | 3.1, 3.2, 3.3 with gem, bundler, rbenv |
| PHP | 8.3 with Composer |
| Java | OpenJDK 21 with Maven and Gradle |
| Go | Go with module support |
| Rust | rustc and cargo |
| C/C++ | GCC, Clang, cmake, ninja, conan |
| Docker | docker, dockerd, docker compose |
| Databases | PostgreSQL 16, Redis 7.0 (installed, not running) |
| Utilities | git, gh, jq, yq, ripgrep, tmux, vim, nano |

A `check-tools` command on the VM prints most versions. Not preinstalled: .NET SDK and any toolchain outside the table, even when its registry is allowlisted. Bun has "known proxy compatibility issues" for package fetching. Resource ceilings: about 4 vCPU, 16 GB RAM, 30 GB disk. Replacing the base image is not supported; install on top with a setup script or run your own image under `docker compose` (env).

**Language servers: none are listed, and it would not matter.** lsp: "In cloud sessions, Claude Code doesn't start plugin language servers, so Claude gets no diagnostics or code navigation there." The LSP recommendation dialog never appears in a cloud session. On top of that, a cloud session does not install plugins the repo's `.claude/settings.json` turns on under `enabledPlugins`, nor add `extraKnownMarketplaces` (no workspace trust dialog); only plugins pushed through server-managed settings reach it (env "What carries over"; pinst "Cloud session" tab; pload; porg). High confidence: three pages agree.

**Measured conflicts with the table** (this repo, real web sessions):

- `gh`: the docs list it; #28 (2026-09-09) and `skills/ship/reference/unattended.md` found it absent and installed it with `apt-get install -y gh` (Ubuntu's 2.45.0). The docs may have been updated since; re-probe before relying on either.
- `az`: absent (#29), installable in about 42 s via `aka.ms/InstallAzureCLIDeb` plus the `azure-devops` extension.
- `shellcheck`, `gitleaks`: absent; `LANG` unset, so locale-dependent scripts misbehave until `LC_ALL=C.UTF-8` (#249).
- Python measured as 3.11.15 (#29).

What carries over from the repo (env "What carries over"): `CLAUDE.md`, `.claude/rules/`, `.claude/skills|agents|commands/`, and, in a single-repo session only, `.claude/settings.json` hooks and permissions and `.mcp.json`. Not carried: anything user-scoped (`~/.claude/*`, user plugins, `claude mcp add` at local/user scope), transport variables in the settings `env` block (`NODE_EXTRA_CA_CERTS`, mTLS vars are ignored), and interactive auth such as SSO.

## 3. Network policy for registries and binary downloads

The Default environment is **Trusted**: an allowlist of package registries, GitHub, cloud SDKs, and nothing else through the session network. Other levels: None, Full (any domain), Custom (own list, optionally plus the defaults). There is no org-wide allowlist; an Owner can share a Custom environment instead (env "Access levels", "Allow specific domains").

| Need | Trusted allows | Source |
|---|---|---|
| npm | `registry.npmjs.org`, `npmjs.com/org`, `yarnpkg.com`, `registry.yarnpkg.com`, `jsr.io`, `npm.jsr.io`, `npm.pkg.github.com` | env "Default allowed domains" |
| PyPI | `pypi.org`, `files.pythonhosted.org`, `pythonhosted.org`, `test.pypi.org`, `pypa.io`; conda: `repo.anaconda.com`, `conda.anaconda.org` | same |
| crates | `crates.io`, `index.crates.io`, `static.crates.io`, `rustup.rs`, `static.rust-lang.org` | same |
| Go, JVM, others | `proxy.golang.org`, `sum.golang.org`; Maven Central, Gradle; Packagist, NuGet, pub.dev, hex.pm, CPAN, CocoaPods, Hackage | same |
| apt | `archive.ubuntu.com`, `security.ubuntu.com`, `*.ubuntu.com`, `ppa.launchpad.net`, plus vendor repos `packages.microsoft.com`, `download.docker.com`, `apt.releases.hashicorp.com`, `pkgs.k8s.io` | same |
| Other binaries | `nodejs.org`, `releases.hashicorp.com`, `dl.k8s.io`, `dotnet.microsoft.com`, `dot.net`, `sourceforge.net`, `packagecloud.io`, `binaries.prisma.sh`, Docker Hub, `ghcr.io`, `gcr.io`, `mcr.microsoft.com`, `public.ecr.aws` | same |
| GitHub releases | `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`, `codeload.github.com`, `raw.githubusercontent.com` are listed, **but** see below | same |

**GitHub release assets are the trap.** All GitHub traffic goes through a separate GitHub proxy, independent of the access level, and "GitHub API and release-asset requests reach only repositories attached to the session, so a setup script that downloads release assets from an unattached repository gets a 403" (env "GitHub proxy"). This is the documented cause of #249's `npx -y shellcheck` 403. So any tool whose installer pulls a binary from another project's GitHub releases (many npm/pip wrappers, `curl ... /releases/download/...`) fails even at Full. Prefer apt, or a registry package that ships the binary itself. The same proxy serves only a pinned set of GraphQL operations (everything else 403, including with your own `GH_TOKEN`), and `git push` works only on the session's current branch.

Other proxy facts: all outbound traffic from an Anthropic-hosted session passes a security proxy (rate limiting, filtering, DNS audit), which "some package managers don't work correctly with", Bun being the named example (env "Security proxy", "Limitations in cloud sessions"). The public registries (`registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `index.crates.io`, `proxy.golang.org`, `jsr.io`) never get an API credential, so private packages on those hosts need another auth path (env "Requests that never get the credential"). API credentials exist on Pro and Max only, not Team or Enterprise.

Not settled by the docs: whether hosts a harness tool fetches at install time (Playwright's browser CDN, which Playwright's docs call only "Microsoft's CDN", LLVM apt, NodeSource, `cli.github.com` apt) are reachable under Trusted. None is on the list by name; a probe settles each.

## 4. Can an Azure DevOps repo run in a cloud session?

**Not as a first-class session.** web "Limitations": "repository cloning and pull request creation require GitHub" (GitHub Enterprise Server is supported on Team and Enterprise). quick: cloud sessions require a connected GitHub account. routines: repositories are GitHub repositories, and GitHub triggers need the Claude GitHub App. selfhost "Availability": "sessions check out repositories from GitHub" (a self-hosted runner's clone hook replaces the built-in clone, but the docs do not describe it as a route to non-GitHub hosts; unsupported, not proven impossible).

**The one documented route is a bundle.** `CCR_FORCE_BUNDLE=1 claude --cloud "..."` uploads the local repo (full history, tracked uncommitted changes, under 100 MB, else current branch, else a squashed snapshot) to a cloud session, and "the session can't push results back to that remote" (web "Send local repositories without GitHub", "Limitations"). It needs a human at a terminal to start, so it cannot back an unattended routine. The changelog confirms non-GitHub-hosted sessions exist as a case: 2.1.281 hid the Create PR button that "could never work" there, and 2.1.282 added "Open repository" links for repos "hosted on a Git server other than GitHub".

**The network is not the blocker.** `dev.azure.com`, `visualstudio.com`, `*.microsoftonline.com` and `packages.microsoft.com` are on the Trusted list (env). #29 measured it in a GitHub-repo web session: zero blocked rows across 44, including git clone, push and ref deletion over HTTPS with a PAT, work-item and PR REST, and `az` installed in the setup budget. So a session can *reach* ADO with a PAT in an environment variable (visible to every environment user; no API credentials on Team/Enterprise). What fails is credential shape: no interactive `az login` (SSO is unsupported in the cloud), and identity lookup by email on `vssps.visualstudio.com` refused the PAT.

Verdict: an ADO-hosted repo cannot be the cloud session's repository except as a push-less bundle a human starts. Confidence high (four pages agree). Unmeasured: whether a bundle session can push to the ADO remote itself with a PAT (the docs' "can't push back" likely describes the built-in flow; #29's push worked from a GitHub-anchored session). Until measured, the skill should classify an ADO repo as local-only for cloud setup, with the bundle route named as an attended-only option.

## 5. Other things that force local-only

From the docs, each a reason the skill can print:

1. **Repo not on GitHub** (ADO, GitLab, Bitbucket): as in part 4. (web)
2. **Needs a non-Linux-x86_64 build**: every Anthropic-hosted VM is Ubuntu 24.04 x86_64 (Windows-only builds, macOS/Xcode, native ARM). (env)
3. **Private network or VPN**: sessions egress from Anthropic's network, and credentials are attached only to "APIs that accept connections from the internet". The fix Anthropic offers is a self-hosted environment (Team/Enterprise public beta, off by default, GitHub repos only) or Remote Control on your own machine. (env; selfhost)
4. **Interactive or browser auth** (AWS SSO, `az login`): "Not supported". (env "What carries over")
5. **Resources beyond about 4 vCPU / 16 GB / 30 GB**: the VM may stop the task. (env "Resource limits")
6. **Org policy**: claude.ai IP allowlisting makes every Anthropic-hosted session fail authentication; Zero Data Retention orgs cannot use cloud sessions at all; Team/Enterprise need an Owner to enable the GitHub connector and cloud sessions. (web "Limitations"; quick)
7. **Harness pieces that do not load in the cloud**: LSP (never starts), repo-enabled plugins and marketplaces, user-scope config, and repo hooks in a multi-repo session. A harness can still be cloud-capable, but these rungs are local-only by construction. (lsp; env; pload)
8. **Secrets**: on Team/Enterprise every secret is a plain environment variable any environment user can read, which some repos' policies forbid. (env "Add API credentials")
9. **Downloads from unattached GitHub repos' releases**, and **GitHub GraphQL-only APIs** (Projects v2): 403 at every access level. A repo whose build depends on them needs a different install path or stays local. (env "GitHub proxy")
10. **Setup that cannot fit about five minutes** is not a hard block (the session still runs, uncached), but every session then pays it. (env)

Hardware and licensed tools are not addressed by the docs; they follow from 2 and 3.
