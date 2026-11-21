# Research: the owner's agents and models, and what each is good for

Researched 2026-11-21 for wayfinder ticket #1313 (map #1310, pain points 9, 10
and 11): which provider instances the fleet file lists, what each offers today,
how its quota is read, how it runs headless, whether T3 Code can launch it, and
which job kinds it suits.

Each claim carries its basis: **measured** (a probe run on the owner's
workstation on 2026-11-21, command named), **sourced** (URL), **inferred** or
**guess**. Account details are left out of every probe output. Benchmark names
and scores are quoted from the pages cited; none was re-run here.

## 1. Answer: draft table of job kind to agent and model

| Job kind | Preferred | Fallback | Second-vendor view |
| --- | --- | --- | --- |
| Code (a supervised ship thread) | Claude Code: Sonnet 5.5 medium for XS and S, Opus 5.5 medium for M, Opus 5.5 high for L and XL (today's ladder) | Codex `gpt-6.2-sol` at medium; `gpt-6.2-astra` for L and XL | Not worth a second run: see review |
| Research (reading across sources) | Claude Code: Fable 5.2 at medium | Codex `gpt-6.2-astra` | Grok `grok-4.7` when X or live web is the source |
| Review (a PR, second opinion) | Codex review on `gpt-6.2-sol` while its weekly bucket is healthy | Claude Code review on Opus 5.5 | Only one cross-vendor reviewer per PR |
| Bounded text (draft, summary, triage reading) | agy on Gemini 3.8 Flash, when signed in | Codex `gpt-6-luna` at low, then Claude Haiku 5.5 | none |
| Design critique | Claude Code: Opus 5.5 at high | Codex `gpt-6.2-astra` (or `gpt-6.1-terra` when the input is a screenshot) | Cursor on `gemini-4-neon`, quota unread |

Evidence per cell is in the evidence page linked from section 6. Three things
the table rests on:

- Only Claude and Codex have a working quota read today, so only they can be a
  preferred or fallback pick under a quota rule. **measured** (section 3).
- The top models are close on code. An independent long-horizon benchmark warns
  that models two or three points apart "are, for all practical purposes, in the
  same neighborhood". **sourced**
  <https://akitaonrails.com/en/2026/10/28/llm-benchmark-v4-gemini-4-argon-gpt-6-1-sol-terra-kimi-k3-1-pro-claude-sonnet-5-5/>
  So quota headroom, not a leaderboard rank, should break ties. **inferred**.
- No public evaluation found measures design critique or research reading as
  such; those two rows transfer from building and agentic-search benchmarks.
  **inferred**.

## 2. What is installed, and which models each offers

Versions are **measured** with each CLI's `--version`; model lists with the
command named in the row.

| Instance (fleet key) | CLI and version | Models offered today | How the list was read |
| --- | --- | --- | --- |
| Claude (`claudeAgent`) | `claude` 2.1.329 | Opus 5.5, Sonnet 5.5, Fable 5.2, Haiku 5.5, plus 10 older ones T3 omits | T3 `orchestrator_capabilities` |
| Codex (`codex`) | `codex-cli` 0.170.0 | `gpt-6.2-sol` (default), `gpt-6.2-astra`, `gpt-6.1-terra`, `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` | `model/list` over `codex app-server` |
| Pi (`pi`) | `pi` 1.5.2 with the `pi-antigravity` extension | `antigravity/claude-opus-4-6`, `antigravity/claude-sonnet-4-6`, `antigravity/gemini-3.8-flash`, `antigravity/gemini-4-argon-disabled`, `antigravity/gpt-oss-120b` | `pi --list-models --offline`, `pi list` |
| agy (`agy`) | `agy` 1.5.12 (the Antigravity CLI) | not readable: `agy models` answered "Please sign in to view available models" | `agy models` |
| Antigravity (`antigravity`) | no `antigravity` binary on PATH; T3 bundles its own ACP tool | T3 lists Gemini 3.8 Flash, Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B | T3 `orchestrator_capabilities` |
| Grok (`grok`) | `grok` 1.0.89 | `grok-4.7` (default), `grok-4.7-build-fast`, `grok-4.6`, `grok-4.5` | `grok models` |
| Cursor (`cursor`) | none: `cursor-agent` and `cursor` are not on PATH, and `agent` on PATH is the Grok binary (`agent --version` prints `grok 1.0.89`) | T3 lists Auto, Grok 4.7, Grok 4.6, Composer 2.5, Claude Opus 5.5, Opus 5, Opus 4.8, Gemini 4 Neon, plus 41 it omits | T3 `orchestrator_capabilities` |

Notes:

- Pi's Claude models are the 4.6 generation, two releases behind Claude Code's
  5.5. On the independent benchmark above Claude Opus 4.6 scores 87.5 and Sonnet
  4.6 85.75, against 100.0 for Opus 5.5. **sourced** (same URL). The fleet
  file's Pi `models` map (`sonnet` and `opus` on the 4.6 ids) matches what Pi
  lists. **measured** (`jq .providers.pi ~/.config/super-agent/fleet.json`).
- Gemini 4 Argon shows in Pi's catalogue under an id ending `-disabled`, and is
  absent from T3's Antigravity list. Whether the owner's plan can run it is
  unknown. **measured** for the listing, **guess** for the cause.
- The fleet file's Claude `models` map (`sonnet` to `claude-sonnet-5-5`, `opus`
  to `claude-opus-5-5`) matches T3's list. Fable 5.2 and Haiku 5.5 are offered
  and have no place in the map or in the tier ladder. **measured**.

