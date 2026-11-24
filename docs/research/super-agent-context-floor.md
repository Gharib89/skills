# Super agent: what the pinned thread's context floor is made of

Evidence for the wayfinder ticket #1370 (map #1310). It follows
`super-agent-context-per-wake.md` (branch `research/super-agent-wake-count`),
which measured that a fresh pinned thread's first call reads about 64k tokens
and the first call after a compaction about 76k, and left open what fills
them. Counted on 2026-11-24.

The **floor** is the context (input plus cache read plus cache write tokens)
of the first API call after a fresh start or after a compaction. Every later
call in the thread reads at least that much.

## How it was measured

- **The real request.** Since Claude Code 2.1.330 a transcript logs every API
  request in full (system blocks, tool definitions, messages). The newest
  pinned thread (S6, started 23 Nov, Opus 5.5, 217 logged requests) gives the
  exact content of its first call and of its first call after a compaction.
  `req.py` rebuilds a request and `parts.py` cuts it into named parts.
- **Tokens per part.** `tok.sh` sends one part as the only user message of a
  near-empty headless request (`claude -p`, Opus 5.5, no tools, no settings,
  no MCP) and reads the API's own usage, minus the 937-token empty baseline.
  The baseline drifted between 938 and 943 across the day, so each count is
  good to about 10 tokens.
- **Check.** The parts of the first call sum to 29,259 tokens for the cached
  prefix (tools and system) against 29,384 measured, and 35,602 for the
  messages against 35,624 measured. The post-compaction parts sum to 50,677
  against 50,703 measured.
- **Compactions.** `compact.py` reads all 42 compactions of the six pinned
  transcripts (S1 to S6, 6 to 23 Nov): the first call after each, and the
  size of every attachment put back.
- **Probes.** Four headless runs (`probe.sh`) and two scratch T3 threads in
  this project, each on Opus 5.5 with one fixed prompt, with settings changed.
  `shape.py` compares their first requests part by part.

Every number below is **measured** by one of these unless a sentence says
inferred.

## 1. The fresh floor: 65,008 tokens

First call of S6 (cache read 29,384, cache write 35,622, input 2).

| Part | Tokens | Share |
|---|---|---|
| Built-in tool definitions (14 tools) | 22,716 | 34.9% |
| Owner's global instructions (CLAUDE.md 2,438, 17 rules 9,103) | 11,541 | 17.8% |
| Skills listing (55 skills) | 7,733 | 11.9% |
| SKILL.md, loaded by the slash command (369 lines) | 7,668 | 11.8% |
| MCP and T3 (see below) | 7,697 | 11.8% |
| Harness system prompt | 2,115 | 3.3% |
| Agent types listing | 1,940 | 3.0% |
| Small reminders (environment, output style, git status, attribution, model, one plugin hook line) | 1,887 | 2.9% |
| Project CLAUDE.md | 1,564 | 2.4% |
| Not allocated (request framing) | 147 | 0.2% |

**Tool definitions.** The `Artifact` tool alone is 12,104 tokens, 18.6% of the
floor. Then `Workflow` 2,070, `AskUserQuestion` 1,767, `Agent` 1,741, `Bash`
1,282, `ListAgents` and `ShareOnboardingGuide` about 1,195 together (inferred
from their share of characters), and seven small ones 2,557. Across the six
sessions (about 6,500 tool calls) the pinned thread called `Artifact` twice,
`Agent` 4 times, `Workflow`, `ListAgents` and `ShareOnboardingGuide` never, and
`AskUserQuestion` 38 times.

**MCP and T3.** T3's system prompt text 2,203; the list of deferred tool names
2,147; the Chrome integration's instructions in the system prompt 1,427; T3's
two always-loaded tools 798; notices about servers that need sign-in or are
still connecting 660; MCP server instructions 462.

**Skills listing.** Personal skills 2,527 (26 skills), built-in 2,604 (17),
plugin and account skills 2,437 (10), project skills 148 (2).

**The floor grows in the first turn.** MCP servers that finish connecting
after the first call add their tool names and instructions: by the first
compaction the deferred list had grown from 2,147 to 4,205 tokens and the MCP
instructions from 462 to 2,081. The first turn itself then added, in S6:

