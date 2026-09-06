# Sibling skill contract on Ship

Resolves [#3](https://github.com/Gharib89/skills/issues/3) (part of #1). Question: what do the
sibling skills assume about Ship, and which of those assumptions must the generic Ship keep
versus which the sibling must give up when Ship becomes one shared skill parameterised by a
ship profile?

Vocabulary is [CONTEXT.md](../../CONTEXT.md): *Ship*, *ship profile*, *axis*, *local gate*,
*generic mechanic*, *sibling skill*, *merge gate*, *small lane*.

## Sources read (all in full unless noted)

| Repo | Path | Role |
|---|---|---|
| crm | `.claude/skills/cloud-ship/{SKILL.md,reference/working-standards.md}` | sibling |
| crm | `.claude/skills/merge-gate/{SKILL.md,scripts/*.sh,reference/*.md}` | sibling |
| crm | `.claude/skills/live-e2e/SKILL.md` | sibling (verification recipe) |
| crm | `docs/agents/{cloud-ship-routine.md,pr-merge-gate.md,triage-labels.md,issue-tracker.md}`, `scripts/cloud-ship-bootstrap.sh`, `CLAUDE.md:107` | routine prompt + repo facts |
| crm | `.claude/skills/ship/{SKILL.md,scripts/*.sh,reference/merge-gate.md,reference/copilot-loop.md,reference/small-lane.md}` | the Ship copy siblings read |
| cc-otel | `.claude/skills/cloud-ship/{SKILL.md,reference/working-standards.md}` | sibling |
| cc-otel | `.claude/skills/powerbi-ship/{SKILL.md,reference/merge-gate.md}` | sibling |
| cc-otel | `.claude/skills/copilot-pr-review-loop/{SKILL.md,references/unattended.md}` | sibling (composed *by* Ship) |
| cc-otel | `docs/agents/cloud-ship-routine.md`, `scripts/cloud-ship-bootstrap.sh`, `CLAUDE.md:15-16,135-147`, `.github/workflows/python.yml:1-30` | routine prompt + repo facts |
| cc-otel | `.claude/skills/ship/{SKILL.md,reference/merge-gate.md,reference/cc-otel.md,reference/small-lane.md}`, `scripts/ship/{_lib,claim,preflight,isolate,reflect,ci-wait}.sh`, `merge.sh:1-40`, `local-gate.sh:1-40` | the Ship copy siblings read |
| global | `~/.agents/skills/agy-ship/SKILL.md` (`~/.claude/skills/agy-ship` does not exist) | sibling |
| global | `~/.gemini/antigravity-cli/skills/ship/SKILL.md` (grep only) | the Ship copy agy runs |

No `.github/workflows/*` file in either repo invokes `cloud-ship` or `ship`. The only CI
coupling is cc-otel `python.yml:18-19`, which path-filters `scripts/ship/**` and runs
`tools/tests/test_ship_lib.py` against `scripts/ship/_lib.sh`. The routine prompt is not a
file in either repo; it is pasted into claude.ai and reproduced verbatim in each repo's
`docs/agents/cloud-ship-routine.md`.

## Verdict legend

- **keep** — the generic Ship must keep this; a sibling relies on it and it is legitimately
  Ship's to own (usually a generic mechanic, or an axis value the ship profile supplies).
- **sibling** — the sibling must change; it hard-codes something that belongs in the ship
  profile, or reaches into Ship's internals.
- **either** — no hard dependency, or the coupling can be resolved on either side; the note
  says which way is cheaper.

## Contract table

### Invocation — skill name and argument shape

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| I1 | Ship is invoked through the Skill tool under the exact name `ship`, with one issue number as its argument. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `cloud-ship/SKILL.md:34` "Run `ship` by **invoking the Skill tool** (skill `ship`)"; `:72` "invoke the `ship` skill on issue $NUM". cc-otel `cloud-ship/SKILL.md:31,78` same wording. | **keep** — name `ship`, `$ARGUMENTS` = issue number (Ship `SKILL.md:76` crm / `:53` cc-otel). |
| I2 | The routine prompt names `cloud-ship`, expects it to be a sibling *inside the repo clone's* `.claude/skills/` alongside `ship`, `tdd`, `code-review`, and refuses to improvise if the Skill tool cannot find it. | routine prompt (both repos) | crm `docs/agents/cloud-ship-routine.md:20-27` "The skill is a sibling in the clone's `.claude/skills/` (alongside `ship`, `tdd`, `code-review`)… If the Skill tool cannot find `cloud-ship`… STOP". cc-otel `:32-40` adds `copilot-pr-review-loop`. | **either — decide in #1.** CONTEXT.md says skills install globally; a cloud sandbox has no global install, only the clone. Either the fire's environment gets a setup step that installs the shared skills, or the shipped-in-repo copy stays for the cloud lane. The prompt is pasted once and "never re-pasted", so whatever is chosen must not change the skill's name. |
| I3 | The sibling knows which skills Ship composes (so a fire can invoke them inline) and lists them by name. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:35-37` "`ship` in turn composes `tdd` and `code-review`… All four ship as sibling skills"; cc-otel `:32-35` adds `copilot-pr-review-loop`. | **sibling** — the composed list differs by repo only because the review-bot topology axis differs. The profile carries that axis; cloud-ship should say "invoke whatever Ship composes" and stop enumerating. |
| I4 | Ship can be handed an already-created branch and told phase 0 is satisfied. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:74-76` "**This branch in the sandbox clone IS `ship`'s phase-0 isolation** — don't create a worktree inside it; treat phase 0 as satisfied (its pre-flight already-in-flight check still applies)"; cc-otel `:80-82` identical. | **keep** — the worktree-layout axis needs an explicit value "in place, branch already exists" (pre-flight still runs, isolate is skipped). Today it is prose the caller overrides; make it a profile/argument value. |
| I5 | The sibling creates the branch itself using Ship's `<type>/<slug>-<issue>` convention, `<type>` = `fix` for a bug else `feat`. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:63-70` "Switch to the repo's semantic convention **before any commit**… `<type>/<slug>-$NUM`… `git switch -c fix/<slug>-$NUM`"; cc-otel `:70-76`. Convention source: crm `ship/scripts/isolate.sh:10` `BRANCH="$TYPE/$SLUG-$N"`; cc-otel `scripts/ship/_lib.sh:24-30` `ship_branch` / `ship_branch_suffix_re`. | **keep** — the `-<issue>` suffix is load-bearing: pre-flight's "remote branch already exists" check greps for it (crm `preflight.sh:32` `git ls-remote --heads origin "*-$N"`; cc-otel `preflight.sh:40`). Both routine docs also depend on it for the "Allow unrestricted branch pushes" permission ("`/ship` pushes `feat/*` branches", crm routine `:87-88`, cc-otel `:72-73`). |
| I6 | agy-ship launches a *different runtime's* `/ship <N>` (Antigravity's vendored copy) and greps its `SKILL.md` for the literal phrase "claim it before" to decide whether the copy is stale; the refresh source is `<crm>/.Codex/skills/ship`. | agy-ship @ global | `agy-ship/SKILL.md:36-38` "Confirm agy's vendored ship skill isn't stale: `grep -i 'claim it before' ~/.gemini/antigravity-cli/skills/ship/SKILL.md` — if absent, `cp -r <crm>/.Codex/skills/ship …`"; `:41` `agy -p "/ship <N>. When your ship skill calls for the 'docs-sync' subagent…"`. | **sibling** — a grep on prose is not a contract, and `/home/gharib/wip/projects/crm/.Codex/skills/ship` does not exist (checked). Staleness should key on a version marker the generic Ship publishes, and the refresh source should be the shared skills repo. |
| I7 | powerbi-ship does **not** invoke Ship; it re-uses Ship's scripted mechanics and "autonomy contract" and forks the rest. | powerbi-ship @ cc-otel | `powerbi-ship/SKILL.md:20-23` "This is `ship`'s sibling for the `desktop-bound` lane, not a wrapper — do not invoke the `ship` skill. It reuses `ship`'s scripted mechanics and autonomy contract but swaps the verification medium". | **either** — the coupling is entirely through S2 below. If the verification-kind axis can express "rendered Desktop pages instead of tests", powerbi-ship collapses into a profile; until then it stays a fork over the generic mechanics. |
| I8 | copilot-pr-review-loop is invoked *by* Ship at phase 7 and detects "unattended" by being told so, then reads `references/unattended.md`. | copilot-pr-review-loop @ cc-otel | `copilot-pr-review-loop/SKILL.md:22-25` "When composed by the `ship` skill (no in-session human), read references/unattended.md"; `unattended.md:1-5` "Read this when the loop is invoked by the `ship` skill (or its cloud routine variant)". Ship side: cc-otel `ship/SKILL.md:252-254` "Invoke the `copilot-pr-review-loop` skill in **unattended mode** (read its `references/unattended.md`)". | **keep** — Ship must pass an explicit unattended signal to any skill it composes; the loop has no other way to know there is no human. |

