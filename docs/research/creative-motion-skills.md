# Motion video skills available now

Research for [#964](https://github.com/Gharib89/skills/issues/964) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.
Builds on [#775](https://github.com/Gharib89/skills/issues/775)
(`research/explainer-motion-tools`, `docs/research/explainer-motion-tools.md`,
dated 2026-10-17) and reports what moved in the nine days since. Runtimes and
asset sources from #775 are not repeated; only skills are re-surveyed.

Labels: **measured** (a command was run, named inline), **sourced** (a primary
source says so: the skill file, the upstream PR, the licence text),
**inferred** (my reading, no direct proof).

Licences come from GitHub's licence detection on each repo's LICENSE file
(`gh api repos/<o>/<r> --jq .license.spdx_id`) plus a listing of the repo root
for LICENSE or COPYING files; where detection said NOASSERTION or none, the
LICENSE file was read in full. A repo with no LICENSE file is all rights
reserved. "Last commit" is the newest commit touching the skill's folder
(`gh api 'repos/<o>/<r>/commits?path=<skill path>&per_page=1'`).

## Answer

Ranked by how much each finding changes the new skill's design.

1. **HyperFrames' own `hyperframes` skill is now a creative-direction skill,
   and it is already pinned in this repo.** On 2026-10-21 upstream cut its
   pack from 21 skills to 7 and rewrote them as knowledge with no process
   (sourced: heygen-com/hyperframes PR #5651, merged 2026-10-21). The
   `hyperframes` entry this repo pins at `683e9b1` (sourced:
   `skills-lock.json`, commit `38ca7da0`) now carries an ambition stance
   (`references/story.md`: three storylines that are three different films,
   built from a device table and a form table, "make one of the three the bold
   one"), adjectives turned into numbers with a growing BANNED list of
   generated-film defaults (`references/spec.md`), a stills storyboard the
   person approves before animation (`references/storyboard.md`), a harsh
   review pass with P0/P1/P2 notes, a "describe each frame as a stranger would"
   test and a fresh-eyes sub-agent (`references/review.md`), and sound,
   explainer and character craft (`references/sound.md`,
   `references/types/explainer.md`, `references/types/character.md`) (sourced:
   read at the pinned ref). Its CLI measures craft too: `check` warns on
   `line_unread`, `dead_stretch`, `text_below_floor`, `first_frame_empty` and
   `film_silent` (sourced: `references/review.md`). If #966 picks HyperFrames,
   the new skill composes `hyperframes` and writes only what it lacks
   (teaching-first long form, chapters, Arabic, own voice, a cast, the gates)
   instead of re-teaching story, spec, storyboard and review (inferred).
2. **Upstream measured that knowledge without process beats a workflow
   skill.** PR #5651's terminal eval (Sonnet, 19 cases x 2) moved "CLI and
   tools used right" from 13% to 79% and required steps from 65% to 93%, at
   lower cost per run, while a blind frame judge barely moved (6.9 to 7.1)
   (sourced: PR #5651 body; not re-run here). Its stated reason, "strong coding
   agents plan, sequence and check their own work; what they lack are private
   facts", is the map's own "maximum freedom" premise, from the engine's
   authors (inferred).
3. **The upstream craft bans what both bar videos did.** `spec.md` bans by
   default "glow, bloom ... floating particles as decoration" and a dark void
   ground; `sound.md` and `media-use` say "no synthesised tones" and "do not
   spend the run ... writing music in code" (sourced). The ship explainer's
   particle parallax and the game show's synthesised 116 BPM bed (#962) both
   break these. Barty-Bart's `sound-effects` skill says the same ("never
   synthesize music or sound effects in code") (sourced). So composing
   `hyperframes` widens the plumbing but restricts the look and the sound; the
   new skill has to say which upstream defaults its ambition stance overrides
   (inferred). The BANNED list itself allows an exception "when the person's
   reference uses it" (sourced), which the bar videos could serve as.
4. **OpenFilm is a new, MIT, outcome-only model of the ambition stance, and a
   third engine #775 missed.** `openfilm/openfilm` (repo created 2026-10-04,
   npm `openfilm` 0.2.5, MIT; measured: `gh api`, `npm view`) ships ten
   35-line skills shaped "What has to be true / What you have / With the
   person". `motion-graphics` says "Surprise us; the expected version is not
   the goal", "nothing in it could be moved into another company's film", and
   offers "anything you can make pictures and motion with ... Blender or any
   renderer whose output becomes a clip"; `whiteboard` requires each mark to
   start when the voice says it and to "report how close it is" (sourced: skill
   files, last commit 2026-10-18). Its engine contract is one function,
   `frame(t)`, per shot (sourced: README). This is the closest existing text to
   the map's "stance plus craft plus gates" shape; borrow the shape, and hand
   the engine to #966 (inferred).
5. **#775's vendoring plan is void.** `hyperframes-core`, `-animation` and
   `-keyframes` are retired upstream; this repo already replaced them with
   `hyperframes` and `hyperframes-cli` (sourced: commit `08fb422e`, #951).
   The skills.sh index still lists the retired names at 0.75M to 1.0M installs
   (measured: `npx skills find hyperframes`), and this machine's global skill
   lock still names ten HyperFrames skills whose folders are gone (measured:
   `jq` over the lock, `ls`). Installing by a retired name misses (sourced:
   PR #5651, `skills update <retired name>` says where the knowledge moved).
6. **Remotion's skills split into twelve and gained an Arabic rule.**
   `remotion-dev/skills` now publishes `remotion-create`, `-markup`,
   `-captions`, `-render` and seven more beside the `remotion-best-practices`
   router (measured: repo tree; `npx skills find remotion`). New on 2026-10-19,
   `remotion-markup/arabic-text.md` teaches `dir="rtl"` on the container,
   word-level animation, and a per-letter split that keeps harakat with their
   letter, lam-alef as one unit, and zero-width joiners so split letters still
   join (sourced: file read; measured: commit log). The technique is plain
   browser text, so it ports to any engine (inferred). The repo still has no
   licence and Remotion's own licence needs a company licence for a for-profit
   organisation over 3 employees (measured: `gh api`; sourced: Remotion
   `LICENSE.md`), so the idea is borrowable, the text is not. The copy
   installed globally here dates from 2026-10-01 and lacks `arabic-text.md`
   (measured: lock `installedAt`, `ls`).
7. **Sound now has skills; most route to paid services.** HyperFrames'
   `media-use` (Apache-2.0) bundles 19 Pixabay-licence effects (measured: repo
   tree; sourced: `CREDITS.md`), local Kokoro TTS and a MusicGen fallback; but
   MusicGen-small's weights are CC-BY-NC-4.0 (measured:
   `curl huggingface.co/api/models/facebook/musicgen-small`), so its local
   music is non-commercial (inferred). Barty-Bart `sound-effects` (MIT,
   2026-10-13) is the best measured sound pass found: a cue list, a beat grid
   checked against the kicks, a CC0 bundled kit, a per-run licence check, and
   five timestamps for a human to hear, because "Claude can't hear" (sourced).
   ElevenLabs (`elevenlabs/skills`, MIT, 2026-10-22) and Sonilo
   (`sonilo-ai/skills`, MIT) are API skills that need keys and credits
   (sourced). For a cast, borrow Barty-Bart's measured pass; keep paid
   providers optional (inferred).
8. **Teaching craft to borrow, not compose.** Manim skills are the
   teaching-first set: `browser-use/video-use` `manim-video` ("geometry before
   algebra", opacity layers at 1.0, 0.4 and 0.15, name the aha moment first;
   MIT, last commit 2026-04-12) and `adithya-s-k/manim_skill` `manim-composer`
   (research, then a `scenes.md` plan; MIT, 2026-01-22) (sourced). HyperFrames'
   `remotion-to-hyperframes` now imports Manim, Blender and After Effects
   renders as media clips (sourced: skill file), so a Manim-drawn derivation can
   sit inside either engine's video (inferred). `calesthio`
   `d3-animated-data-visualization` (MIT) is the only third-party chart skill
   that is explicitly deterministic (measured: grep for seek, deterministic,
   seed: 8 hits); charts go to #968.
9. **Style-recipe skills restrict.** `charlie947/motion-graphics-skills`
   (MIT, 2026-10-11: `vox-explainer`, `apple-launch-film`, `motion-effects`),
   `iart-ai/explainer-video-skills` (MIT, 2026-06-22: `whiteboard-animation`,
   `isometric-animation`, `diagram-animation`), Barty-Bart's `explainer-*`
   and Higgsfield's `video-explainer` each fix one look or one pipeline
   (sourced: skill files). Their review rules are worth lifting (charlie947's
   "if the first 3 seconds would not stop your own thumb, rebuild them";
   its 8-part brief with "The bar", "Never" and "Before you finish") but
   composing any of them would impose its style (inferred).
10. **Licence changes since #775.** `CloudAI-X/threejs-skills` added an MIT
    LICENSE on 2026-10-18 (measured: commit log) but still animates from
    `THREE.Clock` and `requestAnimationFrame` (measured: 15 hits in
    `threejs-animation`, 1 for seek or deterministic), so licence no longer
    blocks borrowing and determinism still does. New skips: `mirage-hq/Tesseract`
    (proprietary terms with a revenue threshold; LICENSE read),
    `MiniMax-AI/MiniMax-H3` and `vibe-motion/skills` (no LICENSE), OpenMontage
    (still AGPL-3.0).

## What changed since #775

| #775 said | Now | Basis |
|---|---|---|
| Vendor `hyperframes-core`, `-animation`, `-keyframes` maintainer-side | Retired upstream 2026-10-21; repo pins `hyperframes` + `hyperframes-cli` at `683e9b1` | sourced: PR #5651, commits `08fb422e`, `38ca7da0` |
| Don't compose the `hyperframes` router: it steals triggers | The router is now the knowledge skill (contract, story, spec, storyboard, review, sound); the trigger risk stays for `explainer-video`, but a sibling that composes it gains its craft | sourced; inferred |
| Whole-video skills (faceless-explainer, motion-graphics, general-video) to borrow from | Retired; their facts moved into `references/film.md` | sourced: PR #5651 |
| 21 HyperFrames skills | 7: `hyperframes`, `hyperframes-cli`, `hyperframes-registry`, `media-use`, `figma`, `slideshow`, `remotion-to-hyperframes`; release v0.8.203 on 2026-10-26 | measured: `gh api .../contents/skills`, `.../releases/latest` |
| `remotion-best-practices` only | Twelve Remotion skills; new `arabic-text.md`; repo still unlicensed | measured: tree, commit log |
| CloudAI-X Three.js: no licence | MIT since 2026-10-18; still wall-clock | measured |
| Not covered | OpenFilm (MIT, outcome-only skills, `frame(t)` engine) | measured, sourced |
| Not covered | Sound skills: `media-use`, Barty-Bart `sound-effects`, ElevenLabs, Sonilo | sourced |
| Not covered | Manim teaching skills and `remotion-to-hyperframes` media import | sourced |

## Skill inventory

Installs from `npx -y skills find <q>` for remotion, hyperframes, motion
graphics, kinetic typography, explainer video, video, animation, manim, sound
design, sound effects, music, chart animation, data visualization video,
three.js, 3d animation, storyboard, motion design, lottie, gsap, video
editing, motion canvas, rive, voiceover and whiteboard animation (measured,
2026-10-26; counts drift daily). No Rive skill exists; the query returns only
`rivet-dev` hits (measured).

| Skill (source) | Teaches | Licence | Last commit | Installs | Restricts or widens | Verdict |
|---|---|---|---|---|---|---|
| `hyperframes` (heygen-com/hyperframes) | Render contract, story, spec, storyboard, review, sound, video types | Apache-2.0 | 2026-10-25 | 1.2M | Widens plumbing and craft; restricts look and sound by its BANNED defaults | Compose if #966 picks HyperFrames (already pinned) |
| `hyperframes-cli` (same) | CLI by job, `check`, `snapshot --review`, `audio`, `beats` | Apache-2.0 | 2026-10-25 | 1.3M | Widens (measured gates) | Compose with `hyperframes` |
| `media-use` (same) | Media by `resolve`; HeyGen or free local; 19 bundled SFX | Apache-2.0; SFX Pixabay licence | 2026-10-25 | 1.1M | Widens; pushes HeyGen sign-in first | Borrow the SFX kit idea; voice stays ours |
| `remotion-to-hyperframes` (same) | Port Remotion; import Manim, Blender, AE renders as clips | Apache-2.0 | 2026-10-25 | 510K | Widens | Use if the bar videos' code is reused |
| `remotion-best-practices` and 11 siblings (remotion-dev/skills) | Remotion API rules, Arabic text, captions, maps, 3D | None (Remotion License upstream) | 2026-10-26 | 684K | Neutral: API facts | Borrow ideas; compose only if #966 picks Remotion |
| OpenFilm skills (openfilm/openfilm) | Outcome criteria per film kind; any tool allowed | MIT | 2026-10-18 | 2.8K | Widens | Borrow the shape for the ambition stance |
| `sound-effects` (Barty-Bart/motion-graphics) | Measured sound pass, CC0 kit, licence check | MIT (plus OFL fonts) | 2026-10-13 | 917 | Restricts (no synthesis) | Borrow method |
| `explainer-engaging`, `-high-energy`, `-default` (same) | One-shot product explainers, one style each | MIT | 2026-10-12 | 830 to 840 | Restricts | Borrow review rules |
| `vox-explainer`, `motion-prompt-writer` and 13 more (charlie947/motion-graphics-skills) | Style recipes, 8-part motion brief | MIT | 2026-10-11 | 1.5K | Restricts | Borrow review rules |
| `manim-video` (browser-use/video-use) | Teaching-first Manim pipeline | MIT | 2026-04-12 | 179 | Widens (new medium) | Borrow teaching craft |
| `manim-composer`, `manimce-best-practices` (adithya-s-k/manim_skill) | Concept to `scenes.md`; Manim API | MIT | 2026-01-22 | 2.6K, 3.9K | Neutral | Borrow planning |
| `whiteboard-animation`, `diagram-animation`, `isometric-animation` (iart-ai/explainer-video-skills) | One explainer style each | MIT | 2026-06-22 | 1.5K | Restricts | Borrow technique |
| `chart-animation` (iart-ai/data-animation-skills) | Chart races, counters | MIT | 2026-06-22 | 1.3K | Neutral | Hand to #968 |
| `d3-animated-data-visualization`, `sound-design-foley`, `motion-graphics-direction` (calesthio/generative-media-skills) | Deterministic D3 charts; foley; MG direction | MIT | 2026-07-14 | 100 to 210 | Neutral | Borrow; charts to #968 |
| `higgsfield-video-explainer` (higgsfield-ai/skills) | Generative 10 s blocks, one style key, paid credits | MIT | 2026-09-26 | 124K | Restricts | Skip |
| `sound-effects`, `music`, `text-to-speech` (elevenlabs/skills) | ElevenLabs API calls | MIT | 2026-10-22 | 11K to 17K | Widens if keyed | Optional provider |
| Sonilo skills (sonilo-ai/skills) | Video-to-SFX, music, ducking via API | MIT | 2026-09-25 | 1.4K | Widens if keyed | Optional provider |
| `design-taste-frontend` (Leonxlnx/taste-skill) | Anti-slop art direction for web pages | MIT | 2026-10-24 | not listed | Restricts (house style) | Skip: web pages |
| `impeccable` (pbakaus/impeccable) | UI design and motion craft | Apache-2.0 | 2026-10-26 (repo push) | 362K | Neutral | Already a map consult skill |
| `threejs-*` (CloudAI-X/threejs-skills) | Three.js on a live clock | MIT since 2026-10-18 | 2026-10-19 | 12K to 20K | Wall-clock | Borrow API facts only; 3D to #967 |
| Tesseract (mirage-hq) | Proprietary render engine plugin | Proprietary terms | 2026-10-23 | 3K | n/a | Skip |
| MiniMax-H3, vibe-motion | Generative and Disney-rule skills | None | 2026-08, 2026-10 | 650 to 3.4K | n/a | Skip |
| OpenMontage (calesthio) | Whole pipeline | AGPL-3.0 | 2026-10-24 | 1.1K | n/a | Skip |

## Recommendation for the spec

- Let #966 decide the engine; then compose that engine's own skill
  (`hyperframes` plus `hyperframes-cli`, already pinned, or the Remotion
  skills) and keep the new skill's text to what the engine skill lacks:
  teaching-first long form in chapters, the cast and own-voice plumbing,
  Arabic, the gate set (#972), and the ambition stance.
- Write the ambition stance in OpenFilm's outcome shape (what has to be true,
  what you have, what you tell the person), not as a process.
- Name, in the stance, which upstream defaults the new skill overrides
  (particles and dark grounds when the idea needs them; a synthesised bed when
  the format calls for one), so a composed `hyperframes` does not quietly
  forbid the bar videos' moves.
- Port Remotion's Arabic technique (RTL base, word-level motion, ZWJ
  per-letter split) as our own text; it is an idea, not copyable prose.
- Take Barty-Bart's measured sound pass (cue list, beat grid, human listen
  points, licence ledger) as the model for cast and sound plumbing; keep
  ElevenLabs, Sonilo and HeyGen as optional keyed providers; do not ship
  MusicGen output without flagging its non-commercial weights.
- Refresh this machine's global skill lock (stale HyperFrames entries, an
  old `remotion-best-practices`) before the three-arm comparison (#970), so
  the "no skill" and "Remotion" arms load current text.

## Thin

- PR #5651's eval numbers are upstream's own and were not re-run.
- Skill bodies were read for the top candidates only; for the rest, the
  description and a grep for determinism words stand in.
- Install counts drift daily and include stale index entries.
- Whether Kokoro (`media-use`'s free voice) speaks Arabic was not checked;
  `explainer-video`'s own voice plumbing is #971's subject.
- OpenFilm's `MANUAL.md` (printed by `npx openfilm`) was not executed or read
  in full; its engine claims are from the README only.
