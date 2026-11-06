# Research: a super agent that supervises many tickets across repos

Researched 2026-11-06 for the owner's "one agent to talk to" goal: a supervisor
that keeps a ticket ledger across repos, launches and watches T3 worker threads,
and routes work across every model, server and machine the owner has.

Each claim carries its basis: **verified** (primary page or repo file read),
**measured** (a probe run on 2026-11-06, command named), **secondary** (press or
third-party coverage), or **inferred**.

## 1. DeepSeek's "super-agent"

"Super-agent" is DeepSeek's own term, and recent. On 2026-10-31 DeepSeek's
Harness team published the article *Super-agent 设计探索：迈向更自主的Agent 系统*
("Exploring Super-agent Design: Towards a More Autonomous Agent System") on
WeChat, and released a research prototype the same day.

- The prototype is `deepseek-ai/dsh-superagent-prototype`: MIT, created
  2026-10-31T09:32:46Z, "Towards a More Autonomous Agent System". **measured**
  (`gh api repos/deepseek-ai/dsh-superagent-prototype`).
  <https://github.com/deepseek-ai/dsh-superagent-prototype>
- Its README calls it a "Research prototype for reference only", "not identical
  to our internal version", and says some article designs "are not implemented
  in this prototype". **verified**.
- The article's primary text was not found (WeChat, not linked from
  <https://www.deepseek.com/en/harness/>). Its claims below are **secondary**,
  from <https://www.ithome.com/0/1020/615.htm> and
  <https://tech.ifeng.com/c/8xkB5gAvNg1>.

### What the article describes (secondary)

- **Two layers.** A **Router** talks to the human, keeps global context and
  dispatches; **Workers** run tasks concurrently in isolated sessions and report
  to the Router, never to the human.
- **Event-driven**, with compute, state and environment kept apart.
- **Watchdog**: a separate session that catches infrastructure failures and
  "uses the model to check whether Workers are making real progress or drifting
  from their goals".
- **Memory**: "Inline & Spill" (recent facts in context, the rest stored and
  read on demand) and "Chain of Recall" (following reference ids across
  triggers, threads and worker sessions).
- **Result**: about 300 messages carrying about 20 work requests, 5 runs each.
  Super-agent p50 12.4 min, p95 15.7 min; one session with subagents p95
  29.5 min. Synthetic workload.
- **Router batching**: from about 1 to about 40 triggers a minute, batch size
  rose 1.0 to 2.8 and time per decision fell 6.4 s to 1.6 s. DeepSeek runs the
  Router on a lighter model.
- **Premise**: a person tracks about 3 to 5 live sessions; human attention is
  the bottleneck.

### What the prototype implements (verified from repo files)

Domain, <https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/001-domain.md>:

- Source, Trigger, Thread, Eval, **Ticket** (with a Mandate), Assignment,
  Executor; results go back through a Channel. Only Eval creates Tickets, and a
  Ticket "defines its own state instead of following the Executor's".
- A closed report enum: `progress`, `waiting`, `ready`, `blocked`, `failed`,
  `dropped`.
- Rejected on purpose: inferring "waiting on a person" from a report's free
  text (the Executor asks through a structured field), and cancelling running
  Tickets on a policy change (the change is recorded and delivered).

Router prompt, <https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/prompts/orchestrator.md>
(**measured**, `gh api .../contents/prompts/orchestrator.md`):

- "Workers investigate and implement; never add implementation plans."
- "Never merge or enable auto-merge yourself".
- "Worker reports, follow_up notices, new candidates and a background job's
  end, with its output, arrive by themselves as messages: never wait for them
  with sleep, polling or job waits; end the turn when nothing is left to do."
  A `noWait` guard enforces it: it refuses Router shell calls with `sleep`, a
  shell timeout over 30 s, or a job wait over 5 s (docs/007-architecture.md).

Execution, <https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/003-execution.md>:

- One Executor session and one directory per Ticket, prepared by a command such
  as `git worktree` (10 min limit).
- Foreground shell commands move to the background after 5 s, so a worker sees
  new messages at its next step. Background work gets at most 30 min after a
  turn, then is killed and the Ticket reported `waiting`.
- A slot limit on workers, "with one extra slot for a person's message".
- Transient failures (408, 429, 5xx, connection errors) retry three times with
  backoff, then the Ticket takes no automatic input until a person acts.