### Labels — `ready-for-agent`, `agent-working`, `ready-for-human`, `needs-triage`, PR labels

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| L1 | The picker queries `ready-for-agent` and relies on Ship's phase-1 claim to make the claimed issue **disappear from that query** — in crm by removing `ready-for-agent` and adding `agent-working`. | cloud-ship @ crm | `:57-61` "**Do not claim it here** — `ship` claims it in its phase 1 (removes `ready-for-agent`, adds `agent-working`, comments). Because the claim drops `ready-for-agent`, this picker never returns an issue another fire already owns". Mechanic: crm `ship/scripts/claim.sh:20-22` POST `agent-working`, DELETE `ready-for-agent`, POST comment. | **keep** — as the claim-mechanism axis: "claim removes the issue from the frontier query". The label names are profile values (crm `docs/agents/triage-labels.md:12` defines `agent-working`; `CLAUDE.md:107`). |
| L2 | Same invariant, different mechanism: the picker skips issues with an assignee, and Ship's claim **is** the assignee. `ready-for-agent` stays on. | cloud-ship @ cc-otel | `:55` "skipping any with an assignee (assigned = claimed — in flight or awaiting merge)"; `:159` MCP mapping "`gh issue edit <n> --add-assignee @me` — the phase-1 claim → `issue_write method=update assignees=["Gharib89"]`". Mechanic: `scripts/ship/claim.sh:20` `gh issue edit "$n" --add-assignee @me`; `CLAUDE.md:16` "**Claim first**: `gh issue edit <n> --add-assignee @me`". | **keep** — same axis, value = assignee. The generic claim mechanic must support both label-swap and assignee. |
| L3 | Pre-flight treats an existing claim as "not actionable" (crm), or merely reports assignees without blocking (cc-otel). | Ship (read by cloud-ship "its pre-flight already-in-flight check still applies", crm `:75-76`) | crm `ship/scripts/preflight.sh:19-20` `select(.name == "agent-working")` → "already claimed (agent-working)"; cc-otel `scripts/ship/preflight.sh:23,46` returns `assignees` and "open, no PR, no branch". | **keep** — and unify: pre-flight should consult the profile's claim axis and block on an existing claim in both repos. cc-otel's silence is a gap, not a design. |
| L4 | The claim is **idempotent**: an already-claimed issue is a no-op success. Siblings pre-claim on that basis. | agy-ship @ global (pre-claims), cloud-ship @ crm (relies on it) | `agy-ship/SKILL.md:36` "Claim it yourself: add `agent-working`, remove `ready-for-agent`, comment" before launching agy's `/ship`; crm `ship/scripts/claim.sh:2-4` "Idempotent — an existing agent-working label is a no-op success", `:14-16`; cc-otel `claim.sh:3` "Idempotent both ways". | **keep** — idempotent claim and release. |
| L5 | The claim **persists through the merge gate**; a merge-ready issue stays claimed with its open PR so later fires skip it, and only the human's squash-merge (`Closes #N`) clears it. | cloud-ship @ crm, cloud-ship @ cc-otel, routine docs | crm `:112-113` "**Leave the issue `agent-working`** — it carries the open PR, so later fires skip it until the merge closes it"; cc-otel `:122-123` "**Leave the issue assigned**"; crm routine `:110-112`; cc-otel routine `:88-90`. | **keep** — Ship must never release the claim at the merge gate, only on `--release` (blocked) or after merge. |
| L6 | The blocked hand-off is the sibling's, not Ship's: it removes the claim (`agent-working` in crm; assignee in cc-otel) and `ready-for-agent`, adds `ready-for-human`, comments a one-line reason, and must never return the issue to `ready-for-agent` (infinite loop). | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:87-101` "do not leave it `agent-working` and do not return it to `ready-for-agent` (that loops it forever)… labels = LABELS, with "agent-working" and "ready-for-agent" removed and "ready-for-human" added"; crm routine `:106-108` "The one relabel the routine owns is the **blocked** hand-off… since not-shippable is a routine policy, not a `/ship` step". cc-otel `:100-114` adds `assignees = []`. | **either → recommend keep.** cc-otel's Ship already has the release half (`claim.sh --release`, `ship/SKILL.md:162-163`, `reference/cc-otel.md:49-51`); crm's Ship has only prose ("hand the issue back", `SKILL.md:166`). Make "release + hand to human" a generic mechanic driven by the profile's label names; the sibling keeps only the *policy* (what counts as blocked) and, in a fire, the MCP transport. |
| L7 | `ready-for-agent` must be present for agy-ship to proceed. | agy-ship @ global | `:33-34` "Require `ready-for-agent` and a concrete spec". | **either** — same triage-role vocabulary as Ship's pre-flight; fine as long as the label string comes from `docs/agents/triage-labels.md`. |
| L8 | `needs-triage` is the label Ship applies when it files an adjacent-bug issue mid-run, and the merge gate later expects those filings to be listed on the PR. | Ship (crm `SKILL.md:176-178` "file a `needs-triage` issue for it and move on"; cc-otel `:181-185` fix-first ladder → "`needs-triage` issue"), read by merge-gate @ crm | `merge-gate/SKILL.md:161-162` "**Filed during this PR** — issues the author agent's notes or the PR body say it filed". | **keep** — Ship must record every issue it filed in the PR body or merge summary (see M3). |
| L9 | `desktop-bound` issues are excluded from the cloud picker and routed to powerbi-ship. | cloud-ship @ cc-otel, powerbi-ship @ cc-otel | cc-otel `cloud-ship/SKILL.md:56-58` "**and any carrying the `desktop-bound` label** — those… ship locally via the `powerbi-ship` skill"; `powerbi-ship/SKILL.md:4` "(`desktop-bound` label…)"; `CLAUDE.md:141-142`. | **sibling** — a repo-specific exclusion; belongs in the profile's frontier/picker section, not in the skill body. |
| L10 | `gate-passed` / `gate-failed` are PR labels set only by merge-gate after Ship's pipeline ends; Ship never reads or writes them. Sweep = open, non-draft PRs carrying neither. | merge-gate @ crm | `merge-gate/scripts/sweep-list.sh:12-13`; `reference/verdict.md:5-15`; `docs/agents/triage-labels.md:13-14,18` "set only by the `merge-gate` skill after `/ship`'s pipeline ends". | **either** — no Ship dependency beyond "Ship must not touch PR labels" and must open non-draft PRs (X6). |

### Comments posted — who writes what on the issue and the PR, and who reads it

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| C1 | Ship posts a **claim comment** on the issue at phase 1. | cloud-ship @ crm (states it), Ship @ crm (does it) | crm `cloud-ship/SKILL.md:59-60` "(removes `ready-for-agent`, adds `agent-working`, comments)"; `ship/scripts/claim.sh:9` default body "🤖 Claimed by a ship run — implementation in progress." cc-otel `claim.sh` posts **no** comment. | **either** — nothing reads it (no script greps it; merge-gate reads PR comments, not issue comments). Keep as a courtesy under the claim axis; not load-bearing. |
| C2 | Ship **reflects the PR on the issue** right after opening, as a comment, "so a scheduled run won't re-pick it". | Ship (both), routine docs | cc-otel `scripts/ship/reflect.sh:15` `gh issue comment "$n" --body "PR: $url"`; crm `ship/SKILL.md:238-240` prose only; crm routine `:104-105` "`/ship` claims the issue itself (phase 1) and comments the PR link (phase 6)". | **either** — the stated purpose is false: neither picker reads comments (L1/L2 use label/assignee). Humans read it. Keep as a generic mechanic (`reflect`) but stop claiming it prevents re-picks. |
| C3 | The PR body carries `Closes #<issue>`; the squash-merge auto-close is how the issue leaves the queue, and the gate extracts linked issues from that keyword. | cloud-ship (both), merge-gate @ crm, Ship merge mechanics (both) | crm `cloud-ship/SKILL.md:80-81` "Put **`Closes #$NUM`** in the PR body so the squash-merge auto-closes the issue"; cc-otel `:93-94`; `merge-gate/scripts/gate-preflight.sh:51` `linked_issues: [$pr.body // "" \| scan("(?i)closes #([0-9]+)")]`; crm `merge-and-verify.sh:34-43` and cc-otel `merge.sh:8` verify "issue_closed" and close manually if the keyword didn't fire. | **keep** — `Closes #<issue>` in the PR body is contract. |
| C4 | In an unattended run the **merge summary is discoverable on the PR** — merge-gate reads "the author agent's merge summary and its per-reviewer dispositions" from the PR comments. | merge-gate @ crm | `merge-gate/SKILL.md:52-54` "Read the PR comments yourself: the author agent's merge summary and its per-reviewer dispositions (Copilot and CodeRabbit), plus the linked issue + brief". Ship side only says "Post this summary, then stop" (crm `reference/merge-gate.md:7`) — i.e. in chat; cloud-ship `:109-110` "post the PR link + a per-reviewer disposition summary and END the fire" does not say where. | **keep — and close the gap.** Generic Ship's unattended mode must post the merge summary as a PR comment (the only place a later human or gate can read it). Today this works only by accident of the fire's transcript. |
| C5 | Ship (or the loop it composes) posts a **per-round PR comment** with the disposition log, and the same log lands verbatim in the merge summary. | copilot-pr-review-loop @ cc-otel | `copilot-pr-review-loop/SKILL.md:123-128` "Post a single PR comment summarizing what was addressed in this round… `gh pr comment <PR> --body "Addressed Copilot findings in <sha>:…`"; `references/unattended.md:19-21` "The log lands verbatim in the round's PR summary comment and in ship's merge-gate summary — a human reads it there, after the fact". | **keep** — the merge summary needs a disposition block that composed skills can write into (M1). |
| C6 | Ship **replies on every iterating-reviewer (CodeRabbit) thread** and bulk-resolves with `@coderabbitai resolve` only once all threads are dispositioned; the gate detects the threads Ship left undispositioned as "unresolved + no non-CodeRabbit reply". | merge-gate @ crm | `merge-gate/scripts/gate-preflight.sh:36-40` `select(.isResolved \| not) \| select(.comments.nodes[0].author.login == "coderabbitai") \| select([.comments.nodes[1:][] \| .author.login] \| any(. != "coderabbitai") \| not)`; `SKILL.md:47-49,54-55` "the CodeRabbit threads left with **no disposition**… a gap the author agent left". Ship side: crm `reference/copilot-loop.md:37-40` "reply **on each review thread**… use its documented thread-resolution mechanism only once **every** thread carries a disposition". | **keep** — as the review-bot topology axis: an iterating reviewer's threads get an on-thread reply per finding before resolution. |
| C7 | Copilot is **round-1-only** in Ship's flow — never re-requested — so the gate's single re-request is still unspent when it arrives. | merge-gate @ crm | `merge-gate/scripts/rerequest-copilot.sh:15-19` refuses when `COUNT -ge 2` "the one gate re-request was already spent"; `SKILL.md:129-133`; crm `ship/reference/copilot-loop.md:10-12,28-31` "**Never re-requested in the ship flow**… (The lone exception… lives in the `merge-gate` skill, not here.)". | **keep in crm's profile** — but note the cross-repo conflict: cc-otel's Ship *does* re-request Copilot (up to 2 rounds via copilot-pr-review-loop, `unattended.md:25`). If merge-gate is ever generalised, its "one re-request" guard must read the round count from the profile, not assume 1. |
| C8 | Every comment the gate posts is prefixed `> *This was generated by AI during merge-gate review.*`; the verdict comment follows a fixed template. | merge-gate @ crm | `merge-gate/SKILL.md:36-40`; `reference/verdict.md:17-53`. | **either** — the gate's own output; Ship never reads it. |

### Script paths, names, argument shapes, JSON contract

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| S1 | The sibling knows Ship's script set and **which scripts hit the GitHub API** (dead in a fire) versus which are local-only (still run). It names them. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:126-131` "`scripts/preflight.sh`, `claim.sh`, `poll-pr.sh`, and `merge-and-verify.sh` all run `gh`… `scripts/local-gate.sh` is the phase-5 gate in a fire too (`isolate.sh` is moot)"; cc-otel `:147-148` "**including the `scripts/ship/*.sh` helpers that wrap `gh`** (preflight, claim, reflect, ci-wait, merge; only `local-gate.sh` works in a fire)". | **sibling** for the enumeration (names differ per repo: `poll-pr`/`merge-and-verify` vs `ci-wait`/`reflect`/`merge`; locations differ: skill-dir `scripts/` vs repo `scripts/ship/`). **keep** for the invariant: the local gate never calls the tracker API, and every other generic mechanic is a thin tracker call that a caller can substitute (X4). |
| S2 | powerbi-ship calls Ship's generic mechanics **by path and argument shape** and acts on their JSON: `scripts/ship/preflight.sh <issue>` → `"actionable": false`; `isolate.sh <issue> <type> <slug>` → sibling worktree + env files copied; `claim.sh <issue> [--release]`; `local-gate.sh`; `reflect.sh <issue> <pr-url>`; `ci-wait.sh <pr>` → `"conflict"` / `"checks-failed"`; `merge.sh <pr> <issue> --worktree <path>` → any `false` step finished by hand. | powerbi-ship @ cc-otel | `powerbi-ship/SKILL.md:62-74` "Same contract as `ship`: JSON verdict on stdout, act on it." + table; `:105-107` "`preflight.sh` — on `"actionable": false` stop and report. `isolate.sh <issue> <type> <slug>` creates the sibling worktree and copies env files"; `:123`; `:166`; `:168-169` "On `"conflict"`… On `"checks-failed"`"; `reference/merge-gate.md:85-88` "run `scripts/ship/merge.sh <pr> <issue> --worktree <path>` from the main checkout and finish any `false` step in its JSON by hand". Script side: `scripts/ship/preflight.sh:8-9`, `isolate.sh:5-6`, `claim.sh:5-6`, `reflect.sh:5-6`, `ci-wait.sh:6-8`, `merge.sh:8-10`. | **keep** — these six names, argument shapes, and JSON keys are the generic-mechanic contract. This is the cleanest dependency in the set; make it the published interface. |
| S3 | **Argument order of `isolate` differs between the two Ship copies.** | Ship @ crm vs Ship @ cc-otel; powerbi-ship depends on the cc-otel order | crm `ship/SKILL.md:41,149` and `scripts/isolate.sh:5` "`isolate.sh <type> <slug> <issue>`"; cc-otel `ship/SKILL.md:97` and `scripts/ship/isolate.sh:8` "`isolate.sh <issue> <type> <slug>`"; `powerbi-ship/SKILL.md:69` uses `<issue> <type> <slug>`. | **keep one** — pick `<issue> <type> <slug>` (issue-first matches every other mechanic: `preflight <issue>`, `claim <issue>`, `reflect <issue> <pr-url>`); crm's copy is the odd one out. |
| S4 | merge-gate runs Ship's local gate **from Ship's skill directory** before every push. | merge-gate @ crm | `merge-gate/SKILL.md:106-108` "the `ship` skill's `scripts/local-gate.sh` (sibling skill dir) runs the full CI-mirrored set and prints only the failing lines". | **sibling** — per CONTEXT.md the local gate is repo-owned ("The only Ship mechanic whose body is the repo itself"). merge-gate should call the path the ship profile's local-gate axis names, not `.claude/skills/ship/scripts/local-gate.sh`. |
| S5 | The local gate accepts `--small <node>`; cc-otel's also accepts `--all`, `--no-docker`, `--base <ref>` and emits gate statuses `pass \| fail \| deferred-to-ci \| unavailable`. cloud-ship passes `--no-docker` when `DOCKER=absent`. | cloud-ship @ cc-otel, Ship small lane (both) | cc-otel `cloud-ship/SKILL.md:83-87` "`scripts/ship/local-gate.sh` — plain when `DOCKER=present`; `--no-docker` when `absent`, which marks the Docker-requiring gates… `deferred-to-ci`"; `scripts/ship/local-gate.sh:10-23`; crm `ship/scripts/local-gate.sh:5-7`; both `reference/small-lane.md` (`--small`). | **keep** the *flags* as the local-gate axis's interface (`--small <node>` is the small-lane floor; `--no-docker` is a verification-kind switch); the *body* is the repo's. |
| S6 | Ship's scripts print a one-screen JSON verdict on stdout, failing log tail on stderr, exit `0 ok / 1 real failure / 2 tooling`, and share `_lib.sh` (env-file inventory, branch convention, JSON emit, secrets regexes). | Ship @ cc-otel; relied on by powerbi-ship (S2) and by CI (`python.yml:18-19` path filter `scripts/ship/**` "covered by tools/tests/test_ship_lib.py (#230)"). | cc-otel `ship/SKILL.md:86-92`; `scripts/ship/_lib.sh:2-16`. crm's copy has no `_lib.sh` and its exit codes vary (`poll-pr.sh:16` exits 3 on timeout). | **keep** the cc-otel contract (JSON stdout, stderr tail, 0/1/2). Flag: if the generic mechanics leave the repo, `test_ship_lib.py` and the `python.yml` path filter go with them or are dropped. |
| S7 | The bootstrap the fire runs first is the repo's own `scripts/cloud-ship-bootstrap.sh`, and its output feeds Ship's gate flags (`DOCKER=present\|absent`). | cloud-ship @ cc-otel, cloud-ship @ crm | cc-otel `:39-43`; `scripts/cloud-ship-bootstrap.sh:4-8` "The DOCKER= line is consumed by the cloud-ship skill"; crm `:41-44` (crm CLI install + `agent-cloud` profile + WhoAmI). | **sibling** — a repo fact; the profile should name the bootstrap and what it emits. |
| S8 | agy-ship needs no Ship scripts but hard-codes the crm CI gate set (pytest, pyright, mkdocs `--strict`, GitGuardian), the live profile `agent-cloud`, and the docs-sync targets (`docs/how-to/`, `crm/skills/reference/`). | agy-ship @ global | `agy-ship/SKILL.md:20-21` "CI gates that must be green before merge: pytest, pyright, mkdocs `--strict`, GitGuardian"; `:60-63`. | **sibling** — every one of these is a ship-profile fact (local gate, verification, docs-sync). agy-ship should read crm's profile. |

