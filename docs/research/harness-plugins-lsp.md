# Claude Code plugins: LSP, official marketplace, pinning

Resolves [#335](https://github.com/Gharib89/skills/issues/335) (part of #333). Question: what can
`setup-harness` install from trust tier 1, and how can it pin and inspect it?

Vocabulary is [CONTEXT.md](../../CONTEXT.md) plus the map's *agent harness* and *Setup skill*.

Measured on 2026-09-26 with Claude Code 2.1.283. Official marketplace read at
`anthropics/claude-plugins-official@fa59bc9037741ecfa131aa27938272605710d7b2` (main, committed
2026-09-25T23:12Z). The repo has **no tags and no releases**.

## Headline: two facts that change the map's settled premises

1. **Cloud sessions do not start plugin language servers.** "In cloud sessions, Claude Code
   doesn't start plugin language servers, so Claude gets no diagnostics or code navigation
   there." ([code-intelligence](https://code.claude.com/docs/en/plugins/code-intelligence)). The
   map's "proves the language server answers" can only be proven in a local session.
2. **Cloud sessions do not install plugins a repo enables.** The cloud "what carries over" table
   lists "Plugins and marketplaces declared in your repo's `.claude/settings.json`: No"
   ([cloud-environments](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup));
   same statement in [install, Cloud session tab](https://code.claude.com/docs/en/plugins/install)
   and [loading](https://code.claude.com/docs/en/plugins/loading#plugins-shared-through-a-repository)
   ("requires the workspace trust dialog, which a cloud session never shows"). What *does* carry
   over: repo `.claude/settings.json` hooks and permissions, `.mcp.json`, `.claude/rules/`,
   `.claude/skills/`, `.claude/agents/`, `CLAUDE.md`. The only plugin routes into an
   Anthropic-hosted cloud session are **server-managed settings** (org Owner role) and
   **plugins synced from claude.ai** ([org](https://code.claude.com/docs/en/plugins/org#when-each-surface-applies-the-plugin-keys);
   changelog 2.1.261 fixes a cloud path for synced plugins).

Both are doc statements; neither was probed in a real cloud session here (this repo's cloud
probes run in a user-opened web session, see memory `measure-in-a-web-session`).

Consequence for the design: anything that must work in a cloud session goes in committed
non-plugin config (`.claude/settings.json` hooks, `.claude/hooks/`, `.mcp.json`, setup script),
not in a plugin. Plugins, LSP included, are a local-session layer.

## 1. How Claude Code configures language servers

**Mechanism.** Only through a plugin. A plugin declares servers in `.lsp.json` at its root or
in the `lspServers` manifest (or marketplace entry) key; the file maps server name to config with
no wrapper object ([components, LSP servers](https://code.claude.com/docs/en/plugins/components#lsp-servers)).
There is no project-level `.lsp.json` and no settings key for LSP outside plugins: settings
docs have zero LSP keys, and "Claude Code doesn't scan a project's `.claude/plugins/`
directory" ([loading](https://code.claude.com/docs/en/plugins/loading#plugins-shared-through-a-repository)).

Config fields ([manifest reference, `lspServers`](https://code.claude.com/docs/en/plugins/manifest-reference#lspservers)),
strict object, unknown key fails validation: required `command`, `extensionToLanguage`
(keys start with `.`); optional `args`, `transport` (accepts `socket` but runs everything over
stdio), `env`, `initializationOptions`, `settings`, `workspaceFolder`, `startupTimeout`,
`shutdownTimeout`, `restartOnCrash` (default true), `maxRestarts`, `diagnostics` (default true).

**Binary.** The plugin never ships the server. `command` is spawned by name from the `PATH` of
the shell that started `claude`. Each official plugin's README names the install command
(table in section 2).

**What Claude gains.** Diagnostics pushed after each Edit/Write of a matching file, and a
read-only `LSP` tool for symbol navigation ([code-intelligence](https://code.claude.com/docs/en/plugins/code-intelligence#see-what-claude-gains)).

**Start timing.** The server starts the first time Claude edits a file with a matching
extension, not at session start.

**Success signal.** `Found N new diagnostic issues in M files (ctrl+o to expand)` under the edit
that introduced an error.

**Failure signals** ([troubleshooting](https://code.claude.com/docs/en/plugins/troubleshooting#language-server-doesnt-start)):

| Failure | Where it shows |
|---|---|
| Binary missing | `/plugin` Errors tab: `Executable not found in $PATH: "<binary>"`; `claude --debug`: `LSP server <name> failed to start: <reason>` |
| Invalid `.lsp.json` entry | whole file skipped; Errors tab: `Invalid LSP server config for ".lsp.json"`. `claude plugin validate` does not read `.lsp.json` |
| Two servers claim one extension | first registered wins; Errors tab: `LSP server "<name>" is not used for <ext> files` |
| Server writes non-protocol stdout, or header over 64 KiB / body over 32 MiB | disconnected, counted as a crash toward `maxRestarts` |
| Plugin enabled in project settings, not installed on this machine | Errors tab: `Plugin "<name>" is enabled in project settings but isn't installed here` |

**Headless caveat.** `--bare` skips LSP (changelog 2.1.81). A `-p` run installs plugins in the
background, so a plugin can be missing on the first turn unless `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1`
([org](https://code.claude.com/docs/en/plugins/org#when-each-surface-applies-the-plugin-keys)).
The official marketplace auto-registers only in an interactive terminal session, never in `-p`
or a terminal attached to a cloud session ([org](https://code.claude.com/docs/en/plugins/org)).

**Implication for a proof step.** A non-interactive proof must (a) have the marketplace declared
in `extraKnownMarketplaces`, (b) set `CLAUDE_CODE_SYNC_PLUGIN_INSTALL=1`, (c) make an edit that
introduces an error, then look for the diagnostics line or the Errors-tab string. The init event
of `claude -p --output-format stream-json --verbose` lists loaded plugins; whether it also
reports LSP server start was not verified.

## 2. What the official marketplace carries

314 plugins at `fa59bc9`: 52 relative-path (in the repo) and 262 external. Categories:
development 123, productivity 69, database 39, monitoring 22, security 18, deployment 9,
design 8, automation 3, learning 3, testing 2, other 4, none 14. Most entries come from partners,
not Anthropic ([anthropic-marketplaces](https://code.claude.com/docs/en/plugins/anthropic-marketplaces#find-plugins-in-the-official-marketplace)).
Read from `.claude-plugin/marketplace.json`, not from memory.

### LSP plugins (all LSP-bearing entries in the catalog)

The 12 Anthropic entries carry their `lspServers` inline in the marketplace entry (`strict:
false`, `version: 1.0.0`); their plugin directories hold only `README.md` and `LICENSE`.

| Language | Plugin | Author | `command args` | Extensions | Binary install (plugin README) |
|---|---|---|---|---|---|
| C/C++ | `clangd-lsp` | Anthropic | `clangd --background-index` | .c .cc .cpp .cxx .h .hpp .hxx .C .H | `brew install llvm` (plus PATH) |
| C# | `csharp-lsp` | Anthropic | `csharp-ls` | .cs | `dotnet tool install --global csharp-ls` |
| Go | `gopls-lsp` | Anthropic | `gopls` | .go | `go install golang.org/x/tools/gopls@latest` |
| Java | `jdtls-lsp` | Anthropic | `jdtls` | .java | `brew install jdtls` |
| Kotlin | `kotlin-lsp` | Anthropic | `kotlin-lsp --stdio` | .kt .kts | `brew install JetBrains/utils/kotlin-lsp` |
| Lua | `lua-lsp` | Anthropic | `lua-language-server` | .lua | `brew install lua-language-server` |
| PHP | `php-lsp` | Anthropic | `intelephense --stdio` | .php | `npm install -g intelephense` |
| Python | `pyright-lsp` | Anthropic | `pyright-langserver --stdio` | .py .pyi | `npm install -g pyright` |
| Ruby | `ruby-lsp` | Anthropic | `ruby-lsp` | .rb .erb .gemspec .rake .ru | `gem install ruby-lsp` |
| Rust | `rust-analyzer-lsp` | Anthropic | `rust-analyzer` | .rs | `rustup component add rust-analyzer` |
| Swift | `swift-lsp` | Anthropic | `sourcekit-lsp` | .swift | `brew install swift` |
| TS/JS | `typescript-lsp` | Anthropic | `typescript-language-server --stdio` | .ts .tsx .js .jsx .mts .cts .mjs .cjs | `npm install -g typescript-language-server typescript` |
| Liquid | `liquid-lsp` | Shopify | in its own repo | Liquid | Shopify CLI (`shopify`) |

Every README install command is unpinned (`@latest`, brew, global npm). The skill must pin the
binary itself (tier 2, the tool's vendor). Several READMEs lead with `brew`, which does not exist
on a Linux or Windows machine; a per-OS install line is the skill's job.

Not covered by any official LSP plugin: Bash/shell, YAML, JSON, Markdown, Terraform/HCL, SQL,
Dart, Elixir, Scala, Zig, Vue/Svelte-specific servers. `serena` (below) is an MCP server that
wraps language servers; it is not a Claude Code LSP plugin and gives no post-edit diagnostics.

### Verification plugins (repo-kind tools, not per language)

| Plugin | Author | Source at `fa59bc9` | Runs | Runtime pin |
|---|---|---|---|---|
| `playwright` | listed as Microsoft, in `external_plugins/` | relative path | MCP: `npx @playwright/mcp@latest` | **unpinned** |
| `chrome-devtools-mcp` | Google ChromeDevTools | `url` @ `1cec9cd` | MCP: `npx chrome-devtools-mcp@1.9.0` | pinned 1.9.0 |
| `browser-use` | Browser Use | `git-subdir` @ `4749bcb` | local Chrome or Browser Use Cloud | not read |
| `postman` | Postman | `url` @ `1e5f49e` | API collections and tests | not read |
| `codspeed` | CodSpeed | `url` @ `59cfc90` | performance benchmarks | not read |
| `serena` | Oraios, in `external_plugins/` | relative path | MCP: `uvx --from git+https://github.com/oraios/serena ...` | **unpinned (git HEAD)** |

Only two entries carry `category: testing`: `playwright` and `growthbook` (feature flags, not
verification). There are no per-language test-runner plugins.

### Hook plugins (every relative-path plugin that ships `hooks/hooks.json`)

| Plugin | Events | What it does |
|---|---|---|
| `security-guidance` (v2.0.7) | SessionStart, UserPromptSubmit, PostToolUse, ... | security warnings on edits, LLM diff review on Stop |
| `hookify` | PreToolUse, PostToolUse, Stop, UserPromptSubmit | Python engine for user-authored hook rules |
| `ralph-loop` | Stop | re-prompt loop |
| `claude-security` | UserPromptExpansion, PostToolUse, ... | banner, metrics, tips |
| `code-modernization` | UserPromptSubmit, Stop, SessionStart, PostToolUse | telemetry scripts |
| `explanatory-output-style`, `learning-output-style` | SessionStart | output-style injection |

**No official plugin runs a repo's linter, formatter, typechecker or tests on edit or on Stop.**
The harness's check ladder has to be written by the skill as project hooks in
`.claude/settings.json` plus `.claude/hooks/`, which also has the advantage of carrying over to
cloud sessions.

### Adjacent: `claude-code-setup` (Anthropic)

One skill, `claude-automation-recommender`: "scan your codebase and recommend the top 1-2
automations in each category" (MCP servers, skills, hooks, subagents, slash commands); read-only.
It overlaps the audit half of `setup-harness` but writes nothing, has no trust tiers, pinning or
proof step. Worth reading its `references/hooks-patterns.md` as prior art, not composing it.

## 3. Project-scope enablement

Probed in a throwaway git repo with an isolated `CLAUDE_CONFIG_DIR` and
`CLAUDE_CODE_PLUGIN_CACHE_DIR`:

```sh
claude plugin marketplace add anthropics/claude-plugins-official --scope project
claude plugin install typescript-lsp@claude-plugins-official --scope project
```

writes exactly this committed `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": { "source": "github", "repo": "anthropics/claude-plugins-official" }
    }
  },
  "enabledPlugins": { "typescript-lsp@claude-plugins-official": true }
}
```

Rules ([install](https://code.claude.com/docs/en/plugins/install#choose-an-install-scope),
[loading](https://code.claude.com/docs/en/plugins/loading#enabled-in-project-settings-but-not-installed),
[org](https://code.claude.com/docs/en/plugins/org#require-plugins-per-repository)):

- `extraKnownMarketplaces` in a repo applies only after the contributor accepts the workspace
  trust dialog (interactive), or in a folder already trusted (`-p`).
- A **relative-path** plugin (all 12 Anthropic LSP plugins, `playwright`, `security-guidance`)
  loads from the marketplace copy once the marketplace applies, with no per-machine install.
- An **external-source** plugin (e.g. `chrome-devtools-mcp`, `liquid-lsp`) does not install
  from settings alone; each contributor runs `claude plugin install <name>@<mkt> --scope project`
  once, or sees `enabled in project settings but isn't installed here`.
- Personal opt-out: `false` in `.claude/settings.local.json` overrides the project `true`.
- **Cloud: none of this applies** (headline 2). Server-managed settings are the only
  settings-based route, and they are org-wide, not per repo.

A second committed route exists: a plugin vendored at `<repo>/.claude/skills/<name>/` with a
`.claude-plugin/plugin.json` loads as `<name>@skills-dir` for everyone, after workspace trust
([create](https://code.claude.com/docs/en/plugins/create), [loading](https://code.claude.com/docs/en/plugins/loading#plugins-shared-through-a-repository)).
It is pinned by the repo's own commit and fully readable in review. Whether it loads in a cloud
session (which never shows the trust dialog) is **not documented**; moot for LSP, which cloud
never starts.

## 4. Pinning and reading source before install

**Plugin source (inside a marketplace entry): pinnable to a commit.** `github`, `url` and
`git-subdir` sources take `ref` (branch or tag) and `sha` (full 40-char commit); with both set,
Claude Code checks out `sha`. `npm` takes `version`; `archive` takes `sha256`
([marketplace reference, plugin sources](https://code.claude.com/docs/en/plugins/marketplace-reference#plugin-sources)).
The official marketplace already pins **all 262** external entries by `sha`.

**Marketplace source (what a repo writes in `extraKnownMarketplaces`): branch or tag only.**
`github` and `git` marketplace sources take `ref` but have **no `sha` field**
([marketplace reference, fields by type](https://code.claude.com/docs/en/plugins/marketplace-reference#fields-by-type)).
Probed with 2.1.283, isolated config:

| Input | Result |
|---|---|
| `anthropics/claude-plugins-official` | added; clone HEAD `fa59bc9` |
| `anthropics/claude-plugins-official@main` | added (`ref: main`); HEAD `fa59bc9` |
| `anthropics/claude-plugins-official@<40-char sha>` | fails: `fatal: Could not read from remote repository` |
| `anthropics/claude-plugins-official#<40-char sha>` | fails, same error |

With no tags in the official repo, **a repo cannot pin the official marketplace (and therefore
its 52 relative-path plugins, all 12 Anthropic LSP plugins among them) to a commit.** What is
available:

- `autoUpdate: false` on the `extraKnownMarketplaces` entry stops the background refresh (default
  is on for `claude-plugins-official`) ([loading, auto-update](https://code.claude.com/docs/en/plugins/loading#which-marketplaces-and-plugins-auto-update)).
  This freezes one machine at its first clone; it does not make two machines agree, and a
  `name@marketplace` install still refreshes the marketplace first regardless of `autoUpdate`.
- The version gate: a plugin whose entry or manifest pins `version` (the LSP plugins pin
  `1.0.0`) is not updated until that string changes, however many commits land
  ([loading, version](https://code.claude.com/docs/en/plugins/loading#how-claude-code-computes-the-version)).
  Author-controlled, so not a pin the skill owns.
- An own inline marketplace (`settings` source) whose entries point at
  `git-subdir` of `anthropics/claude-plugins-official` at a `sha`: its items accept only `name`,
  `source`, `description`, `version`, `strict`, `headers`, `headersHelper`, so **it cannot carry
  the `lspServers` block** that the Anthropic LSP plugins keep in the marketplace entry. For the
  LSP plugins this route yields an empty plugin. (Doc reading; not probed.)
- Vendoring: copy the config into a repo-owned plugin (`.claude/skills/<name>/` or an own
  marketplace). The source is then pinned by the repo's commit. Cost: the repo owns updates.

**Record of what got installed.** `installed_plugins.json` records `version` and
`gitCommitSha` per install (probe: `typescript-lsp` 1.0.0, `gitCommitSha fa59bc9...`), which
is enough for a drift report even where a pin is impossible.

**Pinning the plugin does not pin what it runs.** `playwright` at a fixed marketplace commit
still executes `npx @playwright/mcp@latest`; `serena` runs git HEAD via `uvx`; the LSP binaries
are whatever is on `PATH`. The skill's "pin before install" rule has to reach the executed
package, not only the plugin commit.

**Reading full source before install**
([security, review before install](https://code.claude.com/docs/en/plugins/security#review-a-plugin-before-you-install)):

1. `claude plugin marketplace list` for the marketplace's source.
2. For a relative-path plugin: `plugins/<name>/` or `external_plugins/<name>/` in the
   marketplace repo, **plus the plugin's own entry in `marketplace.json`** (the LSP config lives
   there, not in the directory). For an external one: the entry's `source` repo at its `sha`.
3. Files that run code: `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `bin/`, and any scripts
   they call. The `/plugin` Will-install pane shows that a hook exists, not what it runs.
4. `claude --plugin-dir <dir> plugin details <name>` prints the component inventory (skills,
   agents, hooks with events, MCP and LSP servers) without starting a session; after install,
   `claude plugin details <name>` does the same for the cached copy (probe output: `LSP servers
   (1) typescript`, always-on cost ~0 tokens).

## Confidence

| Claim | Basis |
|---|---|
| LSP only via plugins; config fields; failure strings | docs, high |
| Cloud does not start plugin LSP servers | docs, one explicit sentence; not probed in cloud |
| Cloud does not install repo-enabled plugins | docs, stated on three pages; not probed in cloud |
| Catalog contents and runtime commands | read from `marketplace.json` and plugin files at `fa59bc9`, high |
| Project-scope settings shape | probed, high |
| Marketplace ref cannot be a SHA | docs plus probe, high |
| `settings`-source marketplace cannot carry `lspServers` | docs field list, medium; not probed |
| Skills-dir plugin in a cloud session | undocumented, unknown |
