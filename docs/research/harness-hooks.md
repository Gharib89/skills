# Claude Code hooks for fast verification

Research for [#337](https://github.com/Gharib89/skills/issues/337), part of map [#333](https://github.com/Gharib89/skills/issues/333) (`setup-harness`). Question: how do Claude Code hooks carry the check ladder (per edit on `PostToolUse`, per turn end on `Stop`)?

Sources are the Claude Code docs at code.claude.com (fetched 2026-09-26 as Markdown), the `anthropics/claude-code` CHANGELOG, and local probes run with `claude -p` on Claude Code 2.1.283 (model `haiku`, `--setting-sources project`, scratch git repo; no user settings touched). Each claim carries its source: **[H]** [Hooks reference](https://code.claude.com/docs/en/hooks), **[G]** [Hooks guide](https://code.claude.com/docs/en/hooks-guide), **[CE]** [Cloud environments](https://code.claude.com/docs/en/cloud-environments), **[P]** [Permissions](https://code.claude.com/docs/en/permissions), **[M]** [Monitoring](https://code.claude.com/docs/en/monitoring-usage), **[E]** [Env vars](https://code.claude.com/docs/en/env-vars), **[CL x.y.z]** changelog entry, **[probe]** measured here.

## Answer in brief

1. **Input and output.** `PostToolUse` gets the edited file as `tool_input.file_path` (always absolute) on stdin. `Stop` gets no file list at all. Only exit 2, `decision: "block"` or `additionalContext` reach Claude. Exit 1, the usual linter failure code, is shown to nobody but the debug log, and the turn goes on as if the check passed. The default timeout is 600 s, and a timed-out hook's output is discarded, so a slow check passes silently. `async` hooks cannot block. `asyncRewake` can wake Claude on exit 2.
2. **Changed files only.** Per edit: read `tool_input.file_path` and narrow with `matcher` plus a per-handler `if` (such as `Edit(*.ts)`), so no process spawns for other files. Per turn: work out the change set yourself (`git status --porcelain`, which also catches files that `Bash` wrote), and skip no-op turns by comparing a working-tree fingerprint to the last one checked.
3. **Stop loops.** A blocking Stop hook is re-run on the continuation with `stop_hook_active: true`. Claude Code ends the turn after 8 consecutive blocks (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). Measured: an always-blocking hook ran 9 times over 10 turns and the run ended with an empty result. Bound it with a fingerprint rather than a bare `stop_hook_active` exit, which lets a still-failing check pass after one retry.
4. **Cloud.** Yes, with limits. Hooks in the committed `.claude/settings.json` run in an Anthropic-hosted cloud session that has **one** repository. A multi-repo session does not read them. Hooks shipped through a plugin that the repo enables do not run, because cloud sessions do not install repo-declared plugins. User `~/.claude/settings.json` hooks never reach the cloud. Not probed in a real cloud session.
5. **Cost gotchas.** Every Stop block costs a full model turn. Sync `PostToolUse` hooks run one after another even across a parallel batch of edits (measured). Hook text over 10,000 characters is moved to a file behind a 2,000-character preview. Several past bugs cost context or prompt cache, so the skill should require a minimum version.

## 1. Input, exit codes, output, timeouts, async

### Input on stdin

- Every event gets `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode` (most events), plus `prompt_id` (v2.1.196+) and `scratchpad_dir` (v2.1.257+) **[H: Common input fields]**. `cwd` follows Claude into a worktree or after `cd`. `${CLAUDE_PROJECT_DIR}` stays at the session's start root **[H: Reference scripts by path]**.
- `PostToolUse` adds `tool_name`, `tool_input`, `tool_response`, `tool_use_id`, `duration_ms`. File-tool paths are always absolute **[H: PostToolUse input]**, fixed for Write/Edit/Read in **[CL 2.1.89]**.
- Measured `Edit` payload **[probe]**: `tool_input` has `file_path`, `old_string`, `new_string`, `replace_all`. `tool_response` has `filePath`, `oldString`, `newString`, `originalFile`, `structuredPatch` (hunks with `oldStart`, `newLines` and `lines`), `userModified` and `replaceAll`. The `structuredPatch` gives changed line ranges, which a line-scoped linter could use.
- `Stop` adds `stop_hook_active`, `last_assistant_message`, `background_tasks` and `session_crons` **[H: Stop input]**. Measured **[probe]**: exactly those fields, and **no list of files changed in the turn**.
- `PostToolBatch` fires once per batch of tool calls, with a `tool_calls` array (each entry has `tool_name`, `tool_input` and the serialized `tool_response`). It has no matcher **[H: PostToolBatch]**.
- Coverage gap: a `PostToolUse` hook on `Edit|Write` does not fire when `Bash` or an outside process rewrites the file **[H: PostToolUse]**. `FileChanged` watches only literal filenames in the working directory **[H: FileChanged]**, so it does not replace this for source trees.

### How failure reaches the model

| Hook output | Claude sees it? | Turn | Source |
| :--- | :--- | :--- | :--- |
| exit 0, stderr | No (debug log only) | continues | [H: Exit code 0] |
| exit 0, plain stdout | No for `PostToolUse` and `Stop` (debug log) | continues | [H: Exit code 0] |
| exit 1 (or any code but 2), plain text | **No**. The user sees a `hook error` notice with stderr's first line | continues | [H: Other exit codes], **[probe]**: Claude answered "NONE" |
| exit 2, stderr | Yes, stderr is shown to Claude | continues (tool already ran) | [H: Exit code 2 per event], **[probe]** |
| exit 0, `{"decision":"block","reason":...}` | Yes, `reason` is placed next to the tool result | continues | [H: PostToolUse decision control], **[probe]** |
| exit 0, `hookSpecificOutput.additionalContext` | Yes, as a system reminder | continues | [H: Add context for Claude], **[probe]** |
| `{"continue": false}` | Claude stops processing entirely | ends | [H: JSON output] |

- The skill's hook wrapper must turn any nonzero linter exit into exit 2 (or JSON). This is the gotcha most likely to bite, because linters exit 1 by convention **[H: Other exit codes warning]**.
- For `Stop`, exit 2 or `decision: "block"` keeps Claude going, with the message as the reason. `hookSpecificOutput.additionalContext` also continues the turn, but is labelled "Stop hook feedback" rather than a hook error (v2.1.163+) **[H: Stop decision control]**, **[CL 2.1.163]**.
- `PostToolBatch` behaves differently: `decision: "block"` or `continue: false` **stops the agentic loop** before the next model call **[H: PostToolBatch decision control]**. A batched per-edit check that wants Claude to fix things should return `additionalContext`, not block.
- The "turn ends by default, set `continueOnBlock`" rule for `PostToolUse` applies to `prompt`-type hooks (`ok: false`), not to command hooks **[H: Response schema]**.
- Stdout must be JSON only. A shell profile that echoes on startup breaks parsing silently on exit 0 **[G: Hook JSON has no effect]**. Exec form (`"args": []`) avoids the shell entirely **[H: Exec form]**, added in **[CL 2.1.139]**.
- `additionalContext`, `systemMessage` and plain stdout are each capped at 10,000 characters. Anything longer goes to a file, and Claude gets the path plus a 2,000-character preview, with no prompt to read it **[H: JSON output]**, **[CL 2.1.89]**. Put the first failures first and trim.

### Timeouts

- `timeout` is in seconds. The default is 600 for `command`, `http` and `mcp_tool` hooks (raised from 60 in **[CL 2.1.3]**), 30 for `prompt`, and 60 for `agent` **[H: Common fields]**.
- A hook that hits its timeout is cancelled and **its output is discarded, so it renders no decision** **[H: Timeouts]**. A check that exceeds its budget therefore passes silently. The skill should set `timeout` explicitly on each rung, and the script should enforce its own shorter internal budget so it can report "check too slow" before Claude Code kills it.

### Async and background hooks

- `"async": true` (command hooks only) runs the hook in the background. Its `decision`, `permissionDecision` and `continue` have no effect. `additionalContext` and `systemMessage` are delivered on the **next** turn, or wait for the next user message if the session is idle. `timeout` is not enforced. There is no dedup across firings. In `claude -p` the hook is killed at teardown with outcome `cancelled` **[H: Run hooks in the background]**.
- `"asyncRewake": true` runs in the background, keeps `timeout` enforced, and on exit 2 wakes Claude immediately (even when idle) with stderr as a system reminder **[H: Command hook fields]**, **[H: Limitations]**.
- For the ladder: the per-edit and per-turn rungs should stay synchronous, because only sync hooks can make Claude act before it declares done. `asyncRewake` fits a check that is slower than its rung but should still interrupt, but it spawns one process per firing with no dedup, so a burst of edits starts a burst of runs.

## 2. Target only changed files, skip no-op turns

- **Per edit.** Use `matcher: "Edit|Write"` on `PostToolUse`, and a handler-level `if` with permission-rule syntax to filter by path, such as `"if": "Edit(*.ts)"`. `if` is evaluated before spawning, so a non-matching file costs no process **[H: How a hook resolves]**, **[CL 2.1.85]**. `Edit` rules apply to all built-in file-editing tools **[P]**, so `Edit(*.ts)` should cover `Write` too (inferred from [P], not probed). Since v2.1.214, a single-segment `Edit(src/**)` matches only `<cwd>/src`, so write `Edit(**/src/**)` for any depth **[H: Common fields]**. One `if` holds one rule: use one handler per extension group **[H: Common fields]**.
- **Per edit, batched.** `PostToolBatch` gives every file in a parallel batch at once, so one linter process can cover them all **[H: PostToolBatch]**. It has no matcher or `if`, so it spawns on every batch, reads included.
- **Per turn.** `Stop` has no file list **[probe]**. Two ways to get the change set:
  - Run `git status --porcelain` (lists untracked files that `git diff` misses **[H: PostToolUse]**) or `git diff --name-only HEAD` plus untracked files. This also catches files written through `Bash`.
  - Have the `PostToolUse` hook append each `file_path` to a list keyed by `session_id` under `scratchpad_dir`, and have `Stop` consume it. This misses `Bash` writes, so git is the more complete source.
- **Skip no-op turns.** `Stop` fires whenever Claude finishes responding, not only when a task is done **[G: Limitations]**. Measured: it fired on a turn with no tool calls at all **[probe]**. Fingerprint the working tree with a throwaway index and skip when it matches the last fingerprint checked:

  ```sh
  t="$(git rev-parse --git-dir)/harness-fp-index"; cp "$(git rev-parse --git-dir)/index" "$t"
  GIT_INDEX_FILE="$t" git add -A && GIT_INDEX_FILE="$t" git write-tree
  ```

  Measured **[probe]**: the same hash on two calls with no change, a new hash after an edit, the real index untouched, about 13 ms on a small repo, and `.gitignore` respected, so build output does not count as a change. This is a technique designed here, not a documented Claude Code feature. Cost on a large monorepo is not measured.

## 3. Stop loop hazards and bounds

- A blocking Stop hook is re-invoked when Claude next finishes, with `stop_hook_active: true` **[H: Stop input]**.
- Claude Code overrides the block and ends the turn after 8 consecutive continuations **[H: Stop input]**. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` changes the cap, and `0` disables it **[E]**. Before **[CL 2.1.143]**, a hook that always blocked looped forever.
- Measured **[probe]**, always-blocking hook: 9 Stop invocations (1 with `stop_hook_active: false`, then 8 with `true`), `num_turns` 10, an empty `result`, 30 s wall time, and about 3x the cost of a one-turn run.
- Measured **[probe]**, the documented guard (`stop_hook_active` true means exit 0): 2 invocations, and the second pass let Claude stop whatever the state. On a turn with no edits, an instruction-style block ("run X before stopping") made Claude spend a turn asking what to do.
- **Recommended bound** (derived from the above, not documented):
  - The Stop hook **runs** the checks itself and blocks only with their failure output, never with an instruction for Claude to run them.
  - Skip when the fingerprint equals the last green fingerprint (a no-op turn).
  - On `stop_hook_active: true`, re-check only if the fingerprint changed since the last block, meaning Claude made progress. If it did not change, allow the stop and use `systemMessage` to tell the user the check is still red. The 8-cap stays as the backstop.
  - A bare `stop_hook_active` exit is weaker: a second failing attempt passes.
- Related fixes to take as a minimum version: **[CL 2.1.78]** (API errors plus stop hooks looping), **[CL 2.1.259]** (a blocking Stop hook made the next turn lose reasoning and miss the prompt cache), **[CL 2.1.274]** (Stop prompt hooks re-sent their whole prompt on every block).

## 4. Committed hooks in cloud sessions

- The repo's `.claude/settings.json` hooks and permission rules are available "Yes, in a session with one repository". A session with several repositories, including a project thread, starts above the clones and does not read them **[CE: What carries over]**.
- Plugins and marketplaces declared in the repo's `.claude/settings.json` are **not** installed in cloud sessions **[CE: What carries over]**. A harness hook that ships inside a plugin (for example an LSP or formatter plugin carrying its own `hooks/hooks.json`) will not run in the cloud. Ship the hooks as `.claude/hooks/*` scripts referenced from `.claude/settings.json`.
- An Anthropic-hosted environment runs hooks from the repository and from server-managed settings. User `~/.claude/settings.json` hooks never reach the cloud **[CE: Setup scripts vs. SessionStart hooks]**, **[H: Hook locations]**.
- There is no cloud-only scoping. A hook can branch on `CLAUDE_CODE_REMOTE=true` **[CE]**, **[E]**, **[H: Hook handler fields]**.
- The tools a hook calls must exist on the VM. `jq`, `git`, `ruff`, `mypy`, `pytest`, `eslint` and `prettier` come pre-installed. Anything else comes from the setup script or a `SessionStart` hook **[CE: Installed tools]**.
- Trust: `-p` and SDK sessions treat the folder as trusted for hooks **[H: Workspace trust]**. Measured locally **[probe]**: in `-p` on an untrusted folder the project hooks ran, but `permissions.allow` from the same `.claude/settings.json` was ignored, with the warning "this workspace has not been trusted" (as documented in [P: What runs before you trust a folder]). How a cloud session treats trust is not stated. The carry-over table says hooks and permission rules both apply.
- **Not probed in a real cloud session.** Settling "unchanged" at the evidence level this repo expects means one web-session run (per the repo's cloud-probe practice) that checks the hook fires, `${CLAUDE_PROJECT_DIR}` resolves, and the linter binary exists.

## 5. Hook-cost gotchas from the changelog and probes

| Gotcha | Evidence | Harness consequence |
| :--- | :--- | :--- |
| Sync `PostToolUse` hooks run one after another across a parallel batch | **[probe]**: 2 `Write` calls in one assistant message, 2 s hooks ran 315.94 to 317.94 and 317.99 to 319.99, no overlap. The docs say it "fires concurrently when Claude makes parallel tool calls" [H: PostToolBatch], which the probe did not show for `Write` (one run, thin) | Per-edit latency adds up per file. Keep the per-edit rung to seconds, or batch it on `PostToolBatch` |
| Each Stop block is a full model turn | **[probe]** 10 turns, about 3x cost | Block only on real failures, and skip no-op turns |
| Exit 1 is invisible to Claude | [H], **[probe]** | Wrapper maps failure to exit 2 |
| Timeout output is discarded, and the default is 600 s | [H: Timeouts], **[CL 2.1.3]** | Set `timeout` per rung, and self-report slowness |
| Output over 10k characters is moved to a file with a 2k preview | [H], **[CL 2.1.89]** | Trim to the first N errors |
| `if` avoids process spawns | **[CL 2.1.85]** | Use `if` per extension group |
| A formatter hook that rewrites the file broke the next `Edit` with "File content has changed" | **[CL 2.1.90]** fixed | Minimum version for any format-on-edit hook |
| JSON-output hooks injected no-op system reminders every turn | **[CL 2.1.73]** fixed | Minimum version |
| Async hooks: empty transcript entries, retained output, no stdin with `read -r` | **[CL 2.1.119]**, **[CL 2.1.208]**, **[CL 2.1.72]** fixed | Minimum version if async is used |
| Megabytes of hook error output could wedge a session on "Prompt is too long" | **[CL 2.1.247]** fixed | Trim anyway |
| Hook context around parallel tool calls lost on resume | **[CL 2.1.261]**, **[CL 2.1.267]** fixed | Minimum version |
| `SessionStart` output caused a full prompt-cache miss after `/clear` | **[CL 2.1.277]** fixed | Relevant to the dependency-install hook |
| Stdout that looks like a `{...}` object but is not valid JSON was treated as plain text | **[CL 2.1.248]** now an error | Build JSON with `jq -n` |

v2.1.277 is the lowest version with every fix above. v2.1.280 adds output-size attributes to OTel.

**Measuring the budget.** The OTel event `claude_code.hook_execution_complete` carries `hook_event`, `hook_name`, `num_hooks`, `num_blocking`, `num_non_blocking_error`, `num_cancelled`, `total_duration_ms`, and (v2.1.280+) `additional_context_chars` and `num_outputs_persisted` **[M]**. The debug log records each hook's exit and output **[H: Debug hooks]**. Either gives `setup-harness` a measured number per rung instead of an adjective.

## Where evidence is thin

- Cloud behaviour (part 4) is documented, not measured.
- PostToolUse concurrency: one `haiku` run with two `Write`s. Hooks on read-only tools, or on a mixed batch, may run concurrently as the docs say.
- Whether `if: "Edit(*.ts)"` filters `Write` calls: inferred from the permissions page, not probed.
- Fingerprint cost on a large repo: not measured.

## Sources

- Hooks reference: https://code.claude.com/docs/en/hooks
- Hooks guide: https://code.claude.com/docs/en/hooks-guide
- Cloud environments: https://code.claude.com/docs/en/cloud-environments
- Permissions (workspace trust, Edit rules): https://code.claude.com/docs/en/permissions
- Env vars: https://code.claude.com/docs/en/env-vars
- Monitoring (hook OTel events): https://code.claude.com/docs/en/monitoring-usage
- Changelog: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- Probes: Claude Code 2.1.283, `claude -p --setting-sources project --model haiku --permission-mode acceptEdits`, scratch repo with logging `PostToolUse` and `Stop` hooks, 2026-09-26.
