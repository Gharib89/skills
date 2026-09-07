# Sandbox parent-directory writability for sibling worktrees

Resolves [#24](https://github.com/Gharib89/skills/issues/24) (part of #1). Question:
[#7](https://github.com/Gharib89/skills/issues/7) made `<parent>/<repo>.worktrees/` the core
worktree container on the assumption that the repo's parent is writable wherever Ship runs.
In the unattended lane (Claude Code cloud session / routine — where `cloud-ship` fires), where
is the repo cloned, and can a process `mkdir` beside it?

Vocabulary is [CONTEXT.md](../../CONTEXT.md): *Ship*, *unattended run*, *Host*, *sibling skill*.

## Verdict

**Docs are inconclusive for Anthropic-hosted sandboxes; the only concrete path evidence is
first-party but non-normative (the CLI binary).** Nothing found says the parent is *not*
writable, and the one path signal (`/home/user`) points at a directory that is writable by
construction. Confidence that `mkdir <parent>/<repo>.worktrees` works in an Anthropic-hosted
routine: **medium** — needs one live probe (below) before #7's rule is treated as verified.

For **self-hosted** environments the layout *is* documented and the parent is writable by
requirement (runner refuses to start otherwise). Nested depth differs, though: repo lives at
`<base-dir>/<owner>/<repo>`, so the sibling container lands at
`<base-dir>/<owner>/<repo>.worktrees/`.

## Sources read

| Source | What it settles |
|---|---|
| [cloud-environments.md](https://code.claude.com/docs/en/cloud-environments.md) | VM = fresh Ubuntu 24.04 x86_64 "with your repository cloned"; env vars `CLAUDE_CODE_REMOTE=true`, `CLAUDE_CODE_REMOTE_SESSION_ID`; `$CLAUDE_PROJECT_DIR` "resolves to the repository root". No absolute path. |
| [routines.md](https://code.claude.com/docs/en/routines.md) | "Each repository is cloned at the start of a run, starting from the default branch"; multi-repo routines exist; "no permission-mode picker and no approval prompts during a run". No path. |
| [claude-code-on-the-web.md](https://code.claude.com/docs/en/claude-code-on-the-web.md), [web-quickstart.md](https://code.claude.com/docs/en/web-quickstart.md) | "cloned to an Anthropic-managed VM". No path, no writable-area list. |
| [worktrees.md](https://code.claude.com/docs/en/worktrees.md) | `--worktree` / `EnterWorktree` create under `.claude/worktrees/<name>/` **inside** the repo — Anthropic's own worktree feature never writes to the parent. |
| [security.md](https://code.claude.com/docs/en/security.md) | "Working directory boundary: In Manual mode, Claude Code can only write to the folder where it was started and its subfolders, and can't modify files in parent directories without explicit permission." |
| [hooks.md](https://code.claude.com/docs/en/hooks.md) | `CLAUDE_PROJECT_DIR` = project root where the session started. |
| [self-hosted-environments-deploy.md](https://code.claude.com/docs/en/self-hosted-environments-deploy.md) | Runner `--base-dir` defaults to `/workspace`; "The runner needs write access to it … exits with `cannot create or write to base directory` when it can't"; canonical clone at `<base-dir>/<repo-owner>/<repo>`; `--capacity > 1` uses per-session worktrees instead. |
| [self-hosted-environments-configuration.md](https://code.claude.com/docs/en/self-hosted-environments-configuration.md) | Teardown-hook env `CLAUDE_RUNNER_WORKSPACE_PATHS` = "colon-separated absolute paths of the session's working trees" (runner hooks only, not the agent's shell). |
| [changelog.md](https://code.claude.com/docs/en/changelog.md) | No entry names the cloud clone path. |
| `claude` CLI binary v2.1.263 (`~/.local/share/claude/versions/2.1.263`, `strings`/`grep -a`) | Default cloud-environment create payload hard-codes `cwd:"/home/user"` (see below). Env-var registry includes `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID`, `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE`, `CLAUDE_CODE_REMOTE_MEMORY_DIR`, `CLAUDE_CODE_WORKSPACE_HOST_PATHS`. |
| cc-otel `scripts/cloud-ship-bootstrap.sh`, `.claude/skills/cloud-ship/SKILL.md`; crm `.claude/skills/cloud-ship/SKILL.md` | Neither records the sandbox path. See below. |

## Findings

### 1. Anthropic-hosted: repo path is undocumented; the CLI's default environment says `/home/user`

No docs page states where the clone lives. The CLI binary, when creating the *Default* cloud
environment (`POST /v1/environment_providers/cloud/create`), sends:

```
config:{environment_type:"anthropic",cwd:"/home/user",init_script:null,environment:{},
        languages:[{name:"python",version:"3.11"},{name:"node",version:"20"}],
        network_config:{allowed_hosts:[],allow_default_hosts:true}}
```

Reading: the session's working directory root is `/home/user`, so the clone is most plausibly
`/home/user/<repo>` and the parent is the sandbox user's **home directory** — writable for the
user by construction. This is an inference from one hard-coded field, not a documented
contract; `cwd` here may mean "where the clone goes" or "where the shell starts", and a
multi-repo routine implies one level of nesting per repo under that cwd.

Nothing in the docs' security or sandbox pages lists a read-only area other than what the
proxies keep *out* of the VM (git credentials, signing keys, API keys).

### 2. A second gate: the harness's working-directory boundary, not the filesystem

Even if the parent is writable at the OS level, [security.md](https://code.claude.com/docs/en/security.md)
says Manual mode "can't modify files in parent directories without explicit permission". A
routine has "no approval prompts", so a `mkdir ../<repo>.worktrees` either passes (routine
runs in an auto-approving mode) or is silently denied — the docs don't say which. The live
probe below has to run *through the Bash tool in a routine*, not just as a shell fact.

Anthropic's own worktree tooling sidesteps the question: `.claude/worktrees/` is in-repo.

### 3. Env vars naming the workspace root

- `CLAUDE_PROJECT_DIR` — documented: "resolves to the repository root" (hooks context; the
  cloud-environments page uses it in a SessionStart hook). Best available per-run root marker.
- `CLAUDE_CODE_REMOTE=true` — documented cloud marker.
- `CLAUDE_CODE_REMOTE_SESSION_ID` — documented.
- `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE`, `CLAUDE_CODE_REMOTE_MEMORY_DIR`,
  `CLAUDE_CODE_WORKSPACE_HOST_PATHS` — present in the binary's env-var registry, undocumented.
- `CLAUDE_RUNNER_WORKSPACE_PATHS` — self-hosted runner hooks only; not visible to the agent.

Practical rule: derive the parent as `$(dirname "$CLAUDE_PROJECT_DIR")` (or of `git rev-parse
--show-toplevel`), never a hard-coded `/home/user` or `/workspace`.

### 4. Self-hosted: documented, parent writable, one level deeper

`/workspace` (default `--base-dir`) is required-writable; clone is `<base-dir>/<owner>/<repo>`.
At `--capacity > 1` the runner itself puts sessions in per-session worktrees, and the
requeue note warns that "absolute paths the agent recorded earlier … point at a location that
no longer exists" if runners differ. A `<parent>/<repo>.worktrees/` sibling would be
`<base-dir>/<owner>/<repo>.worktrees/` — writable, but the runner's teardown deletes only
what it knows about (`CLAUDE_RUNNER_WORKSPACE_PATHS`); a sibling dir it didn't create is
leaked until the container goes.

### 5. `cloud-ship` copies don't record the path — they avoid the question

`cc-otel/scripts/cloud-ship-bootstrap.sh` only does `cd "$(dirname "$0")/.."` (repo-relative;
no `/workspace`, `/home`, `$PWD`, or `$CLAUDE_PROJECT_DIR`). Both `cloud-ship/SKILL.md`
copies (cc-otel line 78, crm line 74) say: "This branch in the sandbox clone IS `ship`'s
phase-0 isolation — don't create a worktree inside it; treat phase 0 as satisfied." So the
unattended lane today never creates a worktree at all, sibling or in-repo, and has no
evidence either way about parent writability.

## Implication for #7

The sibling-container rule is unverified in the unattended lane but not contradicted. Two
options, ranked:

1. **Keep sibling default, make the unattended lane skip isolation** (status quo in
   `cloud-ship`): the sandbox clone is already a throwaway; a worktree buys nothing there.
   Then parent writability never matters in the cloud and #7 stands as-is for attended runs.
2. **Sibling default with in-repo opt-in** (`.claude/worktrees/`-style fallback) if a live
   probe shows the parent is blocked. Only needed if option 1 is rejected.

## Live check (one command, run via the Bash tool inside a routine or cloud session)

```
p="$(dirname "$(git rev-parse --show-toplevel)")"; echo "root=$(git rev-parse --show-toplevel) parent=$p CLAUDE_PROJECT_DIR=$CLAUDE_PROJECT_DIR"; mkdir "$p/probe.worktrees" && echo PARENT_WRITABLE && rmdir "$p/probe.worktrees" || echo PARENT_NOT_WRITABLE; ls -ld "$p"; id
```

Expected if the inference holds: `root=/home/user/<repo> parent=/home/user`, `PARENT_WRITABLE`.
Record the output on #7 and this file's verdict can move from medium to high.