### Worktree location

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| W1 | Ship's isolate creates a **sibling** worktree at `<parent>/<repo>-<issue>` and copies gitignored env files in; merge copies them back out and removes the worktree via `--worktree <path>`. powerbi-ship writes into that worktree (`<worktree>\powerbi\…\.pbi\cache.abf`) and opens Desktop on it. | powerbi-ship @ cc-otel | `scripts/ship/isolate.sh:22` `wt="$(dirname "$root")/$(basename "$root")-$n"`; `_lib.sh:18-21` `SHIP_ENV_FILES=(.env .env.prod)`; `powerbi-ship/SKILL.md:106-117`, `:174-175` "launch Desktop on the **worktree's** `.pbip`", `:182`; `reference/merge-gate.md:85-88`. | **keep** the *interface*: isolate prints the worktree path (crm `isolate.sh:27` `echo "$WT"`; cc-otel emits `{"worktree": …}`), merge takes `--worktree <path>`. The *location* is the worktree-layout axis: crm uses `$ROOT/.claude/worktrees/<slug>-<issue>` (crm `isolate.sh:24`), cc-otel a sibling directory. powerbi-ship must read the path from isolate's output, not assume the layout (it already does). |
| W2 | crm's Ship prefers the `EnterWorktree` tool and falls back to `isolate.sh`; cc-otel's always runs `isolate.sh`. | Ship @ crm vs cc-otel | crm `ship/SKILL.md:148-150` "`EnterWorktree`, or `scripts/isolate.sh <type> <slug> <issue>` when that tool is absent"; cc-otel `:146` always the script. | **keep one** — the script path is the only one a sibling can observe (W1); `EnterWorktree` yields no env-file copy and no printed path. Prefer the script. |
| W3 | merge-gate uses its **own** fresh worktree for the PR branch and never the shared checkout; independent of where Ship's worktree was. | merge-gate @ crm | `merge-gate/SKILL.md:61-64` "check it out in a **fresh worktree** (`git fetch origin <branch>` + `git worktree add`); never in the shared checkout". | **either** — no dependency. |
| W4 | agy-ship tracks and later edits/removes "agy's worktree" and must be able to find it. | agy-ship @ global | `:50-51` "Track via… the git worktree + branch"; `:66-67` "edit + commit + push in agy's worktree directly"; `:75-76` "Remove the worktree (`git worktree remove <path> --force`)"; tripwire `:83-85`. | **either** — satisfied by W1's printed path plus the `-<issue>` branch suffix (I5). |
| W5 | In a cloud fire there is **no worktree at all** — the clone's branch is the isolation. | cloud-ship (both) | crm `:74-76`, cc-otel `:80-82` (quoted at I4). | **keep** — see I4. |

