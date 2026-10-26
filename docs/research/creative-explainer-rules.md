# Which explainer-video rules restrict and which guard

Research for [#965](https://github.com/Gharib89/skills/issues/965), under the
map [#961](https://github.com/Gharib89/skills/issues/961). Question: which of
`explainer-video`'s rules restrict creativity, and which guard a real defect?
The output is a keep, drop or reshape list for the new sibling skill, where the
agent authors every scene freely.

Sources: the skill at `skills/explainer-video/` on `main` at f0fb0888
(`SKILL.md`, `reference/`, `agents/`, `scripts/`, the tests under
`tests/explainer-video/`), ADRs 0012 to 0017, and the closed tickets #780,
#796, #797 and #813 with the tickets they cite. Each claim is labelled
**read** (read from that source) or **inferred** (my judgement from it). I ran
no render.

## Answer in brief

- **The visual grammar layer restricts and guards nothing seen in a render.**
  The closed component set, the narrative arc, the style profile's grammar
  families and bans, the tokens-only lint and the per-component caps came from
  taste, brand consistency or reasoning ahead of the motion they govern. No
  ticket names a render defect behind them (read: #780, #796, #797, #813).
- **The defect-backed core is plumbing and measurement.** Length and character
  budget, voice QC, captions, loudness, determinism and the seek-safe lint,
  layout clipping and indent, safe margin under a push-in, whole-word Arabic,
  critic batching, and support verdict reuse each trace to a run that went
  wrong or a measured probe (read: #720, #725, #783, #784, #844, #835, #905,
  #917, #947, #773, #778, #794).
- **Three guards need reshaping, not dropping, before a free scene can pass:**
  the "every digit on screen is a cited claim" rule, the "a scene with no text
  is a hard error" rule, and the critic's `invented` kind. As written they
  fail a game-show "Round 3", a pictorial metaphor beat, and a "VIP" sign on a
  club door (inferred from the code at `scripts/script/check.mjs:148-162`,
  `scripts/gates/gates.mjs:162-171`, `agents/critic.md`).

## The table

Ranked by how much each rule restricts a freely authored scene, most first.
"Defect" names the observed failure the rule prevents and where it is shown,
or "none found". Verdicts are for the new skill only; `explainer-video` stays
as it is (map #961).

| # | Rule | Where | Defect it prevents | Verdict for a free scene |
| --- | --- | --- | --- | --- |
| 1 | **Closed component vocabulary**: one JSON visual per scene, its `component` one of 17 names; `custom` (an HTML fragment) is the only way out, and carries the full lint below | `scripts/lib/visuals.mjs:515-518`, `reference/scene-file.md` | None found. Components were added as tested shortcuts; the owner rejected a closed menu on #796 ("we need to let the Agent be creative and not restrict it") (read) | **Drop.** A freely authored scene is the default unit. The components can survive as worked examples the agent may borrow from, never a set it picks from (inferred). |
| 2 | **Fixed narrative arc**: `hook, context, point..., recap, end`; over 5 minutes `section` openers each holding 2 to 5 points | `scripts/script/check.mjs:76-87`, `reference/sections.md` | None found; the house pipeline's shape, carried over in #721 (read) | **Drop the gate**, keep the arc as teaching craft. A quiz, a story with characters or a game show does not fit five roles (inferred). Chapters stay for long videos (see row 19). |
| 3 | **Scene length 12 to 30 s** (section openers 6 to 12 s) | `scripts/script/check.mjs:97-100` | None found (#721, read) | **Drop.** A 4 s punchline or a 60 s worked example is a pacing choice. Keep the total-length check (row 20) (inferred). |
| 4 | **Style profile grammar**: closed families for layout, seams, camera, type, ease, texture, with bounded knobs (seam 0.2 to 0.4 s, push scale 1.03 to 1.12, stagger 0.03 to 0.08 s), refused out of range | `scripts/lib/style.mjs:98-110, 226-270`, `reference/scene-file.md` | None found; taste (the Velocity Cut pick of #777) and brand (itworx flat) (read: #797) | **Drop.** Seams, camera moves and type motion are authored per scene. Brand style becomes an optional input (map #961) (inferred). |
| 5 | **Profile bans** (`draw`, `blur`, `camera`, `kinetic`, `3d`, component names) and their regex detection in fragments (`$()` counts as camera, `.split(" ")` as kinetic, `blur(` as blur) | `scripts/lib/allowed.mjs:12-46`, `scripts/lib/fragment.mjs:312-320` | None found; a brand's denylist (#780, #797, read). The regexes can trip on benign code (inferred) | **Drop** with the grammar. An optional brand input may carry "avoid" notes as guidance (inferred). |
| 6 | **Tokens-only lint**: a fragment may not write a literal colour (hex, `rgb()`, named) or a fixed text size; only `var(--accent)` and the seven-step `--size-*` scale | `scripts/lib/fragment.mjs:252-275`, `reference/recipes.md` | None found; brand consistency (#780, #796, read) | **Reshape**: drop the literal ban. The real defects (small text, low contrast) are already measured by the layout and contrast gates on pixels (rows 14, 16). Supply a palette and scale as a default, not a law (inferred). |
| 7 | **Fragment stands alone**: no `<script src>`, no library, no at-rules (`@media`, `@font-face`), no nested rules; 3D only through the `stack3d` component | `scripts/lib/fragment.mjs:179-180, 232-243`, `reference/recipes.md` | Partly. Libraries carry wall-clock time sources that break seeking (#774, #923, read); at-rules and nesting are a limit of the composer's scoping, not a defect (read: the lint message) | **Reshape**: let the skill ship pinned, seek-safe libraries (Three.js, an SVG path tool) the agent may load, guarded by the determinism gate. Drop the at-rule and nesting ban by scoping the scene another way (an iframe or shadow root) (inferred). |
| 8 | **No `camera` key on a rich or custom scene; at most one `emphasis` per scene; storyboard menus for component, camera, emphasis, seam** | `scripts/lib/visuals.mjs:519-527, 98-117`, `scripts/storyboard/menus.mjs` | None found (#780, #814, read) | **Drop.** The scene authors its own camera and emphasis; the storyboard approves the scene, not menu picks (inferred). |
| 9 | **Per-component caps** (code 12 lines, flow 2 to 5 steps, panels 2 or 3, list 1 to 6, diagram 5 columns of 3, compare exactly 2) | `scripts/lib/visuals.mjs:31-358`, `scripts/lib/diagram.mjs:27-67` | Fit inside a fixed layout (#727, read); the layout gate already measures fit (#796 made most caps guidance) | **Drop** with the components (inferred). |
| 10 | **Every number shown is a cited claim**: each digit run in a fragment's text, or written into `textContent`, must stand whole in an excerpt the scene cites | `scripts/script/check.mjs:148-162`, `scripts/lib/fragment.mjs:85-100`, `scripts/lib/visuals.mjs:503` | None observed in a render; preventive, extending the citation rule (#796, #830, read). Guards invented figures | **Reshape**: keep for factual numbers; let a scene declare a number decorative (a step "1", a "v2", a quiz score, "Round 3"), which the critic still judges. This is the map's open "facts traced to sources while metaphors stay free" (inferred). |
| 11 | **A scene with no text of its own in any sample is a hard error** | `scripts/gates/gates.mjs:162-171`, `scripts/gates/samples.mjs:84-91` | A probe that saw nothing reporting a pass (#718, read: the code comment) | **Reshape**: keep the probe-health intent, but test that the probe found the scene's elements, not that it found text. A pictorial beat (a sticky note falling off a fridge) has no text and is no defect (inferred). |
| 12 | **Text must be DOM**: `fillText`, `strokeText`, `TextGeometry`, `troika` refused | `scripts/lib/fragment.mjs:193-197` | The layout gate reads DOM text only, so canvas text would escape it (#813, #925, read). A gate blind spot, not a seen render defect | **Keep** for readable text, so the gates can see it; canvas and WebGL pictures stay free (inferred). |
| 13 | **Critic `invented` hard failure**: a name, number, label or claim on screen that no narration or cited excerpt states | `agents/critic.md` | Guards made-up content; no invented render shown in a ticket (read: #690 names the risk) | **Reshape**: keep for factual claims; tell the critic that a metaphor's props and signs (a bouncer, a "VIP" rope, a fridge) are staging, not claims. Otherwise a game-show scene fails (inferred). |
| 14 | **Layout gate**: readable text at least 18 px, inside a 5% safe margin, no overflow or clipping (clip-path and ancestors included), code indents kept, no two readable boxes overlapping | `scripts/lib/layout.mjs:77-132`, `reference/gates.md` | Real: flush-left code (#844), a card hard-clipped at the margin (#835), a pushed-in title past the margin (#947) (read). Size and overlap carried over from the house pipeline, no ticket (read) | **Keep.** It judges only readable text (opacity at least 0.99, outside seams and camera moves), so decorative layered type at low opacity already passes (read: `layout.mjs:43-44`). |
| 15 | **Reading-time gate**: a readable box holds 0.8 s (up to 3 words), else 0.3 s a word and 1.2 s at least; read-along lines 0.8 s whole | `scripts/gates/reading.mjs:11-12, 77-81` | Text flashed too fast to read; reasoned in #813, not seen (read) | **Keep**; it binds only readable text, so a flash meant as texture can be drawn non-readable (inferred). |
| 16 | **Contrast**: 4.5:1 body, 3:1 large | `scripts/lib/layout.mjs:124-132` | Text lost against its ground (house pipeline, read) | **Keep** (inferred: a pure defect guard). |
| 17 | **Caption band and content band**: scenes drawn inside a fixed content band (1680 by 690 or 772), captions fixed at 40 px | `scripts/render/compose.mjs:27-34` | Captions over content (inferred; no ticket) | **Reshape**: reserve the caption zone, let a scene use the rest of the frame, full bleed behind the captions included (inferred). |
| 18 | **Sound effects at most 24 a minute** | `scripts/gates/gates.mjs:229-241` | None found; taste (#723, read) | **Reshape**: drop as a gate or raise it; a game show runs on stings and buzzers (inferred). Keep loudness (row 25). |
| 19 | **Over 5 minutes, sections required** | `scripts/script/check.mjs:76-87`, `reference/sections.md` | Long renders recut whole and drift at joins; per-section cache and once-only audio mux fix it (#794, #779, read) | **Reshape**: keep chapters for long videos (caching, chapter marks, frame-grid joins); drop the 2 to 5 points per section and the 6 to 12 s opener (inferred). |
| 20 | **Length budget**: spoken characters per scene within 10% of its declared seconds; voiced total within 10% of the brief | `scripts/script/check.mjs:101-113`, `reference/voice.md` | Real: a 1-minute brief delivered 76.4 s (#720), a 14-minute brief voiced 1043 s (#783) (read) | **Keep the total**; reshape the per-scene check to follow whatever scene lengths the agent chose (inferred). |
| 21 | **No em or en dashes in the script; sentences over 25 words warn** | `scripts/script/check.mjs:320-332` | None found; house style (read) | **Keep** the dash ban (the owner's rule everywhere, no creative cost); keep the 25-word warning as a warning (inferred). |
| 22 | **Cites and the support check**: every claim sentence cites excerpts, judged `supported` or `connective`; two fix attempts then stop | `scripts/script/check.mjs:133-225`, `agents/support-checker.md` | Narration drifting from its sources (#690, read); verdict flip-flop fixed by reuse (#725, read) | **Keep**, reshaped so a character's in-scene line (a host's joke, an announcer's "Will it run?") is `[no-claim]` staging (inferred). |
| 23 | **Brief `must` and `avoid` coverage** | `scripts/script/check.mjs:280-287` | The user's must or avoid ignored (read) | **Keep** (inferred: costs no creativity). |
| 24 | **Determinism gate and the seek-safe lint**: no `Math.random`, `Date.now`, timers, `requestAnimationFrame`, `gsap.*` outside `tl`, CSS animation or transition; the peak-motion frame renders pixel-identical twice | `scripts/lib/fragment.mjs:186-230`, `scripts/gates/scene.mjs:32-38` | Real: grain keyframes that do not follow seeking (#777), raster drift under load (#905, #917), a lit scene not frame-stable on the GPU (#778) (read) | **Keep**: it is plumbing. A seeded random helper the skill supplies would free generative motion without breaking it (inferred). |
| 25 | **Loudness, captions, voice QC**: -14 LUFS plus or minus 1, peak at most -1 dBTP; caption cues at most 84 characters, in order; recall at least 0.8, precision at least 0.85, rate 7 to 18 characters a second | `scripts/gates/gates.mjs:217-222`, `scripts/gates/captions.mjs`, `scripts/voice/qc.mjs:14, 143-150` | Garbled, cut or looped voice (ADR 0016), precision rounding confusion (#725) (read) | **Keep** (inferred: no creative cost). A cast of voices needs QC per voice (map: cast and sound design). |
| 26 | **Arabic rules**: whole-word motion, no per-letter spans, `dir` on text boxes, Latin runs isolated, line height at least the ink | `scripts/lib/fragment.mjs:278-288`, `scripts/lib/layout.mjs:22-37` | Real: Chrome breaks Arabic joins under character spans (#773); ink measured per face (#704) (read) | **Keep** (inferred). |
| 27 | **Fix caps**: two fix attempts per gate, two critic rounds | `scripts/gates/gates.mjs:316-396, 528` | The critic plateaued over rounds (#652, read) | **Keep** (inferred). |
| 28 | **Critic dispatch** at most 20 at once, verdicts reused for unchanged scenes; scores advisory | `reference/gates.md` | Real: 19 of 39 dispatches refused, 31 of 39 sheets judged again (#784, read) | **Keep** (inferred). |
| 29 | **Motion recipe**: a UI change at most about 250 ms, one element moving at a time, 400 to 500 ms only for entrances | `reference/recipes.md` | None found; taste guidance (#836, read). Not enforced by any script (inferred: the inventory of the lint and gates found no such check) | **Keep as craft knowledge**, never a rule (inferred). |
| 30 | **Render estimate** warns above 5 render seconds a video second, never refuses | `reference/storyboard.md` | None found; a cost signal, its rates from the render-time research #776 (read: map #961) | **Keep** (inferred). |

## What changed since the earlier tickets

- #796 already turned prop caps into guidance and made `custom` an equal
  option, but its five hard rules (bans, tokens, cited numbers, whole-word
  Arabic, every gate) still bind every custom fragment, so a free scene meets
  rows 5, 6, 10 and 11 at once (read: #796, `fragment.mjs`).
- #813's gates all scope to **readable** text, which is what lets decorative
  type pass rows 14 and 15. The new skill can lean on that scoping instead of
  banning techniques (read: `layout.mjs:43-44`; inferred: the consequence).
- No ticket in #780, #796, #797 or #813 records a defect seen in a rendered
  frame; the render defects that exist came later, from #932, #934 and #947,
  and all sit in rows 14 and 24 (read).

## Open for the map

- How a scene marks a number or a label as staging, not a claim (rows 10, 13,
  22): the map's "facts traced to sources while metaphors stay free".
- Whether the skill ships seek-safe libraries (row 7) depends on the engine
  research (map #961: engine open).