| Call | Context | What was added |
|---|---|---|
| 1 | 65,008 | the floor |
| 2 | 69,516 | the bearings file and `reference/handover.md` (4,516 characters), late MCP lists |
| 3 | 76,138 | the open ledger list and `reconcile.sh --help` (10,560 characters), late MCP lists |
| 4 | 79,358 | sections of `reference/remote.md` and `reference/status-block.md` (3,498 characters) |
| 5 | 82,821 | T3 tool schemas loaded through ToolSearch |
| 6 | 88,419 | one thread read and the schedule list (9,764 characters) |

No reference file is read whole on the first turn. The 14 reference files are
53,499 bytes in all and are read by section. In three older fresh starts (S2, S3, S4)
the first reconcile answer was 4,000 to 20,408 characters, and the call after
it read 2.0k to 8.6k tokens more.

## 2. The floor after a compaction: 64k to 90k

First call after S6's compaction: 80,087 tokens (cache read 29,384, the same
tools and system prompt; cache write 50,701).

| Part | Tokens |
|---|---|
| Tools and system prompt, as in a fresh start | 29,384 |
| Owner's and project's instructions, re-sent | 13,105 |
| SKILL.md, re-injected as an invoked skill | 7,825 |
| Skills listing | 7,566 |
| Restored files (up to the 5 most recently read) | 6,902 |
| Deferred tool names, every server now connected | 4,205 |
| The summary | 3,652 |
| MCP server instructions, every server now connected | 2,081 |
| Agent types listing | 1,938 |
| Environment, model, output style, hook line, date | 1,415 |
| The `/compact` command with its instructions, and the resume message | 779 |
| Git status, attribution | 632 |
| Last assistant text kept, background shell notice | 577 |

That is 15,079 above the fresh floor: restored files 6,902, the summary 3,652,
the larger MCP lists about 3,000, and small items.

The restored files in S6 were a scratch message file, two background task
outputs, the bearings file and `reference/handover.md` (the last two 2,331
tokens together). The resume step's first command then added 9,149 tokens
(17,466 characters of ledger output), so the working floor after a compaction
was about 89k.

**The 12 tool schemas discovered before the compaction are not on the floor.**
The request lists them, but the measured call matches the parts only without
their 6,201 tokens, and the next call ran ToolSearch again.

**Why the range is 64k to 90k** (42 compactions):

| Group | n | First call after, median | Range |
|---|---|---|---|
| SKILL.md not re-injected | 13 | 66,289 | 64,035 to 70,698 |
| SKILL.md re-injected | 29 | 78,185 | 71,641 to 90,279 |
| Re-injected, no file restored | 7 | 73,629 | 71,641 to 78,655 |
| Re-injected, over 12k characters of files restored | 8 | 80,324 | 78,774 to 90,279 |

- **The re-injected skill** is the largest cause: about 7.8k tokens, present in
  every compaction of S2, S3, S5 and S6 and in none of S1 and S4. All six
  sessions loaded the skill by the same slash command; why two of them never
  re-injected it was not found (not the Claude Code version, not a Skill tool
  call, not a resume before the first compaction).