### Merge-gate summary shape

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| M1 | The summary has a **per-reviewer disposition block** (one block per reviewer, per-finding `→ fixed \| declined: evidence` lines), and composed skills write their log into it. | cloud-ship @ crm ("per-reviewer disposition summary", `:109-110`), cloud-ship @ cc-otel ("the disposition summary", `:119-120`), copilot-pr-review-loop (`unattended.md:19-21,30`), merge-gate @ crm (`SKILL.md:52-54`) | Ship templates: crm `reference/merge-gate.md:31-35` "Automated review (one block per reviewer — lanes need the per-reviewer split) - round-1 reviewer… - iterating reviewer…"; cc-otel `reference/merge-gate.md:37-40` "Automated review (copilot-pr-review-loop, unattended) - rounds run: <n>/2". | **keep** — a stable "Automated review" section whose *rows* come from the profile's review-bot axis (crm: round-1 + iterating; cc-otel: one loop with round count). |
| M2 | The summary states the PR URL, branch → default branch, lane, implementation, **Deviations from plan**, integrated-test targets, self-review dispositions, local-gate line, docs-sync line, CI line, and ends "Ready to merge. Reply "merge"…". | merge-gate @ crm reads it (C4); powerbi-ship forks it | crm `reference/merge-gate.md:9-42`; cc-otel `:15-47`; `powerbi-ship/reference/merge-gate.md:51-81` (`## /powerbi-ship summary`, swaps "Integrated tests" for "Pages verified"/"Model verification", drops "Automated review" for "Self-review" with auto-review folded in). | **keep** the section list; **either** for powerbi-ship — if the verification-kind axis can rename "Integrated tests" to "Pages verified", the fork disappears. |
| M3 | The summary (or PR body) lists **issues filed during the run** so the gate can report "Filed during this PR". | merge-gate @ crm | `merge-gate/SKILL.md:161-162` (quoted at L8). Neither Ship template has an explicit row for this today. | **keep — add the row.** Ship's template needs an "Issues filed" line (or the PR-template section) that the gate can parse. |
| M4 | The summary is written **uncompressed** — session-wide terse/output styles do not apply. | Ship @ cc-otel, powerbi-ship @ cc-otel | cc-otel `ship/reference/merge-gate.md:7-11` "**Write it uncompressed.**…"; `powerbi-ship/reference/merge-gate.md:8-12` identical paragraph. crm's copy lacks it. | **keep** (generic). |
| M5 | The gate's own verdict uses profile-name + version to identify live targets and never pastes org identifiers. | merge-gate @ crm | `reference/verdict.md:55-58`; `live-e2e/SKILL.md:52-54` "**Never embed real-org identifiers**". | **either** — no Ship dependency; but the same rule should bind Ship's summary in a public repo (crm). |

