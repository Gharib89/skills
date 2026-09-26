# Cloud probe run 1 (2026-09-26, session_01QpBJhsWudwCr3dry72PM6P)

Started with `claude --cloud` from branch `research/harness-web-probe` at 3d3ea66, before
`/remote-env` was set, so it ran in the CLI fallback environment: no setup-script line, no
`ADO_PAT`. Relayed by the user from the session's final reply (the session did not post
to the issue). Items 1, 2 and 4 are void for this run.

In-session answers:

1. No tool named `LSP`, deferred or loaded.
2. Edit of `probe/lsp_target.py` (`return str(a) + b`): no diagnostics.
3. `echo harness-probe-allow:1`, `echo harness-probe-deny:1`, `echo harness-probe-other:1`:
   all three ran with no permission message. The deny rule did not apply.

Report highlights (full table as relayed below):

- root, cwd `/home/user/repo`, branch `research/harness-web-probe`, 4 proxy vars, claude 2.1.283.
- 403 at the proxy (CONNECT tunnel failed): `deb.nodesource.com`, `apt.llvm.org`,
  `cli.github.com`, `cdn.playwright.dev`, `playwright.download.prss.microsoft.com`,
  `playwright.azureedge.net`; plain 403: `storage.googleapis.com/chrome-for-testing-public`,
  `codeload.github.com`.
- Real installs pass: npm, pip (ruff, prek), uv, npx lefthook, go mod download, gem fetch,
  cargo search, apt-get update + install shellcheck, `playwright install-deps`.
  `playwright install chromium` fails (download failure), so headless launch fails.
- Plugins: only `ratelimit-otel` (user scope, synced); `pyright-lsp@claude-plugins-official`
  from `enabledPlugins` not installed. `claude plugin list`: "1 project-scope directory
  under ./.claude/skills/ that may load as a plugin was skipped because this workspace was
  not trusted when plugins were scanned". pyright installed by the SessionStart hook, no
  language server process.
- Hooks: SessionStart marker (remote=true, cwd /home/user/repo, root) and PostToolUse marker
  (edited path) present; Stop marker absent (first turn had not ended).
- `git ls-remote` and `git clone --depth 1` of unattached public GitHub repos pass; prek
  runs a remote hook repo (cold 1.8 s, warm 52 ms).
- Node: `/opt/node22/bin/node` v22.22.2 (also `/usr/local/bin/node`), npm 10.9.7;
  lint-staged 17.6.0 runs.