## 3. Quota: what is read today

The skill's own read was run once:
`skills/super-agent/scripts/quota.sh --fleet <fleet file>`. **measured**.

| Instance | `quota_command` in the fleet file | Result today |
| --- | --- | --- |
| `claudeAgent` | `claude -p "/usage" --output-format json` | `available`: `session` 5h 0.83, `week` 0.64, `week-fable` 0.94 remaining |
| `codex` | three JSON-RPC lines piped to `codex app-server`, the last `account/rateLimits/read` | `available`: `session` 5h 1.0, `week` 0.64 remaining |
| `agy` | `agy -p /usage --output-format json` | `unknown`: "quota command exited 124" |
| `pi` | the same agy command | `unknown`: "quota command exited 124" |
| `cursor` | none | `unknown`: "no quota command in the fleet file" |
| `grok` | none | `unknown`: "no quota command in the fleet file" |
| `antigravity` | none | `unknown`: "no quota command in the fleet file" |

### Shape of each answer

**Claude.** The JSON holds `result` (the `/usage` text), `num_turns: 0` and
`total_cost_usd: 0`, so the read spends no model turn. **measured**. The text
`quota.sh` parses:

```text
Current session: 11% used · resets Nov 21, 3:10pm (<zone>)
Current week (all models): 35% used · resets Nov 25, 12pm (<zone>)
Current week (Fable): 4% used · resets Nov 25, 12pm (<zone>)
```

Fable has its own weekly bucket, nearly untouched. `claude auth status` prints
JSON with `loggedIn`, `authMethod`, `subscriptionType` and `loginExpiresAt`, and
is the only `auth_command` the fleet file holds. **measured**.

**Codex.** The reply to request 2, account keys removed. **measured**:

```json
{"rateLimits": {"limitId": "codex",
  "primary":   {"usedPercent": 0,  "windowDurationMins": 300,   "resetsAt": 1795270430},
  "secondary": {"usedPercent": 36, "windowDurationMins": 10080, "resetsAt": 1795452246},
  "credits": {"hasCredits": false, "unlimited": false, "balance": null},
  "planType": "team", "rateLimitReachedType": null},
 "rateLimitResetCredits": {"availableCount": 1, "credits": [
   {"resetType": "codexRateLimits", "status": "available", "title": "Full reset (Weekly + 5 hr)"}]}}
```

Two things the reader drops today that pain point 10 needs: there is one
`codex` limit, with no separate code-review bucket in the answer, so a review
spends the same weekly bucket as any Codex run; and the account holds one unused
rate-limit reset credit, which `quota.sh` does not surface. **measured**.
`codex login status` printed "Logged in using ChatGPT" and would serve as the
missing `auth_command`. **measured**.