- On restart, running assignments end with "host restarted" and new ones start
  with a recovery note: check the directory, git history and GitHub before
  repeating any outside action, oldest Ticket first.
- Decisions are stored first and done afterwards (an outbox).
- Model per role, set when a session is created; an existing session keeps its
  model (`src/app/role-models.ts`). The handoff prompt: "do not change models
  or retry policy to conceal a failure."

What DeepSeek has **not** published: a Watchdog in the prototype (grep of its
docs and prompts finds none, **inferred** from a partial read of `src/`), a
cross-repo ledger (the prototype serves one repo), cross-vendor routing, or an
arXiv paper on super-agents. Its model releases (V3.1, V3.2) mention agent
training and tool use, not an orchestrator: <https://api-docs.deepseek.com/news/news250821>,
<https://api-docs.deepseek.com/news/news251201> (**verified**).

Others use the term too: ByteDance DeerFlow, "An open-source long-horizon
SuperAgent harness" (<https://github.com/bytedance/deer-flow>, **verified**), and
Genspark's consumer "Super Agent" (2025, **secondary**).

## 2. The AI LABS video

"Deepseek Just Released The Greatest Claude Code Workflow Ever", AI LABS,
2026-11-05, 14 min: <https://youtu.be/3DklR44DHnM>. Read from its English
captions (`yt-dlp --write-auto-subs`). It rebuilds DeepSeek's design in one
local Claude Code session:

- **Tickets** from a ticket-writing skill that grills the human until nothing is
  unclear: per feature an `rd.md` (what to build, what not to touch, decisions)
  and an `eval.md` (checks, edge cases, what done means).
- **`board.md`**: status (draft, ready, done), mode (solo subagent or team via
  agent teams), and runs (alongside, or waits on ticket N, with the reason). The
  human marks a ticket ready; the router picks it up.
- **Router**: `claude --agent router`, Opus at high effort, told never to write
  (held back by instruction, since teammates inherit its tools). It checks each
  worker's result against `eval.md` and sends a fix back to the same worker,
  which still holds the ticket's context. It comes to the human only for a
  choice.
- **Watchdog**: started first by the router, Sonnet at medium effort, compacts
  at 150k tokens. Every 10 min it runs a small script that lists stuck,
  looping, or mutually waiting agents and tells the router. Without it, a worker
  that goes quiet is never noticed, since the router hears only what workers
  say.
- **Workers** on Sonnet, because the ticket already spells out the work.
- Helpers: a merger, a checker and a tester (Vercel agent-browser), and a
  reproducer that repeats a bug, fixes a small one on its own branch, and
  reports otherwise.
- Cost: about 1 hour for 3 tickets (a team ticket stopped at 26 min, two solo
  tickets side by side at 11 and 17 min).

Against the owner's setup: tickets and the board already exist as GitHub
issues, `/triage` agent briefs with acceptance criteria, and native blocking
edges. What the video adds is the router verifying against the acceptance
criteria, the fix going back to the same worker, and a script-first watchdog.
It does not cover cross-repo work or an always-on host (**inferred**).

## 3. Anthropic's guidance

- **Building effective agents**: orchestrator-workers fits "complex tasks where
  you can't predict the subtasks needed"; take ground truth from the
  environment each step; give stopping conditions.
  <https://www.anthropic.com/engineering/building-effective-agents> (**verified**)
- **Multi-agent research system**: the lead saves its plan to memory before the
  context fills; each subagent gets an objective, an output format, tools and
  boundaries; subagents return lightweight references; synchronous subagents
  block the whole system on the slowest; errors compound, so resume from the
  failure point. About 15x the tokens of a chat.
  <https://www.anthropic.com/engineering/multi-agent-research-system> (**verified**)
- **Context engineering**: compaction keeps decisions and open bugs and drops
  redundant tool output; structured notes outside the window; sub-agents return
  1,000 to 2,000 tokens; keep identifiers and load data just in time.
  <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents> (**verified**)
- **Long-running harnesses**: a progress file plus a JSON feature list (agents
  rewrite JSON less casually than Markdown, and edit only `passes`); one feature
  per session; a fixed session-start routine; the failure modes are declaring
  victory early and leaving undocumented state.
  <https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents> (**verified**)