### Exit / stop behaviour

| # | Assumption | Holder | Where (quoted) | Verdict |
|---|---|---|---|---|
| X1 | Ship's merge gate is a **wait for a human** that the composing skill can **override into "post summary and end"** without merging. | cloud-ship @ crm, cloud-ship @ cc-otel | crm `:27-28` "`ship`'s phase-9 merge gate waits for a human "merge" — a human you never reach. The override is step 5"; `:104-113` "**Override it.**… post the PR link + a per-reviewer disposition summary and END the fire. Do not wait, poll, or merge"; cc-otel `:24-25,116-123`. Ship side: crm `reference/merge-gate.md:44` "Then **wait.**"; cc-otel `:49`. | **keep — as an explicit mode, not an override.** Generic Ship needs an unattended flag under which phase 9 = post the summary (as a PR comment, C4) and return; the caller never has to talk Ship out of waiting. Ship never merges in either mode (CONTEXT.md *Merge gate*). |
| X2 | Every Ship stop before the gate — ambiguity rail, red gate after ~2 retries, integrated-test hand-off, mid-run redesign — **returns to the caller with a reason** rather than blocking on a question, so the sibling can map it to the blocked hand-off. | cloud-ship (both), working-standards (both) | crm `:29-30` "A fire that can't finish must not strand the issue. Either `ship` reaches merge-ready (step 5) or you hand it to a human (step 4). Never leave it spinning"; `:87-88` "ambiguous / underspecified, on-prem-only, or CI can't be made green"; `reference/working-standards.md:6-8` "(This is also `ship`'s phase-1 ambiguity rail — in a fire, "report" means the blocked hand-off.)"; cc-otel `:100-102`. Ship's three pauses: crm `ship/SKILL.md:51-62` (the phase-3 hand-off "hand the exact command back and wait" would hang a fire). | **keep** — Ship's stops must be an enumerable set (`ambiguous`, `blocked-verification`, `red-after-retry`, `needs-split`) returned to the caller; "and wait" is only valid when a human is present. |
| X3 | Polling is **bounded and foreground**; reaching the bound is not permission to proceed. | cloud-ship (both) | crm `:165-172` "a short delay between polls, a capped number of attempts; never a detached/background monitor. Reaching the bound is **not** a licence to proceed"; cc-otel `:168-172`; `unattended.md:50-52`. Ship side: crm `poll-pr.sh:16` "done=false (exit 3): the window closed first"; cc-otel `ci-wait.sh:18` `limit=1800`, `:45-46` `timeout` exit 2. | **keep** — CI wait returns a verdict within a bound; never a background monitor. |
| X4 | In a fire, **every GitHub call Ship makes is known and mappable** to an MCP tool, phase by phase: read issue + comments (1), label edit / assignee (1), issue comment (1, 6), `gh pr create` non-draft (6), `gh pr view --json mergeable,mergeStateStatus` (8), `gh pr view --json reviews,statusCheckRollup` (7/8), `@coderabbitai review\|resolve` comments (7, crm), Copilot request (7, cc-otel via `unattended.md:39-46`). The mapping "outranks every literal `gh` command in `ship`, its references, and any repo doc it follows". | cloud-ship @ crm `:133-163`, cloud-ship @ cc-otel `:138-166`, copilot-pr-review-loop `unattended.md:32-46` | crm `:146-148` "**This section outranks every literal `gh` command in `ship`, its references, and any repo doc it follows for the duration of a fire.** The table maps every `gh` command a fire actually reaches". | **sibling — the tightest coupling in the set, and the one most likely to rot.** Generic Ship should name its tracker operations abstractly (read-issue, claim, release, reflect, open-pr, poll-pr, comment-pr, request-review) so the fire maps *operations*, not literal `gh` invocations that change whenever a script is edited. Until then every Ship edit that touches `gh` silently breaks the fire. |
| X5 | Ship **degrades without the task-list tools and without subagents**: it has a markdown-checklist fallback for the phase list, and its delegation rule is optional. | cloud-ship (both) | crm `:117-125` "Go straight to `ship`'s markdown-checklist fallback for the phase list… `ship`'s delegation rule and model-tier table are inert in a fire — run everything inline"; cc-otel `:127-136`. Ship side: `reference/context-discipline.md` (both) names the task list as "required first action" (`ship/SKILL.md:131-134`). | **keep** — Ship must run to completion with neither `TaskCreate` nor `Agent`; the checklist fallback and inline execution are contract, not a quirk. |
| X6 | Ship opens **non-draft** PRs, so the gate's sweep sees them and round-1 review fires. | merge-gate @ crm, Ship (both) | `merge-gate/scripts/sweep-list.sh:12` `select(.draft == false)`; `SKILL.md:50` "Skip drafts"; crm `ship/SKILL.md:227` "Open a **ready** (non-draft) PR"; cloud-ship MCP row "`mcp__github__create_pull_request` (`draft` omitted)" (crm `:160`, cc-otel `:163`). | **keep**. |
| X7 | A PR whose head was pushed in the last 15 minutes may still be Ship's; the gate skips it. | merge-gate @ crm | `merge-gate/scripts/gate-preflight.sh:21-23` `RECENT=$((NOW - PUSHED < 900))`; `SKILL.md:50-51` "(the author agent may still be working)". | **either** — a heuristic; a stronger signal would be the claim state (L5) or a "merge-ready" PR label Ship sets at the gate. Not required. |
| X8 | agy's `/ship` stops are **resumable in the same conversation** (`agy -c -p "<answer>"`), and print mode buffers output until exit. | agy-ship @ global | `:52-54` "If agy stops for input, resume the same conversation… Auto-answer mechanical/documented stops from repo context"; `:49-51`. | **either** — runtime property of Antigravity, not of Ship. |
| X9 | After a human merge the sibling — not Ship — removes the worktree and deletes the remote branch ("squash-merge does not auto-delete here"). | agy-ship @ global | `:75-77`. cc-otel's `merge.sh:3-6` and crm's `merge-and-verify.sh:30-32` already do both. | **sibling** — agy-ship should call Ship's merge mechanic on approval instead of hand-rolling cleanup. |
| X10 | powerbi-ship copies Ship's autonomy contract verbatim (three stops, "Never proceed on red… ~2 attempts") and adds a fourth stop (foreign-Desktop guard). | powerbi-ship @ cc-otel | `powerbi-ship/SKILL.md:34-55` vs cc-otel `ship/SKILL.md:28-49`. | **either** — duplicated prose; resolves itself if powerbi-ship becomes a profile (I7). |

