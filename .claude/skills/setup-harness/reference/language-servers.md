# Language servers

A language server is wired only as a vendored, repo-owned plugin, so every machine runs the same server config at the same binary pin. The official marketplace cannot be pinned to a commit (a marketplace source takes a branch or tag, and it has no tags), so enabling its plugins would give each machine whatever `main` is. Each catalog `## language server` tool names the Anthropic plugin it is vendored from.

## Vendoring

Per wired tool, from `anthropics/claude-plugins-official` at the head of `main` (`git ls-remote https://github.com/anthropics/claude-plugins-official main`, the full SHA):

1. **Read the glue** in full and show it as the install-check row's glue: the upstream's `.claude-plugin/marketplace.json` entry (its inline `lspServers` is the whole server config) and `plugins/<upstream>/`.
2. **Write `.claude/skills/harness-<upstream>/`**:
   - `.claude-plugin/plugin.json`: `name` `harness-<upstream>`, the entry's `description` and `author`, `version` `<entry version>+<full sha>`.
   - `.lsp.json`: the entry's `lspServers` object, `command` and `args` replaced by the catalog `Run:` line with `{version}` and `{member}` filled; `extensionToLanguage` as upstream has it.
   - `README.md`: `Vendored from anthropics/claude-plugins-official@<full sha>`, the upstream entry's name, and the reason (the marketplace cannot be commit-pinned).
3. **Disable the upstream in `.claude/settings.json`**: `"enabledPlugins": {"<upstream>@claude-plugins-official": false}`, merged beside the repo's own keys.
4. **Pin the binary** by the catalog `Pin:` and the install check's pin table: an exact dev dependency at the stack root where the stack's registry serves it (`pnpm add -D -E typescript-language-server@<v>`), else the exact version in the `.lsp.json` launch (pyright's `npx --yes --package=pyright@<v>`).

The name and the disable are the coexistence rule, measured with a dev's user-scope `pyright-lsp@claude-plugins-official` enabled (Claude Code 2.1.283):

- A vendored plugin keeping the upstream's name is not loaded: `the name "pyright-lsp" is already taken by an installed plugin (pyright-lsp@claude-plugins-official), which takes precedence`. It stays unloaded when the upstream is disabled, leaving no server for the extensions.
- Under its own name with the upstream still enabled, both register for `.py`, but only the user-scope server starts and answers. The vendored one never runs, so the pin is silently unused. Nothing duplicates.
- Under its own name with the upstream disabled, only the vendored server registers, starts and answers, and diagnostics arrive from one server.

**TypeScript 7.** Read the stack's resolved `typescript` from its lockfile. At 7 or later, `typescript-language-server` is `Unavailable: typescript-lsp needs TS ≤ 6`: report it under Not acted on and write nothing of it.

An existing `.claude/skills/harness-<upstream>/` is the repo's own evidence: keep it and propose only what it lacks, per the Explore step.

## Local-only, never in the profile

A cloud session starts no plugin language server, so every language server is `local-only: cloud sessions start no plugin language server` in the install-check row's Cloud column and in the report's cloud table. That is true by construction, so it is never written to the harness profile: no `Local-only:` line and no proof line. A row the human drops with a reason is the one exception, recorded `Declined:` like any other.

## The proof

Local only. Its precondition is a trusted workspace; in a cloud session (`CLAUDE_CODE_REMOTE=true`) skip it and say so.

1. **Register the servers.** A plugin written mid-session is not loaded until the human types `/reload-plugins` (Claude cannot run it) or starts a new session. `ToolSearch` with `select:LSP` finds the `LSP` tool only once some server is registered, so no match means ask for `/reload-plugins`. A match does not prove the vendored server is registered, since another plugin's server (the upstream's, before its disable takes effect) also makes the tool appear. So a run that wrote or changed a vendored plugin in this session asks for `/reload-plugins` either way, then runs `ToolSearch` again to load the tool.
2. **Ask each server.** Per wired language, call `LSP` with `hover` (or `documentSymbol`) on one tracked file of that language. Pass when the result has no `Error performing`. A missing binary answers `Error performing hover: Command failed with ENOENT: <command>`.
3. **Report** one line per language: `<language>: answers (<operation> on <file>)`, or `<language>: fails (<the error>)`.

Two signals are not the proof. A diagnostic after an edit mutates a file and arrives on a later tool result or turn, never the edit's own. A `pgrep` of the command shows a process, not an answer.