## 4. Other orchestrator patterns

- **Magentic-One** (Microsoft Research), <https://arxiv.org/html/2411.04468> and
  AutoGen's `_magentic_one_orchestrator.py` (**verified**). A **task ledger**
  (facts given, to look up, to derive, guesses, plus a plan) and a **progress
  ledger** answered every step: `is_request_satisfied`, `is_in_loop`,
  `is_progress_being_made`, `next_speaker`, `instruction_or_question`. The
  **stall counter**: +1 on no progress, +1 on a loop, otherwise -1 (floor 0);
  at `max_stalls` (default 3) it re-plans: update facts, update the plan after
  reflecting on what went wrong, reset every agent's context, re-broadcast the
  ledger.
- **Cognition, "Don't Build Multi-Agents"**: share full context, since actions
  carry implicit decisions and parallel fragments conflict.
  <https://cognition.com/blog/dont-build-multi-agents> (**verified**). One worker
  per independent ticket splits no task, so it is the safe case (**inferred**).
- **OpenAI Agents SDK**: agents-as-tools keeps the manager in control, handoffs
  pass control; orchestrating in code is "more deterministic and predictable".
  <https://openai.github.io/openai-agents-python/multi_agent/> (**verified**)
- **LangGraph supervisor**: archived; its README now recommends "the supervisor
  pattern directly via tools" for control over context.
  <https://github.com/langchain-ai/langgraph-supervisor-py> (**verified**)

## 5. T3 Code: what wakes a supervisor (measured)

Probes P1 to P5 and A1 to A3, run 2026-11-06 from a Claude thread in `auto`
mode. A "wake" means a new turn starts in the supervisor after its turn ended.

| Mechanism | Wakes the supervisor? | Notes |
|---|---|---|
| `delegate_task` child finishes | **Yes**, with the child's summary | P1 woke twice: first a premature "completed" (the child had moved its command to the background), then the real output from its continuation run. |
| `t3_thread_launch` thread finishes, even with `delegatedFrom` set | **No** | P3 got `parentThreadId: null` despite `delegatedFrom`. Matches the crm batch's lost 30 minutes. |
| Background Bash exits | **Yes**, about 5 s after exit | P5: exited 05:34:43, woke 05:34:48. Bash `run_in_background` allows up to 2 h. |
| `schedule_task` once or interval, bound to this thread | **Yes**, as a user-role message | P4 fired on time. Interval minimum is 60 s. |
| A child's permission prompt | **No** | A1, A3: the hold shows only in `task_status.pendingApproval`; the owner saw it in the UI. |
| `watch_pull_request` | Docs say yes (failed checks, required checks passing, comments, reviews, conflicts) | Not yet measured; to be measured on this branch's PR. |

Other measured facts:

- `delegate_task` runs only in the supervisor's own project: `target.projectId`
  for another repo is refused ("A local task runs in this thread's project").
  A worker in another repo is a `t3_thread_launch` thread, or a delegate on
  another machine through `target.environmentId`.
- A run's `completed` status does not mean the work is done. P3's run reported
  `completed` after 8 s while its real command still ran in the background, then
  a second run delivered the output. A foreground `sleep` is blocked by the
  harness in workers too. This is the crm batch's stall class.
- `t3 thread show <id> --json` (the `t3` CLI) prints a thread's status,
  `runCount`, `latestRunId`, `pendingRequestCount`, `pullRequests`, `settled`
  and `worktreePath`. 5 runs: median 0.92 s, range 0.90 to 1.92 s. The CLI
  build is older than the server and logs a migration-divergence warning on
  stderr. So a background shell watcher can poll every worker and exit on a
  change, which wakes the supervisor.
- `t3_thread_list` over all projects reported 916 threads. Archiving works
  (`t3_thread_organize archive`); settle and snooze exist.
- `t3_pending_request` "cannot approve a permission request": a supervisor
  cannot clear a worker's permission hold.

## 6. Antigravity (`agy`) (measured)