## How the two `cloud-ship` copies differ

`reference/working-standards.md` is byte-identical in both repos (`diff` clean). The
`SKILL.md` files share structure and most prose; every difference below is a repo fact
that belongs in the ship profile.

### Selection rule (the picker)

| | crm (`cloud-ship/SKILL.md`) | cc-otel (`cloud-ship/SKILL.md`) |
|---|---|---|
| Query | `:50-53` `list_issues labels=["ready-for-agent"] state=OPEN orderBy=CREATED_AT direction=ASC perPage=1` — **oldest one**, no walk. | `:52-54` same query without `perPage=1`; `:55-66` **walk ascending**. |
| Skip rules | none — `:60-61` "Because the claim drops `ready-for-agent`, this picker never returns an issue another fire already owns". | `:55-58` skip any with an **assignee**; skip any labelled **`desktop-bound`** (→ `powerbi-ship`). |
| Blocker check | none. | `:59-65` first unassigned candidate must have **no open blocker**: try `issue_read method=get`, then `gh api repos/Gharib89/cc-otel/issues/<n>/dependencies/blocked_by`; blocked → next candidate; **neither surface exposes dependencies → "cannot verify blockers" and STOP**. |
| Pre-pick gate | none. | `:45-47` **PR cap**: `list_pull_requests state=OPEN` ≥ 3 → "PR queue full" and STOP. |
| Empty result | `:57-58` "nothing ready" and STOP. | `:67-68` same. |