- **Restored files** run from 0 to 32,419 characters (0 to about 14.8k tokens,
  inferred from S6's 0.455 tokens per character). The two highest floors
  (89,140 and 90,279, both 23 Nov) restored over 31k characters.
- **The summary** runs from 7,381 to 15,925 characters (about 3.1k to 6.6k
  tokens, inferred).
- Global instructions shrank from 42,408 to 35,518 characters between 9 and 23
  Nov, about 2.5k tokens.

## 3. What a settings change removes

**Headless, one fixed prompt, no skill loaded:**

| Run | First call |
|---|---|
| This repo, defaults | 50,353 |
| An empty folder, defaults | 51,045 |
| Empty folder, every user plugin off in the folder's settings | 52,010 |
| The same, and no MCP servers (`--strict-mcp-config`) | 46,408 |
| The same, and `Artifact`, `Workflow`, `ListAgents`, `ShareOnboardingGuide` denied, and the global rules excluded | 21,771 |

**A scratch T3 thread in this project** (a throwaway worktree with a
`.claude/settings.local.json`, same model and harness as the pinned thread):

| Thread | First call |
|---|---|
| The pinned thread, minus its skill (65,008 less 7,668) | 57,340 |
| Probe A: 4 tools denied, global rules excluded, 6 plugins off | 32,815 |
| Probe B: A, and 54 skills off, `Agent` denied, 7 MCP servers denied | 21,272 |

So with the skill loaded, the pinned thread's fresh floor would be about
28.9k instead of 65.0k (inferred: probe B plus the skill's 7,668).

**By lever:**

| Lever | Setting | Removes | Tokens |
|---|---|---|---|
| Deny `Artifact` | `permissions.deny` | its definition and one system line | about 12,330 |
| Exclude the global rules | `claudeMdExcludes` | 17 rules files | 9,103 |
| Turn skills off | `skillOverrides: "off"` | the listing, down to 3 entries; works on built-in and plugin skills too | about 7,100 |
| Deny `Agent` | `permissions.deny` | its definition and the agent types listing | about 3,700 |
| Deny `Workflow`, `ListAgents`, `ShareOnboardingGuide` | `permissions.deny` | their definitions | about 3,265 |
| Deny unused MCP servers | `permissions.deny` with `mcp__<server>` | their tool names and instructions | about 750 at the first call, about 4,300 once all are connected (inferred) |
| Turn plugins off | `enabledPlugins` | one hook line and 3 plugin skills | about 390 |
| A shorter SKILL.md | | 20.6 tokens per line, on every call | 2,060 per 100 lines |
| A different project folder | | project CLAUDE.md 1,564 and git status about 210 | adds 692 net |

- **A different folder does not help by itself.** The empty folder read 692
  tokens more than this repo: it lost the project CLAUDE.md but gained every
  MCP server this repo has switched off (28 names in the per-project
  `disabledMcpServers` list of the user's Claude config).
- **Turning plugins off is worth little.** It removed the plugin hook line and
  three skills; the total did not drop, because more MCP servers had connected
  by that run's first call.
- **The settings work from the folder.** Both T3 probes took them from a
  `.claude/settings.local.json` in the thread's checkout, with no change to
  user settings.
- **Not removed by any probe:** the Chrome integration's instructions in the
  system prompt (1,427; denying the server left them), T3's own text and tools
  (3,001), the owner's global CLAUDE.md (2,438), `AskUserQuestion` (1,767, in
  use), and the names of T3's deferred tools (about 1,466).
- The pinned thread needs the `t3-code` server, the `smart-compact` plugin and
  `PushNotification`; probe B kept all three.

## What it means (inferred)

- About 36k of the 65k fresh floor, and about 39k of the 76k post-compaction
  floor, is removable by settings in the pinned thread's folder, with no
  change to the skill.
- After that, SKILL.md is the largest part left: 7.7k of about 29k, against
  7.7k of 65k today.
- In the sawtooth model of `super-agent-context-per-wake.md` (growth 1.24k per
  call, a call costs 0.1 times its context, a compaction costs twice its cache
  write plus 35k), a 37k post-compaction floor with the 150k compaction point
  costs about 10.4k per call, against 13.6k for the 150k point alone and 16.9k
  today: 23% lower than the 150k design, 39% lower than today.

## Limits

- One session (S6) gives the exact parts; the other five give call totals and
  attachment sizes in characters.
- The headless probes ran the CLI, not T3. Their first requests match the
  pinned thread's part for part, less T3's text, T3's two tools, the Chrome
  instructions and `AskUserQuestion`.
- MCP servers connect over the first few calls, so first-call totals move by
  about 1k between runs.
- About 4 in 10 headless runs stalled before their first request and were
  repeated; a stalled run made no call.
- The model's use of a denied tool or a switched-off skill was not tested;
  the probes only prove the text leaves the request.

## Run it again

```sh
D=docs/research/super-agent-context-floor
python3 $D/req.py <pinned transcript> <timestamp prefix of the request> first-request.json
python3 $D/parts.py first-request.json parts && $D/tokall.sh parts
python3 $D/compact.py S1=<transcript> S2=<transcript> ...
python3 $D/shape.py <probe transcript> <pinned transcript>
$D/probe.sh <label> <folder> [claude flags]
```

`tok.sh` and `probe.sh` expect an empty `empty/` folder beside them.
`fresh-parts.tsv` and `post-compaction-parts.tsv` hold the counts (part,
characters, tokens); `probe-a.settings.local.json` and
`probe-b.settings.local.json` are the two T3 probes' settings.