**agy and Pi.** The read failed from this session. stdout was
`{"status":"ERROR","error":"authentication failed or timed out",...}` and stderr
asked for a Google sign-in in the browser; `timeout` then ended it with 124.
**measured** (`agy -p /usage --output-format json`). The cause is not settled:
agy may be signed out, or its stored sign-in may be unreachable from this
session's sandboxed shell. **guess**. Either way the fleet file's `status:
"available"` for `agy` and `pi` is stale. When the read works, `parse_agy` in
`quota.sh` expects `.command.data.groups[]`, each with a `name` and `buckets[]`
of `{id, window, remaining_fraction, reset_time}`. **measured** (read of the
script). The vendor page says the panel shows "remaining quota for each model
group, such as Gemini models ... and Claude and GPT models" and that "the models
in a group share a weekly limit and a five-hour limit". **sourced**
<https://www.antigravity.google/docs/cli/commands/usage> That page describes an
interactive panel only and does not document the print-mode JSON the skill
relies on. **sourced**.

## 4. Instances that lack a quota reader, and what one would take

| Instance | Why it cannot be read today | What a reader would take |
| --- | --- | --- |
| `grok` | `grok usage` and `grok usage --json` both exit 1 with "`grok usage` can't show your plan's usage here yet. Run /usage inside grok instead." **measured**. Headless `grok -p "/usage"` is not a slash command: it ran one model turn (31,615 tokens, $0.05) and answered as a prompt. **measured**. | The subcommand and its `--json` flag already exist, so the cheapest reader is a setup probe that retries `grok usage --json` after each Grok update and records the command once it answers. **inferred**. Until then the only read is the `/usage` panel in the TUI, which means driving a terminal pane and scraping it. **inferred**. xAI's headless page documents no usage read. **sourced** <https://docs.x.ai/build/cli/headless-scripting> |
| `cursor` | No Cursor CLI is installed on this machine, and the binary named `agent` is Grok's. **measured** (`which`, `agent --version`). Cursor documents no CLI usage command. **sourced** <https://cursor.com/docs/cli/headless> | Cursor bills in dollars per billing cycle, not in 5 hour and weekly windows. Its Admin API has `POST /teams/spend`, returning per member `spendCents`, `overallSpendCents` and `effectivePerUserLimitDollars`. **sourced** <https://cursor.com/docs/account/teams/admin-api> The API overview lists the Admin API as available to Enterprise teams. **sourced** <https://cursor.com/docs/api> So a reader needs a team admin API key the owner may not have, plus a new bucket kind (spend against a limit) in `quota.sh` and `route.sh`. **inferred**. T3 keeps a Cursor usage cache keyed by an API key whose `records` list is empty. **measured** (shape of T3's cache file, strings removed). Whether T3 can read usage the owner could reuse is an open question. **guess**. |
| `antigravity` | No command in the fleet file. T3 also cannot launch it (section 5). | It is the same Google account as agy, and the vendor's `/usage` covers the Gemini group and the Claude and GPT group. **sourced** (Antigravity URL above). The reader is the agy command and parser the skill already has; the entry needs only `quota_command` set. **inferred**. |
| `agy`, `pi` | A command exists but failed today (section 3). | A sign-in, and an `auth_command` so a signed-out agy reads as `auth: failed` and not as an unexplained timeout. No candidate was confirmed: `pi auth check --provider antigravity --json` answered `not_ready`, `provider_not_found`, because the provider comes from an extension. **measured**. |

Only `claudeAgent` has an `auth_command`. `codex login status` (above) and a
grep of `grok models` (which printed "You are logged in with grok.com",
**measured**) would fill two of the gaps.

## 5. Headless runs and T3 launch

Headless flags are **measured** from each CLI's `--help`. Only the Grok row was
executed with a prompt (the one accidental turn in section 4); the Claude row
ran as the quota read.

| Instance | One bounded headless job | T3 can launch a thread? |
| --- | --- | --- |
| Claude | `claude -p "<task>" --output-format json --model <id> --effort <level>`, with `--max-budget-usd` and `--permission-mode` to bound it | Yes: `canRunChildTask` true, no constraints |
| Codex | `codex exec -m <model> -s <sandbox> --json -o <file> "<task>"`; `codex review` and `codex exec review` run a review non-interactively | Yes |
| Pi | `pi -p --model antigravity/<id> --thinking <level> --mode json --no-session "<task>"` | Yes |
| agy | `agy -p "<task>" --model <name> --output-format json --print-timeout <d>`; the skill wraps it in `agy-job.sh` with an allow list and a scratch worktree | No T3 provider of this name: it is a CLI job runner only |
| Antigravity | through agy, as above | No: "Antigravity 1.4.1 no longer works with this T3 Code release. Update it in Antigravity setup." |
| Grok | `grok -p "<task>" -m <model> --output-format json --max-turns <n>`; `--permission-mode` and `--sandbox` bound it | Yes |
| Cursor | Vendor docs: `agent -p --output-format json "<task>"`, `--force` to run every action, `CURSOR_API_KEY` for scripts. **sourced** <https://cursor.com/docs/cli/headless> Not runnable here: no Cursor CLI installed | Yes, per T3: `canRunChildTask` true, no constraints |