### Invocation of Ship

| | crm | cc-otel |
|---|---|---|
| Step numbering | 5 steps (bootstrap, pick, branch+ship, blocked, end). | 6 steps (bootstrap, **PR cap**, pick, branch+ship, blocked, end). |
| Branch | `:63-70` `git switch -c fix/<slug>-$NUM # or feat/<slug>-$NUM`, with `<slug>` defined ("a short kebab summary of the issue title"). | `:70-76` `git switch -c feat/<slug>-$NUM`, `<slug>` undefined. |
| Composed skills the fire must invoke inline | `:35-37` `tdd`, `code-review`. | `:32-35` `tdd`, `code-review`, `copilot-pr-review-loop`. |
| Repo-specific rails while Ship runs | `:77-79` "**Pin `--profile agent-cloud` on every crm command**… An issue that can only be verified on-prem counts as **blocked**". | `:83-92` integration gate by `DOCKER`: `local-gate.sh` plain / `--no-docker`; `deferred-to-ci` → PR CI is the integration gate; **schema-touching issue is blocked**; **no CI configured → blocked for any `code` change**; "The shared dev DB is out of reach by design — the fire has no `DATABASE_URL`". |
| Bootstrap | `:41-44` `scripts/cloud-ship-bootstrap.sh` installs the crm CLI, builds the `agent-cloud` profile from `D365_*`, WhoAmI. | `:39-43` `scripts/cloud-ship-bootstrap.sh` = `uv sync --frozen` + Docker probe, prints `DOCKER=present\|absent`. |

### Claim, hand-off, and end state

