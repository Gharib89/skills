# Ship core inventory — the three copies, row by row

Resolves [#2](https://github.com/Gharib89/skills/issues/2) (part of map [#1](https://github.com/Gharib89/skills/issues/1)). Every step, rail, script feature and reference-file section in the three `ship` copies, with its source location per copy and a classification: `core` (same in every repo once the ship profile supplies parameters), `axis:<name>` (one dimension of the ship profile), or `drop` (dead, or owned by a sibling skill / project instructions rather than Ship).

**Sources read in full (2026-09-06):**

| Prefix | Copy | Path | Last touched |
|---|---|---|---|
| crm | `crm/.claude/skills/ship/` | `S` = `SKILL.md`, `R/` = `reference/`, `s/` = `scripts/`, `C` = `crm/CLAUDE.md` | 2026-07-20 (#909) |
| aiworx | `aiworx-excalidraw-plugin/.claude/skills/ship/` | same prefixes; `C` = its `CLAUDE.md` | 2026-09-06 (#224) |
| cc-otel | `cc-otel/.claude/skills/ship/` for `S`/`R/`; **`cc-otel/scripts/ship/` for `s/`**; `C` = its `CLAUDE.md` | 2026-08-22 (#248) |

Cell format is `file:lines`; `absent` means no copy of the item exists in that repo. Verbatim wording is quoted where it carries the argument. Issue numbers in notes (`#218`, `#401`, …) are the *source repo's* issues, taken from `git log -S` on the rail, so "learned from a defect" is traceable.

---

## Axes found

The eight axes CONTEXT.md already names, confirmed by the copies, plus five the copies disagree on that CONTEXT.md does not name yet.

**Confirmed (CONTEXT.md):**

1. **claim mechanism** — label `agent-working` + comment, released by `release.sh` (aiworx) or not at all (crm) vs. assignee `@me` released by `claim.sh --release` (cc-otel). Hand-back label differs (see disagreement 7).
2. **worktree layout** — `$ROOT/.claude/worktrees/<slug>-<n>` (crm, aiworx) vs. sibling `<root>-<n>` with gitignored env files copied in and back out (cc-otel); dependency bootstrap in the worktree (`npm ci --omit=dev` / `PYTHONPATH` + main venv / nothing).
3. **local gate** — the body is the repo's (CONTEXT.md already says so). Also per-repo *tripwires* that precede the gate (aiworx bundle rebuild) and the test command / test-file layout.
4. **review-bot topology** — three live shapes: auto round-1 Copilot + push-triggered CodeRabbit (crm); Copilot requested per round, soft cap 4, timeline read-back (aiworx); `copilot-pr-review-loop` sibling skill in unattended mode, cap 2 (cc-otel). Convergence definition, round cap, known-non-issues list and "phase 7 runs at all" all hang off this axis.
5. **verification kind** — live/integrated test needing creds (crm, cc-otel) vs. browser verification needing Chrome plus a per-OS caveat proven by the CI matrix (aiworx); plus the repo's *blocking prerequisites* (cc-otel: schema change without Docker is blocked).
6. **versioning** — `python-semantic-release` reads the squash subject, `feat:` reserved (crm); `bump-version.js` must land *in the PR* and CI's version gate enforces it (aiworx — and the aiworx ship copy never mentions it, see gaps); no tooling (cc-otel).
7. **PR template** — present and "don't pass a raw `--body` that bypasses the template" (crm, cc-otel) vs. absent → plain body (aiworx).
8. **small-lane floor** — secret scan + one node (crm, cc-otel) vs. fingerprint + base-fresh + one test file, self-review never collapses (aiworx).

**New candidates (not in CONTEXT.md; each is a real per-repo difference the profile must carry):**

9. **ci-topology** — a red macOS/Windows leg is a real signal (aiworx); path-filtered CI can legitimately report `no-checks` on a docs-only PR (cc-otel); metered Actions minutes impose one-push-per-round (cc-otel). Drives phase-8 interpretation and the merge summary's `CI:` row.
10. **docs-sync targets** — which artifacts are coupled (README / `docs/` / shipped skill / `CONTEXT.md` / `examples/` / map issue), whether a docs-sync subagent exists, and which docs are agent-facing.
11. **adjacent-finds disposition** — "file a `needs-triage` issue, don't fix inline" (crm, aiworx) vs. the fix-first disposition ladder "ticket the forks, not the observations" (cc-otel). Could instead be settled as one core rule (disagreement 3).
12. **public surface** — lane key 1's enumeration and key 2's "provable without <X>" are repo facts (aiworx names its CLIs, gate rules, palette, bundle inputs; crm/cc-otel keep the generic wording).
13. **current-docs sources** — context7 everywhere, plus Microsoft Learn (crm, cc-otel) and a named list of pinned libraries whose version matters (aiworx). Minor; a profile list.

---

## Disagreements that need a human decision

Ranked by how much of the fresh write they block.

1. **Task-list storage.** crm and cc-otel: harness task tools first (`TaskCreate`/`TaskUpdate`, `ToolSearch` probe, `TodoWrite` fallback, then a markdown checklist in replies) — `R/context-discipline.md:49-57` / `:46-54`. aiworx (#221, 2026-09-06, newest): a scratch file `ship-<issue>.md` in the harness scratchpad *is* the source of truth, harness tools are an optional mirror, and "a probe that returns nothing is the normal case on Claude 5-family models: the harness omits the task tools by default unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set" (`R/context-discipline.md:51-64`). aiworx's clock stamps + the merge summary's `Timing:` line (#224) only work on the file. Recommendation: scratch file as source of truth (it is the defect-learned one and needs no tool the harness may withhold).
2. **Small-lane self-review.** crm: "Skip the phase-4 self-review *iff* the repo has an auto-review bot" (`R/small-lane.md:12-14`). cc-otel: "Skip the phase-4 self-review — the phase-7 review loop is the review gate" (`R/small-lane.md:12-13`) — which **contradicts its own** `R/cc-otel.md:35-36` "Phase-4 self-review always runs — it is the only review a `docs`-class change gets besides CI". aiworx: "The phase-4 self-review still runs — it is the mandatory gate and never collapses" (`R/small-lane.md:12-13`). Recommendation: aiworx — the self-review is the one review every topology has, and the two rejection rails (#218) live in it.
3. **Adjacent finds: file or fix.** crm/aiworx `S:175-178` / `S:192-195`: "An adjacent bug or cleanup you spot is **out of scope**: file a `needs-triage` issue for it and move on, don't fix it inline." cc-otel `S:179-185` + `C:20-22`: the four-rung fix-first ladder, "More new tickets than the PR has commits means the reviewer is being obeyed rather than triaged" (#332). Either make the ladder core (it subsumes the other: rung 2 *is* "file a ticket") or make it axis 11.
4. **Script output contract.** crm/aiworx scripts: `PASS <name>` / `FAIL <name>` lines + last-40-lines of each failing log, exit 0/1; JSON via `jq -n` for the GitHub scripts (`S:29-36`). cc-otel: "one JSON verdict on **stdout**, a failing step's log tail on **stderr** — never a full log — exit 0 ok / 1 real failure / 2 tooling" (`S:86-88`), gate statuses `pass` / `fail` / `deferred-to-ci` / `unavailable` (`s/local-gate.sh:22-23`), pure-bash `ship_emit` instead of `jq`. The generic mechanics need one contract; the local-gate contract in particular decides whether "local gate green" can ever silently mean less than "CI green" (cc-otel's `unavailable`/`deferred-to-ci` exist for exactly that, #226/#401). Recommendation: cc-otel's three-way exit + status vocabulary; keep `jq` (already a hard dependency in every GitHub script).
5. **GitHub access path.** crm/aiworx: REST only, `api() { gh api "$@" || { sleep 2; gh api "$@"; }; }` in every script — "gh's GraphQL path flakes 401 mid-session" (`s/poll-pr.sh:3-4`). cc-otel: `gh issue view --json`, `gh pr view --json mergeable`, `gh pr merge --squash`, `gh pr checks --watch` — the GraphQL-backed calls the user's own global rule names as the flaky ones. Recommendation: REST + one retry for the generic mechanics.
6. **Secret scan as core floor.** crm `R/small-lane.md:29-31` and cc-otel `:28-30`: "the **local secret scan** (the repo may be public — a leaked cred is irreversible)" is floor. aiworx has **no secret scan anywhere** (its gate is fingerprint / npm test / clean tree / base fresh) despite being a public plugin repo. Recommendation: floor is core; the scanner (semgrep ruleset / grep regexes / other) is the local-gate body.
7. **Hand-back label after a blocked stop.** aiworx `s/release.sh:6-11`: release **and** re-apply `needs-triage` — "not `ready-for-agent`: a run that stopped blocked is a signal a human should look, not an invitation for the next agent to walk into the same block". cc-otel `R/cc-otel.md:49-51`: unassign so the issue "re-enters the frontier — or hand it to a human per the cloud routine's rules when in a fire". crm: no release mechanism at all. Recommendation: aiworx's semantics, expressed through whichever claim mechanism the profile names.
8. **Merge-summary rows** (map's open question). crm/cc-otel rows `tests · lint · type · docs · security-scan`; aiworx `tests · fingerprint · bundle-repro · clean-tree` plus `bundle:`, `OS-specific claims:`, `Timing:` lines. If the local gate emits JSON (decision 4) the `Local gate:` row can be derived from it and the profile carries only the verification/CI rows.
9. **Existing-PR detection in pre-flight.** crm: any cross-referenced open/merged PR stops the run (`s/preflight.sh:22-29`) — undirected, false-stops on a PR that merely mentions the issue. aiworx (#83): split on a closing keyword aimed at *this* issue, code spans stripped, `mentions[]` returned as context (`s/preflight.sh:36-68`). cc-otel: PR whose head branch ends in `-<issue>` (`s/preflight.sh:31-38`) — never false-stops, but misses a PR on a non-convention branch. Recommendation: aiworx's closing-keyword split **or**'d with cc-otel's branch-suffix match.

**Gaps (not disagreements — a copy is simply missing something another copy learned):**

- crm has no `release.sh`: a claim leaks on every blocked stop and stays on the closed issue after merge (aiworx `R/merge-gate.md:59-60`: "pre-flight refuses the issue forever" once reopened).
- cc-otel `preflight.sh` reports `assignees` but never stops on one (`s/preflight.sh:18, 23`); only the cloud picker's frontier query protects a manual re-run.
- cc-otel `merge.sh` never releases the assignee; same reopen hazard as above.
- aiworx `SKILL.md` never mentions the version bump that its CI `plugin` job enforces (`C:54-58`); a `/ship` run on a `skills/`/`tools/`/`dist/` change goes red in phase 8 with no phase telling it why.
- cc-otel `isolate.sh` hardcodes `main` (`s/isolate.sh:24,31`); crm/aiworx resolve `origin/HEAD`.
- crm/aiworx `isolate.sh` use `git rev-parse --show-toplevel` (`s/isolate.sh:12` / `:14`) — run from inside a worktree it nests a worktree; cc-otel resolves the main checkout via `--git-common-dir` (`s/isolate.sh:17-19`).

---

## Inventory

### A. Framing and contract (SKILL.md preamble)

| Item | crm | aiworx | cc-otel | Class | Notes on disagreement |
|---|---|---|---|---|---|
| Frontmatter: composes `tdd` + `code-review` | S:3-7 | S:3-7 (+ `writing-for-agents`) | S:3-7 (+ `copilot-pr-review-loop`) | core | Extra skills: `writing-for-agents` → core (row D-15); `copilot-pr-review-loop` → axis:review-bot. |
| "also invoked by the cloud ship routine" | S:6-7 | absent | S:7 | core | Sibling-skill interface (`cloud-ship`); keep the sentence. |
| `metadata.internal: true` | S:9-10 | absent | absent | drop | crm's `npx skills add` packaging flag; the global skill is installed, not vendored. |
| Opening promise: "implemented test-first, integration-tested, self-reviewed, bot-reviewed, and CI-green" | S:15-18 | S:13-16 ("browser-verified") | S:13-16 | core | The verification adjective is axis:verification wording. |
| "This skill is **generic** — everything repo-specific lives in … project instructions … **Read them first** … if any is missing, surface the gap — don't guess" + the list of facts needed | S:20-27 | S:18-26 | S:18-26 | core | This list **is** the ship profile's field inventory: test command (from a worktree), live-test targets + creds / browser story, full local-gate set "(not a fixed triad)", docs-sync rules, commit-subject convention, review bot + roles. cc-otel adds `reference/cc-otel.md` for "what this repo's `CLAUDE.md` *doesn't* carry" — the closest existing thing to a ship profile. |
| Scripts section: "deterministic steps are encoded, not prose … the script is the single source of truth for that step's mechanics" | S:29-45 | S:28-45 | S:84-103 | core | Contract disagreement → decision 4. cc-otel adds `_lib.sh` "one source so the two sides of a paired concern can't drift" (S:90-92). |
| Sandbox fallback: "In a sandbox that gates [api.github.com] … skip them and use the caller's MCP mapping; the local-only scripts still apply" | S:47-49 | S:47-49 | S:104-105 ("A repo without these scripts: fall back to the prose mechanics") | core | Sibling interface for `cloud-ship`. Keep both sentences. |
| Autonomy contract: one guaranteed stop + ambiguity rail + phase-3 hand-off; "Everything else … is **autonomous**, no mid-loop pause" | S:51-65 | S:51-66 | S:28-42 | core | Third pause's trigger is axis:verification (creds absent / no usable Chrome or OS-specific claim). |
| "**Never proceed on red.** … bounded self-fix-and-retry (~2 attempts) … **stop and report**; never merge on red. Make the report a **fast yes**" | S:67-72 | S:68-73 | S:44-49 | core | |
| Release the claim on any run ending short of the merge — "or it outlives the run and blocks every future one. Not at the phase-3 … hand-off: that one waits and resumes" | absent | S:73-78 | S:162-163 (prose only) | core | **Defect-learned (#85).** crm has no release at all (gap). |
| Argument: number / omitted → ask / free text = task spec, skip fetch | S:74-77 | S:80-83 | S:51-54 | core | |
| Consult current docs, verify against **pinned** version before acting on a bot's API claim | S:79-87 | S:85-93 | S:56-64 | core | Doc sources (MS Learn) and the named pinned libraries → axis:current-docs (profile list). |
| Model tiers table + "Tag every subagent … explicitly — never default-inherit" + "tier [code-review's] two axes yourself" | S:89-106 | S:95-112 | S:66-82 | core | cc-otel adds rows "Implementation subagent (phase 2)" and "writing the implementation brief"; aiworx adds the `writing-for-agents` pass. Union them. |
| "Poll loops and gate runs are **scripts** … no model at all; a subagent there burns budget to relay what an exit code already says" | S:101-103 | S:107-109 | S:78-79 | core | |
| Lanes: three keys, "when unsure, it's *not* small", "Behavior change is allowed — a bugfix *is* one" | S:108-124 | S:114-135 | S:107-123 | core | Key 1's public-surface enumeration, key 2's "provable without <live call / browser>", key 3's repo tripwires → axis:public-surface. |
| Pipeline intro: read context-discipline first; "creating the run's ten-item task list … Don't start phase 0 until that list exists" | S:126-134 | S:137-145 ("once that checklist exists in the scratch file") | S:125-133 | core | Storage → decision 1. |
| "**Compose, don't reinline.** Load the `tdd` skill … `code-review` skill … through the Skill tool … never hand-roll their logic" | S:136-140 | S:147-153 | S:135-139 | core | |

### B. The pipeline — phases 0 to 9

| Item | crm | aiworx | cc-otel | Class | Notes on disagreement |
|---|---|---|---|---|---|
| **0** Pre-flight stop reasons: closed, existing PR, existing branch, already claimed | S:142-147 | S:155-163 | S:141-145 (closed, PR or branch — **not** claimed) | core | What counts as "existing PR" → decision 9. cc-otel doesn't stop on a claim (gap). |
| **0** Push-access check runs first — "the only one the rest of the run cannot see: every read-only call succeeds for an account that cannot push … stays invisible until phase 9's merge answers 404" | absent | S:158-161 | absent | core | **Defect-learned (#218).** |
| **0** `mentions[]` = live PRs that merely name the issue — "context to carry into phase 1, never a reason to stop" | absent | S:161-163 | absent | core | **Defect-learned (#83).** |
| **0** Rationale note: picker-based runner relies on the phase-1 claim; pre-flight "catches a *manual* re-run or an already-shipped issue, where there is no picker" | S:144-147 | absent | S:143-145 | core | Sibling interface (`cloud-ship`). |
| **0** Create isolated workspace: `EnterWorktree`, or `isolate.sh` when absent | S:147-150 | S:163-167 ("it also installs the runtime deps a worktree needs") | S:145-148 (always `isolate.sh`; sibling worktree; copies env files) | axis:worktree | Core requirement: fresh branch off the up-to-date default in an isolated checkout. |
| **0** Branch `<type>/<slug>-<issue>`, `<type>` matches the issue | S:150-151 | S:166-167 | S:146-147; s/_lib.sh:24-30 | core | Pre-flight's branch check depends on this suffix in all three. |
| **0** "**Commit as you go** … the PR needs real commits"; branch `<type>` is a label — "The squash subject, not the branch, drives release tooling" | S:153-157 | S:169-172 | S:150-154 | core | "release tooling" vs "release history" is axis:versioning wording. |
| **1** Fetch issue + comments, derive success, spec precedence, "**If it's too vague to plan, stop and ask**" | S:159-162 | S:174-177 | S:156-159 | core | |
| **1** Claim before implementing, idempotent; "Don't claim if you stopped on the ambiguity rail; if you claim then stop blocked, hand the issue back" | S:163-166 ("skip if … no documented claim convention") | S:178-183 | S:160-163 | core | Mechanism → axis:claim; hand-back label → decision 7. |
| **2** Classify `docs`/`code`/`infra`, "announce the class and the skip path it implies — **and whether it passes the three lane keys**" | S:168-172 | S:185-189 | S:165-171 | core | |
| **2** Where implementation runs: judgment on main thread, execution to one sonnet subagent when the plan is settled; "Keep implementation on the main thread when the issue is exploratory, the spec is still settling, or the change touches schema / architecture" | S:173-175 → R/implement.md:29-51 | S:189-191 → R/implement.md:42-64 | S:172-179 (inline) | core | Same rule, three phrasings; cc-otel's schema/architecture clause is the sharpest. Tripwires only in crm/aiworx (row D-19). |
| **2** "**Stay surgical** … every changed line should trace to it" | S:175-176 | S:192-193 | S:179-180 ("or to a rung-1 ad-hoc fix named in the PR body") | core | |
| **2** Adjacent bug/cleanup: file `needs-triage`, don't fix inline — vs. fix-first disposition ladder | S:176-178 | S:193-195 | S:180-185; C:20-22 | axis:adjacent-finds | → decision 3. |
| **2** Deviations log from the first edit; "resolve it by the conservative option, log what + why, and keep going"; lands verbatim in PR body + merge summary | S:178-183 | S:195-200 | S:186-191 | core | |
| **2** Balloons mid-flight → "**stop and report** with a split proposal … (the ambiguity rail applies mid-run too)" | S:183-186 | S:200-203 | S:191-194 | core | |
| **2** Bundle discipline: rebundle + commit `dist/` in the same change; "`browser.js` refuses a stale fingerprint, so forgetting turns every later browser call red" | absent | S:205-210; R/implement.md:35-40 | absent | axis:local-gate | Profile field: pre-gate tripwires. Generic wording: "the repo's tripwires (profile) apply whatever the class". |
| **3** Verify "**only what you touched**, on the environment the bug was reported against"; `docs` or small-lane → skip to gate | S:188-192 | S:212-219 | S:196-200 | core | Kind → axis:verification. |
| **3** OS caveat: "this machine proves Linux claims; macOS/Windows claims … are proven by the CI matrix, not locally" | absent | S:215-217; R/implement.md:94-99 | absent | axis:ci-topology | Generic form: "a claim this machine cannot prove is proven by the named CI leg; watch it in phase 8". |
| **4** "Sync docs **before** reviewing, so the review reads the docs edits as part of the diff" | S:194-196 | S:221-223 | S:202-204 | core | |
| **4** Docs-sync fires only on public-surface or observable-behavior change; skip list (infra, restoring documented behavior, test-only, comments); "when you skip, say so in one line at the merge gate" | S:198-206 | S:225-231, 239-242 | S:206-214 | core | Targets + subagent → axis:docs-sync. |
| **4** Agent-facing docs go through `writing-for-agents` (judgment tier); human prose takes the mechanical pass | absent in S (C:66: crm's docs-sync agent invokes it for `crm/skills/`) | S:232-237; C:52 | absent | core | 2 of 3 repos + this repo's own map note ("`writing-for-agents` for any skill or profile prose"). Which docs are agent-facing → axis:docs-sync. |
| **4** Self-review via `code-review`, per-axis tiers; **auto-triage** canonical definition: "harden rather than rip out capability, verify nits against the **pinned** dependency versions, reject known non-issues; fix the valid ones; record a one-line disposition per finding" | S:208-213 | S:244-248 | S:216-223 | core | cc-otel appends "A finding is an observation, not a work item — run each one down the **fix-first disposition ladder**" (decision 3). |
| **4** Two rejection rails: repo-existence claims checked "against `origin/main` — the base the review pinned — never against the worktree, which may predate a merge"; "a finding's **evidence and its claim are separate**: a reviewer citing the wrong commit for a real primitive is still right" | absent | S:250-255; R/review-loop.md:67-69 | absent | core | **Defect-learned (#218) — "both learned from a defect that reached main".** |
| **4** "This self-review plus green CI *is* the review gate — don't skim it. The Copilot rounds … are a second pair of eyes on top, not a substitute" | absent (crm: bot round-1 is the gate in small lane) | S:256-258; C:85 | R/cc-otel.md:35-36 (contradicted by R/small-lane.md:12-13) | core | → decision 2. |
| **5** Precondition: "phase 3 passed **or** the class is `docs` — if neither holds, you skipped a verification; stop and go back" | S:215-216 | S:260-261 | S:225-226 | core | |
| **5** Run the local gate green before opening the PR; "mirrors the checks CI actually runs"; "Run it inline: it projects its own output, so a subagent adds nothing" | S:218-223 | S:263-273 | S:228-236 | core | Body → axis:local-gate. |
| **5** Checks CI runs that the gate can't: "at least *anticipate* it" (prose) vs. explicit `deferred-to-ci` / `unavailable` statuses — "`unavailable` → a required tool is missing — surface it, don't silently skip" | S:222-223 | S:272-273 | S:230-234 | core | → decision 4. Principle in all three; only cc-otel makes it machine-checkable. |
| **5** Base-fresh check — "the one thing **CI cannot**: that the branch has seen every commit on its base. CI tests the merge ref, so a branch that predates a merge still goes green — while every 'does this already exist?' question you answer from the worktree gets the pre-merge answer" | absent | S:267-271; s/local-gate.sh:72-94 | absent | core | **Defect-learned (#218).** Same root cause as the `origin/main` rejection rail. |
| **5** Small lane: `local-gate.sh --small <node|test-file>` | S:224-225 | S:274-275 | S:234-236 | core | Content → axis:small-lane-floor. |
| **6** Open a **ready** (non-draft) PR — "drafts may not trigger the project's automated review" | S:227-228 | S:277 | S:238-239 | core | |
| **6** Title = Conventional-Commit subject derived from the issue; "release tooling reads this on squash-merge" | S:228-229 | S:277-279 | S:239-240 | core | axis:versioning wording. |
| **6** PR template: "fill it in … tick / strike-through each checklist item honestly … Don't pass a raw `--body` that bypasses the template; let it populate, then edit" | S:229-236 | S:279-282 (no template → plain body) | S:240-247 | axis:pr-template | `Closes #<issue>` + **Deviations from plan** section → core in every variant. |
| **6** "An automated round-1 review may fire on PR creation — **don't re-request round 1**" / "Review fires in phase 7 — nothing to wait for at PR-open" | S:236-237 | absent | S:247-248 | axis:review-bot | |
| **6** "**Reflect the PR back on the issue** right after opening … so a scheduled run won't re-pick it" | S:238-240 ("skip if no documented convention") | S:283-284 | S:249-250 (`reflect.sh`) | core | Sibling interface (`cloud-ship` picker). Script it once generically. |
| **7** Runs "**Only if the repo has an automated reviewer configured** (per project instructions — never an assumption)" | S:242-243 | S:286-287 | S:252 (always; the loop skill is the reviewer) | axis:review-bot | |
| **7** Reviewer roles + convergence: round-1 dispositioned once, push-triggered owns iteration, "Converged = the iterating reviewer quiet on the latest push + all round-1 threads dispositioned" | S:243-252 | S:287-294 (request per round, soft cap 4, "Converged = the latest round returns nothing actionable + every thread … dispositioned + green CI") | S:252-259 (unattended loop, 2-round cap, "Converged = the loop reports quiet … or the cap reached with every finding dispositioned") | axis:review-bot | Three topologies; the profile picks one and names the logins. |
| **7** Auto-triage every comment with phase 4's definition, judgment tier | S:248-249 | S:292 | S:256-257 | core | |
| **7** Read the request back off the PR **timeline** — "Copilot never shows up in `requested_reviewers`, so an empty array there says nothing" | absent | S:290-292 | absent | axis:review-bot | **Defect-learned (#219)**; must ship inside the generic skill's Copilot-on-request option, not be left for a profile to rediscover (row D-27). |
| **8** CI overlaps phase 7; conflict → "A conflicted PR has no merge ref, so merge-commit checks never start and CI sits **pending forever** — don't wait on it. Resolve: fetch … rebase … **re-run the local gate (phase 5)**, and push" | S:254-260 | S:296-302 | S:261-267 | core | |
| **8** Red after review converged: fix, push, proceed on green — "a lint/format/flake fix earns no review anyway" | S:261-263 | absent | S:267-269 | core | |
| **8** "**A red macOS or Windows leg with a green Linux leg is a real signal, not a flake**" | absent | S:302-305; C:23 | absent | axis:ci-topology | |
| **8** `"no-checks"` on a docs-only diff is fine (path-filtered CI) | absent | absent | S:269; s/ci-wait.sh:32-33 | axis:ci-topology | |
| **9** "**Hard stop.** Post the summary and wait for the user's explicit 'merge'; on approval, squash-merge, delete the branch, clean up the worktree" | S:265-268 | S:307-310 | S:271-275 | core | |
| Reference-files index | S:270-281 | S:312-324 | S:277-288 | core | Regenerate from whatever the fresh write ships. |

### C. Scripts — one row per feature

Generic mechanics per CONTEXT.md: preflight, claim and release, isolate, CI wait, merge, reflect. Only `local-gate.sh` stays per repo (its *contract* is still core).

| Item | crm | aiworx | cc-otel | Class | Notes on disagreement |
|---|---|---|---|---|---|
| `api()` wrapper: REST via `gh api`, one retry after 2 s — "gh's GraphQL path flakes 401 mid-session; every call retries once" | s/preflight.sh:12; claim.sh:11; poll-pr.sh:30; merge-and-verify.sh:15 | same + s/release.sh:38 | absent (`gh issue/pr` subcommands, `set -e`) | core | → decision 5. |
| **preflight** output `{actionable, reasons[]}`, all reasons collected, exit 0/1 | s/preflight.sh:8, 35-40 | s/preflight.sh:9-11, 74-81 (+ `mentions[]`) | s/preflight.sh:8-9 (`{actionable, reason, assignees}`, first hit wins, exit 0/1/2) | core | Collect-all (crm/aiworx) gives the human a fuller stop report; keep it. |
| preflight: push-access check first (`repos/{owner}/{repo}` `.permissions.push`), with the `gh auth switch` hint | absent | s/preflight.sh:19-27 | absent | core | **Defect-learned (#218).** |
| preflight: issue state ≠ open → reason | s/preflight.sh:16-17 | :30-31 | :21-29 | core | |
| preflight: "`#N` is a PR, not an issue" | s/preflight.sh:18 | :32 | absent | core | |
| preflight: already claimed | s/preflight.sh:19-20 (`agent-working` label) | :33-34 | absent (assignees reported, not enforced) | core | Mechanism axis:claim; the stop is core. |
| preflight: existing PR — undirected cross-reference / closing-keyword split with fenced-code stripping and multi-issue "Closes #75, #81" / head-branch suffix | s/preflight.sh:22-29 | :36-68 | :31-38 | core | **Defect-learned (#83)** → decision 9. |
| preflight: remote branch `*-<issue>` exists | s/preflight.sh:31-33 | :70-72 | :40-44 (anchored regex from `_lib.sh`) | core | |
| **isolate**: fetch first — "refusing to branch off a possibly-stale default" | s/isolate.sh:13-16 | :15-18 | :24 (hardcoded `main`) | core | Resolve `origin/HEAD`, don't hardcode. |
| isolate: refuse if branch exists — "preflight should have stopped this run" | s/isolate.sh:19-22 | :21-24 | :26-29 (also refuses if worktree path exists) | core | |
| isolate: worktree location | s/isolate.sh:24-26 (`$ROOT/.claude/worktrees/<slug>-<n>`) | :26-28 | :22 (sibling `<root>-<n>`) | axis:worktree | |
| isolate: resolve the **main** checkout via `--git-common-dir` "even when invoked from inside another worktree" | absent (`--show-toplevel`) | absent | s/isolate.sh:17-19 | core | cc-otel's is the correct one (gap in the other two). |
| isolate: copy gitignored env files in (`SHIP_ENV_FILES`), report `env_files[]` | absent | absent | s/isolate.sh:33-42; s/_lib.sh:18-21 | axis:worktree | Profile field: files to carry. Empty list is a valid value. |
| isolate: install runtime deps in the worktree ("node_modules is not shared with the main checkout") | absent (`local-gate.sh` handles `PYTHON`/`PYTHONPATH` instead, :18-23) | s/isolate.sh:30-35 | absent | axis:worktree | Profile field: worktree bootstrap command. |
| isolate output: bare path vs JSON `{worktree, branch, env_files}` | s/isolate.sh:27 | :36 | :43 | core | → decision 4. |
| **claim**: idempotent — existing claim is a no-op success | s/claim.sh:2-4, 13-17 | :2-4, 13-17 | :3 ("Idempotent both ways") | core | |
| claim: mechanism — label `agent-working` + strip `ready-for-agent` + comment "🤖 Claimed by a ship run — implementation in progress." vs `gh issue edit --add-assignee @me` | s/claim.sh:9, 20-22 | :9, 20-22 | :16-21 | axis:claim | |
| claim: "A false success here would let a concurrent run double-pick — fail loudly" | s/claim.sh:19 | :19 | :14 (`fail` → exit 2) | core | |
| **release**: separate script; "so a claim never outlives the run that took it"; two callers (post-merge release-only, `--handback` adds `needs-triage`) | absent | s/release.sh:1-24 | s/claim.sh:16-18 (`--release`, no hand-back label) | core | **Defect-learned (#85).** Label semantics → decision 7. |
| release: check label state rather than assume — "a DELETE 404s the same way whether the label was already gone or the call itself failed" | absent | s/release.sh:12-16, 45-52 | n/a | core | Applies to the label variant of axis:claim. |
| release: unknown flag → exit 2 — "A typo'd flag must not read as release-only: the caller would believe a hand-back landed that never ran" | absent | s/release.sh:29-36 | absent | core | Script-hygiene rail; apply to every generic script's arg parser. |
| release: hand-back that didn't land → exit 1 even though the claim is gone | absent | s/release.sh:65-67 | absent | core | |
| **local-gate** contract: one line per check, "only the failing output", last 40 lines | s/local-gate.sh:2-3, 34-43, 63-73 | :2-3, 41-50, 122-132 | :6-7, 57-70 (JSON record, tail-40 to stderr) | core | Format → decision 4. |
| local-gate: `--small <node>` runs the floor + the one proving node | s/local-gate.sh:25-28, 45-47 | :22-25, 96-99 | :17, 36, 140-142 | core | Floor content → axis:small-lane-floor. |
| local-gate: statuses `pass` / `fail` / `deferred-to-ci` / `unavailable`; exit 0/1/2; "`unavailable` … TOOLING rather than silently skipping" | absent | absent | s/local-gate.sh:22-23, 76-111, 245-252 | core | → decision 4. Principle: local green must never mean less than CI green (s/_lib.sh:76-78, #401). |
| local-gate: selection derived from workflows' own `paths:` filters; unmapped triggered workflow → `unavailable`; explicit exclusion list for workflows with no local mirror | absent | absent | s/local-gate.sh:145-171; R/cc-otel.md:53-63 | axis:local-gate | Body. The *fail-loudly-on-unmapped* principle is core (row above). |
| local-gate: `--base <ref>`, `--all`, `--no-docker` | absent | absent | s/local-gate.sh:11-17, 30-39 | axis:local-gate | `--base` and `--all` are generic enough for the contract; `--no-docker` is body. |
| local-gate: secrets grep always on — added diff lines + untracked files, self-excluded, one sanctioned literal, regexes under test in `_lib.sh` | semgrep ruleset (s/local-gate.sh:46, 53) | **absent** | s/local-gate.sh:113-138; s/_lib.sh:64-71 (#269) | core (floor) / axis:local-gate (scanner) | → decision 6. |
| local-gate: workflow linters only when `.github/` changed; pinned-version lockstep comment | s/local-gate.sh:55-60 | absent | (via pre-commit / path selection) | axis:local-gate | Body. |
| local-gate: pyright floor read from `pyrightconfig.json`, "never hardcoded" | s/local-gate.sh:30-32 | absent | absent | axis:local-gate | Body; the pattern "read the pin from the config CI reads" is worth a sentence in the local-gate guidance. |
| local-gate: fingerprint check; bundle rebuild + `dist_unchanged` "Bytes AND paths: `git diff` alone misses an added file"; check clean fixture | absent | s/local-gate.sh:27-39, 52-70, 103-108 | absent | axis:local-gate | Body. |
| local-gate: clean-tree check — "verification must not dirty the repo" | absent | s/local-gate.sh:101, 110-119 | absent | axis:local-gate | Body (mirrors aiworx CI). |
| local-gate: base-fresh check; "An unresolvable base fails: a check that could not ask its question must not answer 'fresh'" | absent | s/local-gate.sh:72-94 | absent (diff is against merge-base but never fails on behind, :43) | core | **Defect-learned (#218).** Belongs in the generic contract, not the body — it is repo-independent. |
| local-gate: Docker / pwsh / Windows-PowerShell gating with `deferred-to-ci`; Pester under 5.1 via `winps-pester.ps1`, exit 3 = unresolved "must never read as `pass`" | absent | absent | s/local-gate.sh:76-111; s/_lib.sh:73-85; s/winps-pester.ps1 | axis:local-gate | Body (#401). The deferral status is the core part. |
| local-gate: dev-DB safety — `unset DATABASE_URL` before self-spinning tools | absent | absent | s/local-gate.sh:200-206 | axis:local-gate | Body. |
| ship scripts under unit test (`test_ship_lib.py` pins the secrets regexes and the exit-code mapping) | absent | absent | s/_lib.sh:9-13 | core | Practice: the generic scripts' load-bearing pieces get tests in this repo. |
| **poll / CI wait**: bounded foreground loop, ONE JSON summary, `--timeout 480 --interval 20`, `done:false` + exit 3 = "window closed first — re-run to keep waiting" | s/poll-pr.sh:1-28, 54-66 | :1-40, 78-92 | s/ci-wait.sh (`gh pr checks --watch` under `timeout`, 1800 s, exit 2 on timeout) | core | Implementation → decision 5. |
| poll: `mergeable_state: dirty` → done immediately (conflict) | s/poll-pr.sh:13-15, 46-47 | :13-15, 69-70 | s/ci-wait.sh:23-30 (checked first) | core | |
| poll: reviews keyed to the **current head sha** — "a review on an older commit does not count" | s/poll-pr.sh:8-10, 40-41 | :8-10, 52-54 | absent | core | For any topology that awaits a review. |
| poll: `substantive` — "A reviewer's reply to ONE COMMENT THREAD posts as a review row of its own … Only a non-empty body is a round" | absent | s/poll-pr.sh:18-22, 54, 73 | absent | core | **Defect-learned (#211).** |
| poll: `reviewer_blocked` — the awaited login's quota/queue comment; "Non-null with done=false means the round is WAITING, not missing" | absent | s/poll-pr.sh:24-28, 56-64 | absent | axis:review-bot | Copilot-specific phrases; ship with the Copilot option. |
| poll: `--await-review <login>` | s/poll-pr.sh:6, 49 | :6, 72-73 | absent | axis:review-bot | |
| ci-wait: `no checks reported` → `no-checks`, exit 0 | absent | absent | s/ci-wait.sh:32-33, 42-44 | axis:ci-topology | |
| ci-wait: `--watch` non-zero "could be a check failure OR a tooling/auth blip; if this follow-up read also fails … report tooling instead" | absent | absent | s/ci-wait.sh:50-58 | core | Keep the principle whichever transport wins. |
| Source guard when `set -e` is off — "a failed load must still emit the JSON verdict contract … not 'command not found' to stdout" | absent | absent | s/ci-wait.sh:12-15; s/merge.sh:14-17 | core | Script hygiene. |
| **merge**: squash via REST `PUT …/merge` with `commit_title="<title> (#<pr>)"` vs `gh pr merge --squash` | s/merge-and-verify.sh:21-23 | :25-27 | s/merge.sh:48 | core | → decision 5. Both agree the PR title is the squash subject. |
| merge: "Never assume the command took — verify merged state before reporting done" | s/merge-and-verify.sh:25-28 | :29-32 | :50-56 (3 retries) | core | |
| merge: delete the remote branch explicitly; "May legitimately 422 if GitHub's auto-delete already removed the branch" / "`gh --delete-branch` fails its local step while `main` is checked out" / `ls-remote --exit-code` "Only exit 2 proves deletion — don't let a network blip read as success" | s/merge-and-verify.sh:30-32 | :34-37 ("this repo does not auto-delete branches on merge") | :69-74; C:31 | core | Take cc-otel's proof-of-deletion. |
| merge: issue-close fallback — "give the Closes-keyword automation a beat", then PATCH/`gh issue close` | s/merge-and-verify.sh:34-44 | :59-69 | :58-67 | core | |
| merge: fast-forward the local base branch, worktree-aware — "This script runs from the feature worktree, so a plain `git pull` here would pull the base INTO the feature branch"; ff-check by hand when no checkout holds the base; best-effort | absent | s/merge-and-verify.sh:39-57; R/merge-gate.md:62-71 | s/merge.sh:84-97 (only if the main checkout is on `main`) | core | **Defect-learned (#83).** |
| merge: ff-pull retry past a transient `index.lock` from a concurrent `git status` — "Never auto-delete the lock … which this script can't prove" | absent | absent | s/merge.sh:84-94 | core | **Defect-learned** (cc-otel ab98cf5, 2026-07-20). Shared-checkout hazard, not Windows-only. |
| merge: release the claim; "A claim left on a closed issue is harmless until someone reopens it, at which point pre-flight refuses the issue forever" | absent | s/merge-and-verify.sh:71-79; R/merge-gate.md:58-60 | absent | core | Mechanism axis:claim; the step is core (gaps in crm and cc-otel). |
| merge: copy gitignored env files out of the worktree before destroying it | absent | absent | s/merge.sh:41-46 | axis:worktree | Pairs with isolate's copy-in via `SHIP_ENV_FILES`. |
| merge: remove worktree + force-delete local branch — "A squash-merged branch is not an ancestor of main: force delete" | prose R/merge-gate.md:56-58 | prose R/merge-gate.md:73-75 | s/merge.sh:76-82 (scripted) | core | Script it; the prose says the same thing in all three. |
| merge: per-step boolean JSON; "Any `false` in the JSON → finish that step by hand before reporting done" | s/merge-and-verify.sh:46-49 | :82-88 | :8-10, 31-37, 99-101; R/merge-gate.md:63 | core | |
| merge: "intentionally no `set -e` — the cleanup steps … use explicit `\|\| finish 1` / `\|\| true`, and `git ls-remote --exit-code` returning non-zero is a *success* signal" | absent | absent | s/merge.sh:24-27 | core | Script hygiene. |
| **reflect** as a script: `gh issue comment "PR: <url>"` | prose | prose | s/reflect.sh | core | Generic mechanic per CONTEXT.md. |
| **`_lib.sh`**: shared env inventory, branch convention, JSON emit, secrets regexes, exit-code mapping — "one source so the two sides of a paired concern can't drift" | absent | absent | s/_lib.sh (#230) | core | Answers part of the map's open question; contents 1 and 4 are axis values, the shape is core. |
| `ship_emit` `@`-sigil raw-JSON rule — "Forgetting the sigil yields a valid, stringified value — never invalid JSON" | absent (`jq -n`) | absent (`jq -n`) | s/_lib.sh:43-62 (#283) | core | Only if pure-bash emit wins in decision 4; otherwise drop in favour of `jq -n`. |

### D. Reference files — one row per section

| Item | crm | aiworx | cc-otel | Class | Notes on disagreement |
|---|---|---|---|---|---|
| **context-discipline** — "What bloats the window is raw tool output landing in the main thread, not the work itself" | R/context-discipline.md:1-5 | :1-5 | :1-5 | core | |
| Delegation rule — "**delegate noise, not size.** A subagent earns its cost only when the raw output you'd otherwise ingest is much larger than the conclusion you need" | :7-15 | :7-15 | :7-16 ("Suite runs, CI logs, and merge mechanics are scripts now") | core | |
| Lever: delegate reading — "a file body you only need to *understand* should never enter main context, only the hunk you *change* should" | :17-24 | :17-24 | :18-25 | core | |
| Lever: project every `gh`/CLI call; "A bare `gh pr view --json` serializes the entire PR object … kilobytes of noise" | :25-29 | :25-29 | :26-28 | core | |
| Lever: investigate inside the worktree from the start | :30-31 | :30-31 | :29-30 | core | |
| Lever: "Trust Edit/Write — don't verify-Read after a successful edit" | :32-34 | :32-34 | :31-33 | core | |
| Lever: targeted test nodes during the loop; full suite only at the gate | :35-36 | :35-38 (names `tests/<area>.js`, `npm test` includes browser smoke) | :34-35 | core | Test-file layout → axis:local-gate (profile: test command / node syntax). |
| Lever: noisy verification *runs* — live tests in a cheap-tier subagent returning pass/fail + failing lines; gate and polling are scripts, run inline | :37-43 | :39-45 | :36-40 (all scripts) | core | |
| Lever: one scratch file for the design/plan (survives a mid-run summary) | :44-45 | :46-47 (also holds the task list) | :41-42 | core | |
| First action — task list storage | :49-57 (harness tools → `ToolSearch` → `TodoWrite` → markdown in replies) | :51-64 (scratch file `ship-<issue>.md` is truth; tools optional mirror; Claude 5 omits them unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`) | :46-54 | core | → decision 1. **Defect-learned (#221)** on the aiworx side. |
| Clock-stamp every flip from `date -u +%H:%M`; re-opened phases append a range; midnight rule; feeds the `Timing:` line | absent | :66-85; R/merge-gate.md:39-42 | absent | core | #224 (2026-09-06). Contingent on decision 1 — the harness task tools carry no timestamps. |
| One item per phase, one `in_progress`, completed only when verification passed; "the map back if context is summarized mid-run" | :59-63 | :86-88 | :56-60 | core | |
| Small lane keeps the same ten items — "`skipped (small lane)` … so the record shows a decision, not a gap" | :63-65 | :86-88 | :60-62 | core | |
| The ten items | :67-76 | :90-99 | :64-73 | core | Items 2, 3, 7, 8 carry axis wording (rebundle, browser-verify vs integrated test, review topology, matrix legs); template them from the profile. |
| **small-lane** — what collapses by construction (docs-sync, phase 3) | R/small-lane.md:6-10 | :6-10 | :6-10 | core | |
| Self-review in the small lane | :12-14 (skip iff bot) | :12-15 (never skip; phase 7 still runs) | :12-13 (skip) | core | → decision 2. |
| Small-lane gate content | :15-18 (semgrep + node) | :16-20 (fingerprint + test file; script also runs base-fresh) | :14-17 (secrets grep + node) | axis:small-lane-floor | |
| Review in the small lane — round-1 is the whole gate / one loop round / Copilot round still requested | :19-21 | :12-15 | :18-20 | axis:review-bot | |
| "Subagents: usually none of your own" | :22-25 | :21-24 | :21-24 | core | |
| The floor — worktree, one regression test, PR, CI, merge gate | :29-31 (+ secret scan) | :28-31 (+ self-review, fingerprint) | :28-30 (+ secret scan) | core | Skeleton is core; the extra items → decisions 2 and 6. |
| Revocable — "The lane is falsifiable … **downgrades to the full lane** for the remaining phases … Downgrading once is cheap; shipping a non-small change as small is the failure" | :33-41 | :33-40 | :32-39 | core | Trigger list carries axis wording (bot / secret scan / fingerprint / OS leg). |
| **implement** — classes `docs` / `code` / `infra`; announce the skip path "so a wrong label is a visible decision now, not a silently-skipped verification later" | R/implement.md:6-27 | :6-33 | :6-27 | core | |
| `code`: invoke `tdd` "**autonomously** — red→green→refactor **without pausing for plan approval** (you're intentionally overriding tdd's plan-approval checkpoint)" | :18-20 | :18-26 | :18-20 | core | |
| `infra`: "don't force a contrived red. Extract the logic into a testable seam and unit-test its **observable behavior** through that seam" | :21-25 | :27-31 | :21-25 | core | |
| "When in doubt between `code` and `docs`, treat it as `code` and write the test" | :27 | :33 | :27 | core | |
| New test file must be wired into `test:fast` or `test:browser` (`tests/test-targets.js` enforces) | absent | :22-26 | absent | axis:local-gate | Profile field: where a new test goes / how it is registered. |
| Bundle inputs "a tripwire, not a class" | absent | :35-40 | absent | axis:local-gate | See B, phase 2. |
| Delegate execution, keep judgment — hand the subagent worktree path, plan, test command, conventions; require diff summary + test nodes + **structured deviations list** ("a subagent that fixes-and-forgets loses it") | :29-45 | :42-58 | absent (S:172-179 partial) | core | |
| Subagent tripwires: "Every Edit/Write path carries the **worktree prefix** … After its first edit, `git -C <main-checkout> status` must be clean"; runs only targeted nodes, gate stays with the orchestrator | :47-51 | :60-64 | absent | core | Defect-shaped (an absolute main-checkout path "silently edits the wrong tree"). |
| Verify the spec's external-system claims — "treat it as a **hypothesis, not a fact** and confirm it … with the cheapest possible probe *before* writing the fix around it" | :53-63 | :66-79 ("This repo exists because two such claims … turned out to be traps") | :29-39 | core | Example list → profile (axis:verification). |
| Spec precedence — "the latest authoritative spec wins, and the body's original acceptance criteria no longer bind" | :65-72 ("a review bot reading the stale body will flag 'missing' requirements … reject those in phases 4/7") | :81-86 ("Note this explicitly in the deviations log") | :41-48 | core | Merge both consequences. |
| Phase 3 detail — "**Run on the environment the bug was actually reported against** … a different environment may auto-heal the bug … Green ≠ fixed unless it's green where it failed"; hand-off when creds/Chrome absent | :74-83 | :88-101 | :50-59 | core | Target and hand-off trigger → axis:verification. |
| **copilot-loop / review-loop** — "A review bot re-reads the **whole PR** on each round, so treat every round's output as a fresh read of the committed tree, not a conversation" | R/copilot-loop.md:1-6 | R/review-loop.md:1-6 | absent (delegated to `copilot-pr-review-loop`) | core | |
| Round-1 reviewer: dispositioned once, "**Never re-requested in the ship flow** … `review_on_push: false`" | :8-12, 20-31 | absent | absent | axis:review-bot | |
| Iterating reviewer: reads replies — reply **on each review thread**; use its thread-resolution mechanism "only once **every** thread carries a disposition"; rounds are free, no ceiling | :13-15, 33-44; C:115 (`@coderabbitai resolve`) | absent | absent | axis:review-bot | |
| "If it runs neither, phase-4 self-review + green CI is the review gate — skip this phase" | :17-18 | absent | absent | axis:review-bot | The "none" option. |
| Known-non-issues note may be trimmed (`.github/copilot-instructions.md`, first 4000 chars) | :26-27; C:113 | absent | absent | axis:review-bot | |
| The lone re-request exception belongs to the `merge-gate` skill | :30-31; C:113, 119 | absent | absent | drop | Sibling skill's business; Ship only promises never to re-request round 1. |
| Requesting a Copilot round: POST `requested_reviewers`, then read the timeline; two identities (`Copilot` in the event, `copilot-pull-request-reviewer[bot]` on the review, `copilot-pull-request-reviewer` as the check) — "the login you POST is not the login you read back" | absent | :8-45; C:62-79 | absent | axis:review-bot | **Defect-learned (#219).** Ships inside the Copilot-on-request option. |
| The loop: request → poll → triage in one batched push, reply on each thread → request again | absent | :47-53 | absent | axis:review-bot | |
| "**Batch fixes into one push per round** — every push spends its (usually rate-limited) review quota" / "CI minutes are metered" | :41-42 | :51 | S:254-255; R/cc-otel.md:25-30 | core | Three reasons, one rule. |
| Converged definitions | :46-50 | :55-58 | S:257-259 | axis:review-bot | |
| Per-reviewer blocks in the merge summary — "the lanes need that accountability" | :50-52 | :57-58 | R/merge-gate.md:37-40 | core | One block per reviewer, whatever the topology. |
| "If the iterating reviewer stays substantive round after round, that's a shape problem more rounds won't fix — stop and report" / soft cap 4 → degraded / cap 2 | :54-55 | :60-62 | S:254 | core | Cap value → axis:review-bot; the stop-and-degrade rule is core. |
| "**Triage, don't apply.**" — same auto-triage + the two rejection rails | absent | :64-69 | absent | core | See B, phase 4. |
| Poll mechanics — run `poll-pr.sh` inline, "`done: false` means the window closed first — re-run to extend; never a detached background monitor" | :57-65 | :71-81 ("The poll is the **landing signal** only — before triage fetch the round's review body and comment threads") | S:263-269 (`ci-wait.sh`) | core | |
| "A round is a review with a body" — hold hand-rolled checks to `substantive: true` | absent | :83-86 | absent | core | **Defect-learned (#211).** |
| A round that hasn't landed: **never queued** (no timeline event) = unavailable → retry once → degraded; **queued but quiet** = keep polling, 2–4 min | absent | :88-103 | absent | axis:review-bot | Copilot-on-request option. |
| Infra flakes: error body with zero comments is "an **infra failure**, not feedback"; after a couple, proceed on green CI as a **degraded** exit "not convergence: note in the merge summary that the reviewer never actually passed" | :67-75 | :102-103 | absent | core | The degraded-not-converged rule is core; the detection wording per bot is axis. |
| "After any merge command, re-verify PR state before declaring done" | :77-78 | :105-106 | s/merge.sh:50-56 | core | |
| **merge-gate** — "make that call a 10-second yes/no by laying out everything they'd want to check" | R/merge-gate.md:1-5 | :1-5 | :1-5 | core | |
| "**Write it uncompressed.** A session-wide output style … does **not** apply to this summary. It is the evidence a human approves an irreversible squash-merge on" | absent | absent | :7-11 | core | **Defect-learned (#384).** |
| Summary template skeleton: header, PR, Issue, Lane, Implementation, Deviations, verification block, Self-review, Automated review, Local gate, Docs-sync, CI, "Ready to merge. Reply 'merge'…" | :9-42 | :9-45 (+ `bundle:`, `OS-specific claims:`, `Timing:`) | :15-47 | core | Row contents → decision 8. |
| "Then **wait.** … Never use an auto-merge flag while a review could still be pending — it can merge the instant CI is green, before a review lands" | :44-46 | :47-48 | :49-51 | core | |
| On approval: run the merge script; what it does | :48-54 | :50-71 | :53-63 | core | See C, merge rows. |
| Local cleanup after squash — force delete, discard the orphaned worktree changes | :56-58 | :73-75 | :55-63 (scripted) | core | |
| "If the user says no / wants changes — Treat their note as the next round of work: apply it on the same branch, re-run the local gate, and come back to this gate. Don't re-open the whole pipeline" | :60-63 | :77-80 | :65-68 | core | |
| **cc-otel.md** — dbmate/`schema.sql` mechanics; live-Postgres ladder (throwaway container → interactive only → **blocked**) | absent | absent | R/cc-otel.md:6-23 | axis:verification | Profile field: blocking prerequisites and what to do without them. |
| Metered CI push discipline — "a push only when the tree actually changed — re-running CI on unchanged code is pure spend" | absent | absent | :25-30 | axis:ci-topology | |
| Review bot answer (none installed; loop skill is the reviewer; self-review always runs) | C:109-119 | C:60-85 | :32-36 | axis:review-bot | |
| Integrated test target (testcontainers, never the shared dev DB) | C:71-73 (`live-e2e` sibling skill) | C:5 (system Chrome, `CHROME_PATH`) | :38-43 | axis:verification | |
| Claim ops (assignee is the claim; release re-enters the frontier) | C:105-107 | C:89, 92 | :45-51 | axis:claim | |
| Workflow-name → gate-group coupling; "A brand-new workflow needs a gate group or an exclusion-list entry in the same PR — otherwise the script fails loudly" | absent | absent | :53-63 | axis:local-gate | Body; principle is core (row C, statuses). |

### E. CLAUDE.md facts the skill defers to

Rows here are what "read project instructions first" actually pulls; they show what the ship profile has to carry versus what stays in CLAUDE.md.

| Item | crm | aiworx | cc-otel | Class | Notes on disagreement |
|---|---|---|---|---|---|
| Never develop in the shared main checkout; "Before **any** git mutation anywhere: `git branch --show-current && git status -sb` first, and stage with explicit paths, never `git add -A`" | C:19-28 | C:31-40 | C:24-31 | core | Identical in all three → belongs in the generic skill, not three profiles. |
| Worktree bootstrap (`PYTHONPATH` + main venv / `npm ci --omit=dev` / copy `.env.prod`) | C:28 | C:36 | C:28 | axis:worktree | |
| Test command(s) and the full CI check set | C:30-42 | C:7-25 | C:33-64 | axis:local-gate | Profile: test command from a worktree; the local gate body owns the rest. |
| Docs-sync coupled artifacts | C:54-70 | C:42-52 | C:110-119 | axis:docs-sync | |
| Release / versioning: PSR reads squash subject, "reserve `feat:` for substantial new capability" / `bump-version.js` in the PR, `version-gate.js` / none | C:77-93 | C:54-58 | absent | axis:versioning | aiworx gap: not surfaced in its ship copy. |
| Code review topology | C:109-119 | C:60-85 | R/cc-otel.md:32-36 | axis:review-bot | |
| Triage labels + `agent-working` | C:105-107 | C:92 | C:127-129 (five labels, no claim label) | axis:claim | |
| Way of working — frontier, claim first, fix-first ladder, deferrals get tickets | absent | absent | C:13-22 | axis:adjacent-finds | → decision 3. |
| "For code exploration/search, use the **`Explore`** agent … on the **haiku** model" | C:97-99 | absent | absent | drop | Already covered by the model-tier table's "Investigation / mapping → haiku". |
| Shell output-capture traps (zsh / PowerShell) | C:44-52 | absent | C:69-77 | drop | Project instructions carry them; Ship reads CLAUDE.md anyway. |
| CI shape (3-OS matrix + clean-tree + bundle + plugin jobs / path-filtered per concern) | (workflows: ci, docs, e2e, release, semantic-release) | C:23-25 | C:107, 119 | axis:ci-topology | |
| PR template present | `.github/PULL_REQUEST_TEMPLATE.md` | absent | `.github/PULL_REQUEST_TEMPLATE.md` | axis:pr-template | Detectable by the generic skill; the profile only needs to say whether to honour it. |

---

## What the fresh write must not lose — the defect-learned rails, collected

Every rail a copy describes as learned from a defect, with its home row above. All marked core except the Copilot request/read-back pair, argued as core *to the Copilot-on-request option* of the review-bot axis (it is meaningless in the other two topologies but must ship with the option, not be rediscovered by a profile author).

| Rail | Copy, source issue | Row |
|---|---|---|
| Push-access check first in pre-flight | aiworx #218 | B phase 0; C preflight |
| Closing-keyword vs mention split in pre-flight | aiworx #83 | B phase 0; C preflight |
| Release the claim on every short stop and on merge; hand back to `needs-triage` | aiworx #85 | A; C release; C merge |
| Two rejection rails: check against `origin/main`; evidence ≠ claim | aiworx #218 | B phase 4 |
| Base-fresh check in the local gate | aiworx #218 | B phase 5; C local-gate |
| A review row with no body is not a round (`substantive`) | aiworx #211 | C poll; D review-loop |
| Read the request back off the timeline; two Copilot identities | aiworx #219 | B phase 7; D review-loop (axis:review-bot, Copilot option) |
| Fast-forward the base branch from the right checkout after merge | aiworx #83 | C merge |
| Task list on a scratch file; harness task tools may be absent | aiworx #221 | D context-discipline (decision 1) |
| Write the merge summary uncompressed | cc-otel #384 | D merge-gate |
| Retry ff-pull past a transient `index.lock`; never delete the lock | cc-otel ab98cf5 | C merge |
| Local gate fails loudly on an unmapped workflow / unresolvable tool (`unavailable`), never silently passes | cc-otel #226/#235 | C local-gate (decision 4) |
| Windows-PowerShell Pester exit 3 → `deferred-to-ci`, never `pass` | cc-otel #401 | C local-gate (body; status vocabulary core) |
| Secrets regexes and exit-code mapping under unit test | cc-otel #269, #401 | C `_lib.sh` |
| `git ls-remote --exit-code` 2 is the only proof of remote deletion | cc-otel | C merge |
| Resolve the main checkout with `--git-common-dir` | cc-otel | C isolate |
| Conflicted PR → CI pending forever; rebase + re-run gate + push | all three | B phase 8 |
| Draft PRs may not trigger the review bot | all three | B phase 6 |
| Never an auto-merge flag while a review could be pending | all three | D merge-gate |
| Subagent edits must carry the worktree prefix; `git -C <main> status` clean | crm, aiworx | D implement |
| Reviewer error body with zero comments = infra failure; degraded exit, not convergence | crm, aiworx | D review-loop |
