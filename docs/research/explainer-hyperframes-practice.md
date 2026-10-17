# How professionals make videos with HyperFrames

Research for [#772](https://github.com/Gharib89/skills/issues/772) on the
[explainer-video visuals map](https://github.com/Gharib89/skills/issues/770).
Researched 2026-10-17 against HyperFrames `main` at `2061154` (npm 0.8.169) and
`heygen-com/hyperframes-launches` at `d7ac350`.

Labels: **measured** (a command was run or a primary file read; the command or
file is named), **inferred** (my reading, no direct proof), **guess**.

## Answer

The polished HyperFrames films are HeyGen's own launch films, and their source
is public (`heygen-com/hyperframes-launches`, Apache-2.0, 608 stars; measured,
`gh api repos/heygen-com/hyperframes-launches`). What makes them look produced
is not a library feature. It is a small, repeated grammar written by hand in
GSAP on top of plain sub-compositions:

1. **Seams are velocity-matched cuts, never hard cuts or plain crossfades.**
   Two families carry almost every scene change: **zoom-through** (scale plus
   blur on the Z axis, cut at peak blur) and **cut-the-curve** (both sides move
   the same direction at the same speed, cut mid-throw). Zoom-through is named
   in 14 of the 20 project folders and cut-the-curve in 11 (measured, `grep
   -rqiE` per folder over `*.html *.md *.js`). Nobody uses HyperFrames'
   `data-transition` or `data-vfx-chain`: 0 hits (measured, same grep).
2. **Blur is a motion tool**: ramped on entries and exits in 10 of 11 and 8 of
   9 projects in the two code sweeps (measured, `grep -E "filter: ?['\"]?blur\("`
   over each project's `index.html` and `compositions/*.html`).
3. **Type moves by word, never through SplitText**: per-word spans with
   staggers of 0.025 to 0.09 s and `yPercent` mask reveals (measured, `grep
   -ohE "stagger: ?[0-9.]+"`; `SplitText` has 0 hits in any composition, only
   inside vendored `gsap.min.js`).
4. **Reveals are timed to the voice**: a cue file or a hand-aligned table puts
   each reveal on the word that names it (measured,
   `frame-md-launch-storyboard/assets/vo-timing-cues.json` drives
   `scene-02-diagnosis.html:292,304`).
5. **The process is storyboard first, contact sheet before motion**, with a
   written motion register (signature moves plus bans) and a seam ledger
   (measured, contact sheets named in 8 of 20 folders; `cloud-render-launch/design-system/frame.md`,
   `claude-design-send-hyperframes-launch/STORYBOARD.md:120-128`).

HyperFrames' own agent skills encode the same grammar as doctrine: smooth
`power3` settles over bounce, reveals in the back half of a scene on the voice
cue, no breathing or drifting camera, velocity-matched internal seams
(measured, `skills/faceless-explainer/references/motion-language.md:91-126`).

Our composer already does point 4 (each piece reveals as the sentence naming it
starts; measured, `compose.mjs:335-339`) and nothing of points 1, 2 or 3: it has
no transition, camera, blur or grain code at all (measured, `grep -rniE
"transition|camera|grain|blur\(" skills/explainer-video/scripts` returns
nothing). The highest-value adoption is the seam grammar, injected the way
HyperFrames' `faceless-explainer` does it so narration timing never moves.

## The five to show the owner

| # | Film | Why it matters to us | Video | Source |
|---|---|---|---|---|
| 1 | **HyperFrames launch** (HeyGen, 2026-04-16, 49.8 s) | Widest technique range in one film: glass-card zoom-throughs, per-word type, CSS clip-path wipes, WebGL shader, a Three.js-styled beat, footage, captions. Its STORYBOARD, SCRIPT and HANDOFF are public. 8,333 likes on X | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-hyperframes-launch-v1-s.mp4), [X post](https://x.com/HeyGen/status/2044827454460871072) | [hyperframes-launch/](https://github.com/heygen-com/hyperframes-launches/tree/main/hyperframes-launch) |
| 2 | **FRAME.md storyboard** (HeyGen, 61.3 s) | A narrated concept explainer, our format. Shows the full professional process: per-scene contact sheets before motion, a VO cue JSON that names animation events, a `#cam` wrapper camera, blur-matched seams, a session log of feedback rounds | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-frame-md-launch-storyboard-v1-s.mp4) | [frame-md-launch-storyboard/](https://github.com/heygen-com/hyperframes-launches/tree/main/frame-md-launch-storyboard) |
| 3 | **HTTP caching explainer** (HyperFrames docs, 26.2 s, 1920x1080) | The one-shot output of HyperFrames' own `/faceless-explainer` skill: a node diagram that gains a cache layer on the voice cue, keyword-highlight captions, big glowing type. The baseline an agent reaches with their doctrine, in our exact shape (16:9, narrated, diagrams) | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/prompting/variant-explainer-landscape.mp4) | prompt in [`docs/prompting/explainers.mdx:82`](https://github.com/heygen-com/hyperframes/blob/main/docs/prompting/explainers.mdx) |
| 4 | **HeyGen x Stripe** (HeyGen, 38.7 s, 4K master) | Rebuilt frame-faithful to an After Effects master, so proof that the finish is reachable in HTML. A CSS 3D rotary word drum landing on spoken verbs, typewriter step titles on gradient grounds, a speed-ramp explode, a terminal with a progress bar | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-HF-heygen-stripe-v1-s.mp4) | [HF-heygen-stripe/](https://github.com/heygen-com/hyperframes-launches/tree/main/HF-heygen-stripe) |
| 5 | **Three.js 3D cards** (HyperFrames docs, 9.0 s, 1920x1080) | The 3D path the map must decide: three lit cards with real shadows, a focus that steps card to card, a closing lockup, through the seek-safe `three` adapter. Their docs call real 3D "Three.js, a validated default" and CSS `perspective` "flat" | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/prompting/example-3d-cards.mp4) | prompt in [`docs/prompting/runtimes-and-3d.mdx:20-45`](https://github.com/heygen-com/hyperframes/blob/main/docs/prompting/runtimes-and-3d.mdx) |

Every URL above returned 200 and the lengths are from `ffprobe` (measured,
`curl -sI` and `ffprobe -show_entries format=duration` on each MP4). The
showcase MP4s are 1280x720 previews of 1080p or 4K masters (measured,
`ffprobe` stream size; the Stripe card says 4K). The X post was checked through
`cdn.syndication.twimg.com/tweet-result` (measured: 8,333 likes, 49,792 ms video).

Runners-up, if the owner wants more: **Texture launch** (21.0 s, the texture
and shader polish layer:
[MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-texture-launch-video-v1-s.mp4)),
**VFX reel** (26.6 s, Three.js GLB phone with bloom:
[MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-vfx-heygen-combined-v1-s.mp4)),
and Bin Liu's **Claude connector explainer** (54.4 s, tuned for explainers, no
public source: [X post](https://x.com/liu8in/status/2064388601354600813),
measured via the syndication endpoint: 362 likes, 54,354 ms).

## How the professionals work

All measured by reading the named files in `hyperframes-launches@d7ac350`
unless labelled.

- **Brief, then storyboard, then contact sheet, then motion.**
  `frame-md-launch-storyboard/HANDOFF.md` builds "scene by scene, as portable
  standalone pieces... Each scene gets a contact sheet (static 16:9 keyframes,
  no animation) to lock visual direction before motion". Its contact sheets
  (`scene-02-contact-sheet.html`) are one card per frame: a "Frame 2A" label, the
  beat, a static render and a note carrying the motion intent ("this is the key
  morph. Use parallax zoom, not a flat rotate"). `claude-design-send...`'s
  BRIEF makes a "design-pass contact sheet REQUIRED before comps". This is our
  storyboard-before-render rule, with one addition we lack: a per-card motion
  note.
- **A storyboard row carries the seam.** `figma-launch/STORYBOARD.md` columns:
  act, id, type, start, dur, beat, "sustained-motion route", "seam OUT".
  `claude-design-send.../STORYBOARD.md:120-128` closes with a **seam ledger**:
  cut, exit vector, entry vector, carrier element, technique, and checks "2
  families" of transition. `heygen-apple-motion` formalises it as
  `ledger.json` (axis and direction per cut).
- **A motion register sits beside the palette.**
  `cloud-render-launch/design-system/frame.md` has a "Motion Register":
  adjectives, five signature moves (type-on at about 0.045 s per character, one
  zoom-through into the window, leftward cut-the-curve) and bans ("overshoot
  beyond ~1.04", "crossfading the whole film", "idle hover-wobble").
  `claude-paper-launch/FRAME-claude.md` adds a pre-render self-audit (squint,
  silence, one accent use, one lifted plane). HyperFrames ships 13 such frame
  presets (measured, `ls skills/hyperframes-creative/frame-presets | wc -l`).
- **Voice sets the clock.** `frame-md-launch-storyboard/assets/vo-timing-cues.json`
  holds Whisper-derived labelled cues (`{time: 5.69, label:
  "scene02.zoom_out_start"}`) and the scene code uses those exact times.
  `website-to-hyperframes/STORYBOARD.md` goes to sub-second beats with ease,
  duration, camera and SFX file per beat.
- **Reference films are measured, not eyeballed.** `HF-heygen-stripe` was
  rebuilt against an After Effects master with ffmpeg scene detection, contact
  sheets and per-frame luma (`STUDY-V12-vs-TAKE6.md`); `k3-promo` comments give
  per-frame numbers "measured from ref".
- **Handoff logs carry gotchas between sessions** (every project has a
  HANDOFF or README of traps; see [Gotchas](#gotchas-the-makers-recorded)).

## Techniques, by axis

Counts come from two code sweeps over the wired compositions (each project's
`index.html` plus `compositions/*.html`): one over 11 projects, one over 9
(measured, per-project `grep -qE <pattern>`; the pattern is named).

### Transitions (the biggest lever)

- **Zoom-through**: exit scales up to about 1.2 with 14 to 20 px blur under
  `power3.in` over about 0.2 s; the swap happens at peak blur; entry comes from
  about 0.75 (or 1.25 for the inverse) with blur settling under `expo.out`
  (measured, `variables-launch/compositions/scene-05.html:119,189-191`,
  `claude-paper-launch/index.html:273-292`).
- **Cut-the-curve**: outgoing scene throws `xPercent:-13` (or `x:-200` with 8 px
  blur) under `power2.in`; the incoming scene is already sliding the same way
  and decelerates (measured, `claude-paper-launch/index.html:295-335`,
  `variables-launch/compositions/scene-02.html:124-126`).
- **Waterfall**: cut-the-curve per word across a text-to-text seam (measured,
  `variables-launch/compositions/scene-01.html:158-165`).
- **Crossfade only for soft layer changes**: the Stripe handoff records a
  "crossfade-dip law" (a crossfade darkens at its midpoint) and swaps it for a
  hard cut on a matched background (measured, `HF-heygen-stripe/HANDOFF-V7.md`
  section 2).
- **Blur scales with the subject**: 10 px peak for text, 18 to 20 px for a
  full-frame surface, applied to the wrapper, the same value on both sides of
  the cut (measured, `skills/faceless-explainer/references/cut-catalog.md`
  "Blur Logic").
- **Energy picks duration**: calm 0.5 to 0.8 s, medium (explainer) 0.3 to 0.5 s,
  high 0.15 to 0.3 s; one primary transition carries most seams and the boldest
  accent is spent once on the climax (measured, `docs/prompting/transitions.mdx:73-79`).
  For "corporate, SaaS, explainer" it names `whip-pan`, `cinematic-zoom`,
  `transitions-push`, `transitions-cover` (`transitions.mdx:32`).
- **Shader transitions are for two or three beats, not every cut** (measured,
  `docs/prompting/runtimes-and-3d.mdx:101-111`). They composite on a WebGL
  canvas (`packages/shader-transitions`), so on this machine they are GPU work
  (inferred).

### Camera

- A wrapper element is the camera: `#cam` starts at `{x:-1505, y:162,
  scale:3.5}` and eases to identity over 1.5 s with `power3.inOut` under
  `perspective:2400px` (measured, `frame-md-launch-storyboard/compositions/scene-02-diagnosis.html:20,237-240,292`).
- A seek-safe variant drives the camera through CSS custom properties read in
  `calc()` on every layer, "not in an onUpdate callback, seek-safe, every layer
  in lockstep" (measured, `claude-design-send-hyperframes-launch/compositions/s3-flyover.html:43-66`).
- The `figma-launch` "zoom ladder" climbs from 1.32 to 4.4 over nine hard cuts at
  a shortening cadence of 0.8 to 0.1 s (measured, `act2.html:196-212`).
- HyperFrames' rules name four camera moves (`multi-phase-camera`,
  `coordinate-target-zoom`, `viewport-change`, `camera-cursor-tracking`) and
  two blueprints built on them (`spatial-pan-stations`, `camera-journey`)
  (measured, `motion-language.md:35-40`, `blueprints-index.md`). Their doctrine
  bans a slow pan or push in the back half of a scene ("disrupts the viewer's
  sightline") and lazy breathing (measured, `motion-language.md:111-118`).

### Kinetic type

- Per-word spans, `yPercent:115` to 0 under a mask, `power4.out`, stagger 0.12
  (measured, `sfx-music-launch/compositions/button-spam.html:87,120`).
- Token cycles in place (a fixed line, one slot changing) and a CSS 3D rotary
  drum stepping `rotationX` by 30 degrees onto each spoken verb (measured,
  `HF-heygen-stripe/compositions/rotary.html:22-82`).
- Typewriter by `clip-path inset` with `steps(n)` or a proxy counter setting
  `textContent`, caret blinking on `steps(1)`; 10 of 11 projects (measured,
  `grep -E 'caret|steps\('`).
- HyperFrames names kinetic type moves `discrete-text-sequence`,
  `dynamic-content-sequencing`, `kinetic-beat-slam`, `hacker-flip-3d`
  (measured, `motion-language.md:13-33`).

### Layering, depth and texture

- Depth of field by blurring the off-focus subset; glass cards with
  `backdrop-filter: blur(26px) saturate(1.15)` (measured,
  `figma-launch/compositions/act1.html:36`); stacked glow at 4, 22 and 52 px
  (measured, `k3-promo/index.html:173-175`).
- Grain: an `feTurbulence` SVG data URI or a grain div with
  `mix-blend-mode:overlay`; 5 of 9 projects wired (measured, `grep -E
  'feTurbulence|grain|snoise|fbm\('`). `claude-design-send` holds the grain off
  on the seam frame and calls it "GRADE not motion" (measured, `BRIEF.md`,
  `s3-flyover.html:73-80`). The registry `grain-overlay` component is a static
  `feTurbulence` tile (measured, `registry/components/grain-overlay/grain-overlay.html:71`),
  so it is deterministic by construction (inferred).
- Edge-feathered windows with two-gradient `mask-image` and `mask-composite`
  (measured, `cloud-render-launch/compositions/opener.html:60-62`).
- A background that cues the edit: `inspector-launch` pulses its canvas
  halftone about 0.1 s before each cut (measured, `inspector-launch/DESIGN.md`,
  `index.html:2638-2644`).

### 3D

- Real WebGL in 4 of 9 projects, CSS 3D `perspective` in 4 of 9 (measured,
  `grep` for `THREE|getContext` and `perspective`). The launch film's
  "Three.js" beat is actually a CSS 3D torus (measured, `grep -c THREE
  hyperframes-launch/compositions/flex-threejs.html` returns 0).
- Real Three.js: `liquid-brand-refraction` tweens only `{time}` on the GSAP
  timeline and renders a pure `renderAt(time)` on the adapter's `hf-seek` event
  (measured, `liquid-pop-v2.js:452-565`); `vfx-heygen-combined` drives a
  `PerspectiveCamera` from a GSAP proxy object (measured, `index.html:872-886`).
  Both are GPU-heavy: a transmission material with eight video textures, and
  three WebGL contexts (inferred).
- HyperFrames' guidance: ask for Three.js through the adapter whenever depth,
  light or a camera orbit matters; CSS 3D "skews flat planes" (measured,
  `docs/prompting/runtimes-and-3d.mdx:20-45`).

### Pacing

- Seam durations of 0.2 to 0.6 s (measured, `claude-paper-launch/index.html:259-337`);
  scene lengths of 1.6 to 6.4 s in `cloud-render-launch` and 0.9 to 5.2 s in
  `pr-to-video-launch` (measured, their `data-duration` values).
- Eases: `power2.out` 205 uses, `none` 136, `power2.in` 126, `expo.out` 47
  (measured, `grep -ohE "ease: ?'[^']+'" | sort | uniq -c` over the 9-project
  set). Custom eases in 5 of 9, including a velocity-matched entry
  `t => -0.806*t*t + 1.806*t` reused across films (measured,
  `hyperframes-launch/compositions/glass-intro.html:464`,
  `vfx-heygen-combined/compositions/vfx-text-cursor.html:332`).
- The doctrine: nothing dumped in the first 25 percent of a scene; each piece
  reveals in the later 50 percent when the voice names it (measured,
  `motion-language.md:101-109`). Note the launch films break their own bounce
  rule: `back.out` appears in 13 of 20 folders (measured, `grep -rqiE
  'back\.out'`), so the doctrine is stricter than the practice.

## How it is structured in code

- One root `index.html` mounts each scene as a sub-composition
  (`data-composition-src`, `data-start`, `data-duration`, `data-track-index`);
  each composition registers one paused GSAP timeline on
  `window.__timelines[id]` (measured in 10 of 11 and all 9 projects, `grep
  data-composition-src`). Our composer has the same shape (measured,
  `compose.mjs:504`).
- **Seams live on the root timeline, not in the scenes.**
  `claude-paper-launch/index.html:259-337` holds all eight seams;
  `pr-to-video-launch/index.html:47-67` has an `xfade()` helper there.
- HyperFrames' `faceless-explainer` injects seams mechanically: it extends
  only the outgoing scene's `data-duration` by the transition length, moves no
  `data-start`, puts adjacent scenes on alternating tracks, and stamps a GSAP
  template on the main timeline at the incoming start, so "voice/SFX/captions
  [stay] synced" (measured, `skills/faceless-explainer/scripts/transitions.mjs:1-24`).
  Its vocabulary is `crossfade`, `blur-crossfade`, `push-slide`,
  `zoom-through`, `squeeze` with direction and duration modifiers.
- Deterministic by hand: no `Math.random`, `Date.now` or
  `requestAnimationFrame` in any wired composition; randomness is a seeded
  `mulberry32(1337)` (measured, `grep` per project, `k3-promo/index.html:410`).
  Lottie seeking is taken over by stepping `goToAndStop` from `onUpdate`
  (measured, `claude-paper-launch/compositions/chat-response.html:289-295`).
- The registry has 210 blocks and 238 components, including 13
  `transitions-*` CSS blocks, `grain-overlay`, `vignette`, `motion-blur`,
  `cinematic-zoom`, `flowchart` and `data-chart` (measured, `ls
  registry/blocks | wc -l`, `ls registry/components | grep -E ...`). The pros
  did not use them: every seam is hand-built (measured, `grep -rlE
  'transitions-(push|blur|cover|scale|3d|dissolve)|cinematic-zoom|grain-overlay'`
  over the launches' `*.html` returns nothing).

## Arabic and right-to-left

HyperFrames' skills and prompting docs give no right-to-left guidance for
motion or kinetic type (measured, `grep -rniE "arabic|rtl|right-to-left"
skills docs/prompting docs/guides` hits only unrelated text). Everything in the
launch films splits by word, which is the shape our Arabic rule already
requires (Arabic moves whole words, never letters). Per-character techniques
(type-on per character, `hacker-flip-3d`, letter-spaced mask boxes) break
Arabic joins and must stay Latin-only (inferred). Directional seams
(cut-the-curve left, waterfall) should mirror their x vector in a
right-to-left run, the way our flow arrows already flip (measured,
`compose.mjs:214`; the mirroring for seams is inferred). Z-axis seams
(zoom-through) are direction-neutral (inferred).

## What our composer could adopt

Ranked by visual gain per cost. All are plain GSAP on paused timelines, so
they keep the determinism gate (inferred) unless marked GPU.

1. **A seam per scene boundary**, injected on the main timeline with
   `faceless-explainer`'s extend-outgoing-only mechanics, so narration and
   caption timing never move. Start with two families: zoom-through for a
   topic change, cut-the-curve for a continuing idea; blur 10 px on text
   scenes, 18 to 20 px on full-frame cards. A style profile then picks the
   families and durations (the "transition family" field the map's schema 2
   item lists). Our scenes already sit on their own sub-compositions
   (`compose.mjs:504`), so this is root-timeline work only (inferred).
2. **A motion register in the style profile**: signature moves, one ease
   family, bans (bounce, breathing, back-half pans), copied from
   `cloud-render-launch/design-system/frame.md`. It turns "styles differ only in
   colour" into styles that differ in motion.
3. **A wrapper camera** per scene (`#cam` scale and translate, or the CSS
   custom-property form), used for one push-in or zoom-to-target on the beat
   the narration names, not as drift.
4. **Per-word kinetic type** for title and statement scenes: masked
   `yPercent` reveal with a 0.03 to 0.09 s stagger, plus an in-place token
   cycle. Works for Arabic as is.
5. **A grade layer**: static `feTurbulence` grain and a vignette over the whole
   video, held off on seam frames. Cheap, deterministic by construction
   (inferred).
6. **Motion notes on storyboard cards** and a **seam ledger** in the scene
   file, so the owner judges motion before the render (feeds the map's
   "storyboard and animatic for motion" item).
7. **3D through the `three` adapter** as a GPU-only opt-in: tween only time,
   render a pure function of it on `hf-seek`, as `liquid-brand-refraction`
   does. Whether GPU frames stay pixel-equal across runs is unmeasured here and
   is the map's gate question.

## Gotchas the makers recorded

- A sub-composition whose `timeline.duration()` is shorter than its slot is
  hidden and flashes black; the fix is a padding tween `tl.to({}, {duration:
  X}, 0)` (measured, `hyperframes-launch/HANDOFF.md:16-25`). The runtime on `main`
  still says "visibility/parity continues to derive from the live
  sub-timeline" (measured, `packages/core/src/runtime/init.ts:840-841`). Our
  scene timelines are not padded to their slot (measured,
  `compose.mjs:391-398`) and our renders pass the gates today, so either the
  scene's last frame is not affected or it is not visible (guess). Probe this
  before seams extend scene slots, since extend-outgoing-only lengthens the
  slot by design.
- "CSS filter flattens 3D", "onUpdate is frozen on snapshots/seek", a `<video>`
  without an `id` renders frozen (measured, `HF-heygen-stripe/HANDOFF-V7.md`).
- CSS 3D `rotateX` can render video layers black in capture (measured,
  `heygen-apple-motion/02-bouncy-ui/index.html:320`).
- `tl.eventCallback` is "unsupported by the render" (measured, comment at
  `claude-paper-launch/compositions/followup-type.html:346`).
- Measuring text at runtime races font loading; bake widths (measured,
  `heygen-apple-motion` READMEs).
- WebGL `ReadPixels` stalled the GPU, and six render workers ran Chrome out of
  memory around frame 780, three is safe (measured,
  `hyperframes-launch/HANDOFF.md`, `timeline-launch/HANDOFF.md`).

## Other examples found

| Film | Maker | Length | Link | Note |
|---|---|---|---|---|
| SpaceX / Grok explainer | HeyGen | 39.5 s | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-spacex-launch-v1-s.mp4) | Mostly a Grok chat UI demo; a reskin of `claude-paper-launch`, same seams |
| Website to video | HeyGen | 41.9 s | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-website-to-hyperframes-v1-s.mp4) | Sub-second beat storyboard |
| PR to video | HeyGen | 31.4 s | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-pr-to-video-launch-v1-s.mp4) | Closest code-explainer analogue |
| Timeline editor | HeyGen | 33.5 s | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-timeline-launch-v1-s.mp4) | Named seams in HANDOFF |
| K3 promo | HeyGen | 16.7 s | [MP4](https://static.heygen.ai/hyperframes-oss/docs/images/showcase/launch-k3-promo-v1-s.mp4) | Pixel replica, seeded PRNG, grade layer |
| HyperFrames Studio launch | HeyGen | 80.8 s | [X](https://x.com/HyperFrames_/status/2107149824189698558) | 4,092 likes (measured, syndication endpoint) |
| "Motion Design is solved" | Bin Liu | 24.0 s | [X](https://x.com/liu8in/status/2045391185519448574) | No source |
| @midudev demo | outside user | 18.3 s | [X](https://x.com/midudev/status/2110008983180198035) | No source |
| @yucheng59 beat-mapped film | outside user | 45.0 s | [X](https://x.com/yucheng59/status/2109637712940871996) | GSAP plus raw WebGL at 144 BPM |

The rows from the Studio launch down were found by a subagent through Exa and
the syndication endpoint; I re-measured only the Studio launch and Bin Liu's
explainer post. YouTube holds tutorials only, no polished showcase (inferred
from search). The `hyperframes.dev/viewer/<uuid>` "Watch" links in the
launches README return 404 (measured by the subagent, `curl -L`).

## Sources

- HyperFrames repo, `main` at `2061154`: `docs/examples.mdx`,
  `docs/prompting/{explainers,transitions,runtimes-and-3d,storyboards}.mdx`,
  `skills/faceless-explainer/{SKILL.md,references/motion-language.md,references/cut-catalog.md,scripts/transitions.mjs}`,
  `skills/hyperframes-animation/blueprints-index.md`, `registry/`, `ADOPTERS.md`.
- `heygen-com/hyperframes-launches` at `d7ac350`: 20 project folders, read only.
- Showcase: <https://hyperframes.heygen.com/examples> (200).
- Our composer: `skills/explainer-video/scripts/render/compose.mjs` at `c47de85`.
- Prior research not redone: `research/explainer-engines`,
  `research/explainer-effects`, `research/explainer-design-refs`.