| | crm | cc-otel |
|---|---|---|
| Claim (done by Ship) | label swap: −`ready-for-agent` +`agent-working` + comment (`:59-60`; `ship/scripts/claim.sh`). | assignee: `assignees=["Gharib89"]` (`:159`; `scripts/ship/claim.sh:20`). `ready-for-agent` stays. |
| Blocked hand-off (done by cloud-ship) | `:95-101` labels = current − {`agent-working`, `ready-for-agent`} + `ready-for-human`; comment reason. | `:106-113` labels = current − `ready-for-agent` + `ready-for-human`; **`assignees = []`**; comment reason. |
| Blocked causes named | `:87-88` ambiguous/underspecified, on-prem-only, CI can't be made green. | `:100-102` ambiguous/underspecified, needs Docker or CI it doesn't have, CI can't be made green (+ schema-touching, no-CI, cannot-verify-blockers, PR-cap from earlier steps). |
| Merge-ready definition | `:105-109` CI green, **Copilot round-1 threads dispositioned (never re-requested), every CodeRabbit thread dispositioned and resolved (`@coderabbitai resolve`), CodeRabbit quiet on the latest push**, `mergeable`. | `:117-119` CI green, **`copilot-pr-review-loop` converged (quiet, or 2-round cap with every finding dispositioned)**, `mergeable`. |
| What is posted at the end | `:109-110` "the PR link + a **per-reviewer** disposition summary". | `:119-120` "the PR link + the disposition summary". |
| Issue left as | `:112` `agent-working`. | `:122` assigned. |

### `gh` → MCP mapping table

Shared rows (identical text): `gh issue view --comments`, `gh issue list`, `gh issue comment`,
`gh pr create` (`draft` omitted), `gh pr view --json mergeable,mergeStateStatus`,
`gh pr view --json reviews,statusCheckRollup`.

| Only in crm (`:154-163`) | Only in cc-otel (`:155-166`) |
|---|---|
| `gh issue edit --add-label/--remove-label` → `issue_read get_labels` → `issue_write update` full label set. | `gh issue edit --add-assignee @me` → `issue_write update assignees=["Gharib89"]`; `--remove-assignee` / label swaps → full label set + `assignees=[]`. |
| `@coderabbitai review` / `@coderabbitai resolve` → `add_issue_comment` on the PR. | `gh pr list` (PR cap) → `list_pull_requests`. |
| — | Copilot request + polling → delegated to `copilot-pr-review-loop/references/unattended.md`. |
| Scripts declared dead: skill-dir `scripts/preflight.sh`, `claim.sh`, `poll-pr.sh`, `merge-and-verify.sh`; `local-gate.sh` works; `isolate.sh` moot (`:126-131`). | Scripts declared dead: `scripts/ship/{preflight,claim,reflect,ci-wait,merge}.sh`; only `local-gate.sh` works (`:147-148`). One sanctioned `gh api` attempt: the dependencies probe, "expect it to 403 and move on" (`:150-151`). |
| Names the repo docs whose `gh` it overrides: `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` (`:142-143`). | Names `docs/agents/issue-tracker.md` and the `copilot-pr-review-loop` skill (`:145-146`). |

### Metadata and wiring

| | crm | cc-otel |
|---|---|---|
| Frontmatter | `metadata: internal: true` (`:9-10`). | none. |
| `.claude/settings.local.json` `skillOverrides` | `"cloud-ship": "name-only"` (`:26`). | `"cloud-ship": "off"` (`:14`). |
| Routine doc extras | Stale-claim recovery = relabel `ready-for-agent` by hand (`:115-117`); one-time `gh label create agent-working` (`:123-126`); D365 env vars + `CLOUD_SHIP_PYTHON` (`:60-83`). | Activation precondition on CI (#24) (`:10-18`); stale-claim recovery = unassign by hand (`:94-96`); "Deliberately absent: `DATABASE_URL` and all Azure identity vars" (`:64-66`); GitHub Actions minutes budget (`:99-105`). |

## Findings that change the generic design

1. **The fire's `gh`→MCP table is a copy of Ship's internals (X4).** It enumerates every
   `gh` call by phase; any edit to a Ship script or reference that adds or renames a `gh`
   call silently breaks the cloud lane. Generic Ship should expose named tracker
   operations so the profile/caller maps operations, not command lines.
2. **The merge summary has no defined destination in unattended mode (C4/X1).** merge-gate
   reads it from PR comments; Ship's template says "post… then wait" (chat). Define:
   unattended → PR comment, then return.
3. **Two claim mechanisms, one invariant (L1/L2/L6).** Label-swap (crm) vs assignee
   (cc-otel), and only cc-otel's Ship has `--release`. The claim axis needs both values and
   the release half everywhere; the sibling keeps only the *blocked* policy.
4. **`isolate` argument order differs between copies (S3)** — `<type> <slug> <issue>` in crm,
   `<issue> <type> <slug>` in cc-otel; powerbi-ship depends on the latter.
5. **merge-gate and agy-ship reach past the profile (S4, S8, X9).** merge-gate calls the local
   gate out of Ship's skill directory; agy-ship hard-codes crm's CI gate set, live profile,
   and docs-sync targets, and greps Ship prose for staleness against a `.Codex/skills/ship`
   path that does not exist.
6. **Copilot round count is a per-repo axis, not a constant (C7).** crm: round-1 only (so
   merge-gate's single re-request is unspent); cc-otel: up to 2 explicit rounds. A
   generalised merge-gate must read the count from the profile.
7. **Only cc-otel's scripts are tested (S6).** `python.yml` path-filters `scripts/ship/**` to
   `tools/tests/test_ship_lib.py`. Moving generic mechanics into the shared skill moves or
   drops that coverage — decide which.

## Must-keep gist

- Skill name `ship`, argument = one issue number; branch `<type>/<slug>-<issue>` (the
  `-<issue>` suffix drives pre-flight); non-draft PR with `Closes #<issue>` in the body.
- Generic mechanics by name, argument shape, and JSON verdict (stdout JSON, stderr tail,
  exit 0/1/2): `preflight <issue>`, `isolate <issue> <type> <slug>` (prints the worktree
  path), `claim <issue> [--release]` (idempotent; claim persists through the gate),
  `local-gate [--small <node>] [--no-docker]`, `reflect <issue> <pr-url>`, `ci-wait <pr>`
  (bounded, foreground), `merge <pr> <issue> --worktree <path>` (post-approval only).
- Claim axis: label-swap or assignee, either way "claimed issues leave the frontier query"
  and Ship never releases at the merge gate.
- Merge summary: fixed section list with a per-reviewer "Automated review" block, an
  "Issues filed" line, uncompressed; in unattended mode posted as a PR comment and then
  Ship returns — it never waits for, polls for, or performs the merge.
- Every pre-gate stop returns to the caller with an enumerable reason; Ship runs without
  `TaskCreate` and without subagents; the local gate never calls the tracker API.