- Through T3: `delegate_task` to the `antigravity` provider with `runtimeMode`
  `full-access` is refused from an `auto` parent ("Child runtime mode
  full-access is broader than parent mode auto"). In `auto` (inherited) or
  `auto-accept-edits`, the child holds its first shell command for approval
  (A1, A3). So a shell-running agy child under T3 needs a full-access
  supervisor.
- `agy` CLI 1.4.12: `--mode auto` prints "the terminal sandbox is not available
  on this host" and falls back to a default mode that auto-denies
  `RunCommand` in print mode.
- A session-only allow rule works without `--dangerously-skip-permissions`:
  `agy -p "<task>" --settings '{"permissions":{"allow":["command(*)"]}}' --output-format json`
  ran the shell command, 12.4 s wall, 30.8k input tokens.
- `agy -p /usage --output-format json` prints the quota as JSON: a **Gemini**
  group (weekly 97% left at the probe) and a **Claude and GPT** group (Claude
  Opus 4.6, Sonnet 4.6, GPT-OSS; 100% left), each with a weekly and a 5-hour
  bucket and a reset time. Both are separate from the Claude Code subscription.
- Models: `gemini-3.8-flash-{high,medium,low}`, `claude-sonnet-4-6`,
  `claude-opus-4-6-thinking`, `gpt-oss-120b-medium` (`agy models`).

## 7. Inventory (measured 2026-11-06)

- **T3 providers** (`orchestrator_capabilities`): Claude (Opus 5.5, Sonnet 5.5,
  Fable 5.1, Haiku 5.5), Codex (`gpt-6.1-sol`, `gpt-6-astra`, `gpt-6.1-terra`,
  `gpt-6-luna`, 4 more), Antigravity (the models above). Cursor, Grok, OpenCode,
  fx, Kiro, Muse and Pi are disabled. Batch thread creation up to 20; scheduled
  tasks on.
- **T3 environments** (`t3_environment_links`): `gharibs-server` reachable
  (full access, link expires 2026-12-03); `Gharib-ITWorx` unreachable.
- **Herdr machines** (`herdr machine list`): `server` (`myserver`) only. The OMEN
  laptop named in the hosts rule is not saved there.
- **This host**: 12 cores, 30 GB RAM (20 GB available), RTX 2070 Super Max-Q
  8 GB.
- **GitHub** (`gh auth status`): `Gharib89` (active; `repo`, `workflow`,
  `delete_repo`) and `ahmed-gharib89` (`repo`, `workflow`).
- **MCP** (`claude mcp list`, in this repo): connected are Exa, Microsoft Learn,
  Microsoft 365 and Playwright. Context7, Claude Docs, Excalidraw, Notion,
  Linear, Atlassian, Asana, Box, Canva, HubSpot and Intercom are disabled for
  this project; Firecrawl needs authentication. The `ctx7` CLI covers library
  docs without the MCP.

## 8. Implications for the design

Each traces to a section above; the design proposal decides among them.

1. **Wake by a background watcher, not by ending a turn and hoping.** Only
   delegate completions, background Bash exits, schedules and (per docs) PR
   watches wake a supervisor; launched threads and permission holds never do
   (section 5). A watcher over `t3 thread show` and GitHub REST that exits on
   any change gives one wake path for every worker in every repo, the same shape
   as `drive-session`'s `watch`.
2. **Detect stalls from state, judge them with a model.** A run `completed`
   with no merged PR and no gate summary is the stall signature (section 5).
   Count stalls Magentic-One style (+1, -1, act at 3) and act by re-briefing
   the same thread first, a fresh thread second (sections 2, 4).
3. **Ticket state lives in a file outside the context, in JSON, with a closed
   stage enum**, written before acting (DeepSeek outbox, Anthropic harness).
   GitHub stays the source of truth for issues, edges and PRs.
4. **The supervisor routes and verifies; it never implements.** It checks a
   finished worker against the issue's acceptance criteria and sends a fix back
   to the same thread (sections 1, 2).
5. **One ticket, one thread, one worktree**, model picked at launch and recorded
   (DeepSeek role models; owner's crm practice).
6. **Use agy's separate quota for text work and second reviews** through the
   CLI with session allow rules; a T3 agy child needs a full-access supervisor
   (section 6).
7. **Reserve a slot for the owner** and cap live workers near the 3 to 5 a
   person can follow (DeepSeek).
8. **Recover by checking before repeating**: after a crash or compaction, read
   the worktree, git log and PR before any outside action (DeepSeek restart
   note).
