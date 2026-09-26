# Web-session probe of cloud setup unknowns (#342)

Measured 2026-09-26 on Claude Code 2.1.283 in cloud environment `Default`
(env_01JP2VM3dbgtAjtNh8um94pq, the one `claude --cloud` uses after `/remote-env`), with the
probe script [`probe-harness-web.sh`](probe-harness-web.sh) on branch
`research/harness-web-probe`. Raw runs: [local control](harness-web-control-2026-09-26.md),
[run 1 (fallback env)](harness-web-cloud-run1-2026-09-26.md),
[run 1b](harness-web-cloud-run1b-2026-09-26.md),
[bundle run 3b and idle restart](harness-web-cloud-run3b-idle-2026-09-26.md); run 2b and
run 3b's push were read from their session pages (quoted below).

**Method trap.** `claude --cloud` with no `remote.defaultEnvironmentId` set silently used a
fallback environment, not the one carrying the setup script and env vars (runs 1, 2, 3).
Run `/remote-env` first.

## Answers

1. **Setup script cwd: the repo clone.** The setup line logged
   `pwd=/home/user/repo user=root home=/root`, the repo's top-level listing, and
   `git rev-parse --show-toplevel` = `/home/user/repo`. A pasted one-liner can call a
   committed script (`bash scripts/cloud-setup.sh`). `CLAUDE_CODE_REMOTE` is already set
   during setup. Same in a bundle session.
2. **Setup cache and idle.** A second new session on the same repo, 6 minutes after the
   first session's setup, ran the setup script fresh (run 2b: setup line 21:46:12, 8 s after
   boot; run 1b's was 21:40:00). No cache reuse was observed, so the setup script must be
   idempotent and fit in its ~5 minute budget on every new session. Idle: run 1b's turn
   ended 21:42:58; the next message about 6 minutes later found a restarted kernel on a
   **preserved disk** (`/tmp`, the checkout and a local commit intact), the setup script
   **not** re-run, and the `SessionStart` hook re-run 8 s after boot. No expiry that loses
   the disk was seen at that interval; anything a hook installs into the disk survives a
   resume, processes do not.
3. **Reachability (`Default` network).** Pass, with a real install where one exists: npm
   (`npm pack`), PyPI (`pip download` ruff, prek), uv, npx lefthook, Go proxy + sumdb
   (`go mod download gopls`), RubyGems (`gem fetch`), crates (`cargo search`, static.crates.io),
   Maven Central, Gradle plugins, NuGet, Packagist, static.rust-lang.org, Ubuntu apt
   (`apt-get install shellcheck`), `raw.githubusercontent.com`, Docker Hub (401 = auth
   challenge, reachable). **Blocked (proxy 403)**: `deb.nodesource.com`, `apt.llvm.org`,
   `cli.github.com` apt, `codeload.github.com`, `storage.googleapis.com/chrome-for-testing-public`,
   and all three Playwright browser CDNs (`cdn.playwright.dev`,
   `playwright.download.prss.microsoft.com`, `playwright.azureedge.net`).
   `npx playwright install chromium` fails with "Download failure", so a headless launch
   fails; `playwright install-deps` (apt) passes. Playwright in the cloud needs those CDN
   hosts added to a Custom network allowlist, a human step in the environment config.
4. **Azure DevOps bundle push: works with a PAT.** Run 3b
   (`CCR_FORCE_BUNDLE=1 claude --cloud` from a clone of `AhmedGharib/_git/AhmedGharib`,
   `ADO_PAT` set as an environment variable):
   `git -c credential.helper= push "https://pat:${ADO_PAT}@dev.azure.com/..." HEAD:refs/heads/probe/bundle-push-1790459207`
   exited 0 and `ls-remote` listed the branch (deleted afterwards). The bundle checkout has
   **no remote** (`git remote -v` empty, only local `main`), so the push must name the URL.
   Without a PAT the push fails with "Authentication failed"; `dev.azure.com` answers 302
   unauthenticated. The environment setup script runs in bundle sessions too.
5. **Plugins and LSP: both doc claims hold.** `enabledPlugins`
   `pyright-lsp@claude-plugins-official` was not installed (`claude plugin list` shows only a
   user-synced plugin). The vendored `.claude/skills/probe-pyright/` plugin was skipped:
   "1 project-scope directory under ./.claude/skills/ that may load as a plugin was skipped
   because this workspace was not trusted when plugins were scanned". With
   `pyright-langserver` on PATH (installed by the SessionStart hook), editing a `.py` file
   gave no diagnostics, no `LSP` tool, and no language server process.
6. **Hooks apply, permissions do not.** `SessionStart`, `PostToolUse` (with the edited
   path) and `Stop` markers were all written by the committed `.claude/settings.json`. The
   committed `permissions` block did not apply: `echo harness-probe-deny:1`, matched by
   `permissions.deny`, ran with no message, as did the allow and unlisted commands (the
   session runs in "Accept edits" mode and never prompted). Cause as reported by Claude Code:
   the cloud workspace is untrusted, matching the local `-p` untrusted-folder result.
7. **Clone of an unattached public repo: works.** `git ls-remote` and
   `git clone --depth 1 https://github.com/pre-commit/pre-commit-hooks` passed, and
   `prek run --all-files` with a remote hook repo installed and ran the hook (cold 1.8 s to
   2.3 s, warm 52 ms to 85 ms). Tarball fetches from `codeload.github.com` are blocked.
8. **Node: v22.22.2** at `/opt/node22/bin/node` (also `/usr/local/bin/node`), npm 10.9.7;
   `npx lint-staged@17 --version` printed 17.6.0. Runs as root, `HOME=/root`.