T3 answers are **measured** with one call to
`mcp__t3-code__orchestrator_capabilities`. That call also lists a second Claude
instance and four other providers (OpenCode, fx, Kiro, Muse Code), all with
"Provider instance is disabled."; none is in the fleet file's `providers`.

T3's Cursor row says it can launch although no Cursor CLI is on this machine.
How T3 reaches Cursor was not established. **guess**: through the API key its
usage cache is keyed by.

## 6. What each is good and bad at, per job kind

The vendor guidance, benchmark numbers and the reading behind each row of the
table are in
[super-agent-agents-and-models-evidence.md](super-agent-agents-and-models-evidence.md).

## 7. What routing does today

Read from `skills/super-agent/scripts/route.sh`, `quota.sh`,
`reference/routing.md` and `reference/agy-jobs.md`. **measured** (file reads).

- `route.sh` has two modes: `--size <XS|S|M|L|XL>` for a supervised thread and
  `--job text` for a bounded text job. There is no research, review or design
  job kind.
- The tier ladder is Sonnet medium, Opus medium, Opus high. XS and S start on
  the first rung, M on the second, L and XL on the third. `--raise` climbs one
  rung per stall or hard finding.
- Launch candidates are the `claude` instances, plus `pi`, `cursor` and `grok`
  instances whose fleet entry sets `route: true`. Cursor and Grok are a last
  resort, picked only when no Claude or allowed Pi instance can launch. The
  owner can name any of them with `--instance`.
- An instance is skipped on failed auth, a weekly bucket at 0 or under the
  weekly reserve (default 0.05), or a Claude 5 hour bucket under the floor
  (default 0.1). The reserve drops to 0 in the last hour of a weekly window.
  The most weekly headroom, times `weekly_weight`, wins.
- A tier above the default asks the owner only when the chosen instance's
  weekly bucket is under 50%. An unknown quota never asks.
- A text job goes to agy on `gemini-3.8-flash-medium`. With `--claude` it stays
  on Claude Code, and overflows to agy's `claude-sonnet-4-6` only when the best
  Claude weekly bucket is under 50% and agy's Claude group is not.
- `quota.sh` reads each provider through its fleet `quota_command`, once per
  wake, and reports an unreadable one as `unknown`, never as an error.

Gaps between that and the table, each **measured** against the script:

1. Codex is never a candidate, for a launch or for a text job, although it is
   one of only two instances with a working quota read and T3 can launch it.
   Its quota is read every wake and then used by nothing in `route.sh`.
2. The ladder has no place for Fable 5.2 or Haiku 5.5, and Claude's
   `week-fable` bucket is read and then ignored: routing ranks on `week` alone.
3. The text route hard-codes two model ids in the script
   (`gemini-3.8-flash-medium`, `claude-sonnet-4-6`). Neither could be checked
   against agy today, since `agy models` needs a sign-in.
4. With agy unreadable, `--job text` still answers `driver: agy`: the text
   route never looks at agy's status or at the Gemini group's bucket.
5. The Codex reset credit and the absence of a separate review bucket are not
   carried into the quota answer, so nothing can budget review spend yet.

## 8. Open questions for the owner

- Is agy signed out on this machine, or was its sign-in only unreachable from
  the sandboxed shell? A plain `agy -p /usage --output-format json` in a
  terminal settles it.
- Does the owner hold a Cursor team admin API key? Without one, Cursor quota
  stays unread and Cursor stays a named, last-resort instance.
- Should Fable 5.2 join the ladder as a top rung for XL and research, given its
  separate and nearly unused weekly bucket?
- Should Codex become a launch and text-job candidate, which the table assumes?
