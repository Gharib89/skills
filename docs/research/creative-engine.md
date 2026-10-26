# Remotion or HyperFrames for freely authored scenes

Research for [#966](https://github.com/Gharib89/skills/issues/966) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.
Baseline zoomed first: [#653](https://github.com/Gharib89/skills/issues/653)
(`research/explainer-engines`), [#660](https://github.com/Gharib89/skills/issues/660)
and [ADR 0012](../adr/0012-explainer-video-composes-in-hyperframes.md),
[#771](https://github.com/Gharib89/skills/issues/771) and
[#776](https://github.com/Gharib89/skills/issues/776). Siblings read:
#965 (`research/creative-explainer-rules`), #964
(`research/creative-motion-skills`), #967 (`research/creative-threejs`).

**Answer:** author in **HyperFrames only**. On this machine the two engines
are equal on everything a free scene needs: render time, determinism, Arabic
shaping and motion range all came out level or inside each other's run-to-run
range. So the call falls to what is not level: Remotion's licence (a paid
seat for every user in a company of 4 or more, unchanged since ADR 0012) and
the fact that `explainer-video`'s plumbing and gates already run on
HyperFrames. The bar videos show what free authoring plus ambition can do.
They do not show that React is needed for it: every move they make (springs,
path draws, parallax, particles, kinetic type, sound effects) is in reach of
HTML plus GSAP, and their own code can be ported with HyperFrames'
`remotion-to-hyperframes` skill. OpenFilm (MIT, three weeks old) is a model
for the skill's stance, not a third engine.

Labels: **measured** (a command run on this machine, named), **sourced** (a
licence, doc, source file or issue, linked), **inferred** (my reasoning from
those).

## Ranked findings

1. **Licence decides the call; nothing measured offsets it.** Remotion's
   `LICENSE.md` on `main` still reads: free for "an individual", "a for-profit
   organization with up to 3 employees", non-profits and evaluation; everyone
   else "is required to obtain a Company License" (sourced,
   [LICENSE.md](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md),
   last wording change 2025-08-25, year bump 2026-01-01; measured,
   `gh api repos/remotion-dev/remotion/commits?path=LICENSE.md`). npm
   `remotion@4.0.539` declares `SEE LICENSE IN LICENSE.md` (measured,
   `npm view`). The FAQ prices it at "$25/month per person who writes Remotion
   code themselves or using agentic coding tools", contractors' "headcount
   aggregates with yours for the 4-person threshold", and building "a service
   that generates Remotion code using artificial intelligence" is allowed
   (sourced, [licence FAQ](https://www.remotion.dev/docs/license/faq)). The
   pricing page lists "Remotion for Creators", "$25/mo per seat", for "low
   volume manual video creations ... including using AI agents and Remotion
   Studio" (sourced, [remotion.pro/license](https://www.remotion.pro/license),
   read 2026-10-26). Remotion 5.0's terms are still an open PR
   ([#3750](https://github.com/remotion-dev/remotion/pull/3750), state OPEN,
   measured `gh pr view`): "an organization or team of individuals with up to
   3 people", a new ban on operating "a rendering service that allows
   end-users to bring or upload their own Remotion code", and binding Terms
   and Conditions. So ADR 0012's reason stands unchanged: a Remotion default
   is not commercial-safe, and the skill cannot know which case its user is
   in (inferred). HyperFrames 0.8.203 is Apache-2.0 (measured, `npm view
   hyperframes@0.8.203 license`; `gh api repos/heygen-com/hyperframes`).
2. **Render time is level for 2D scenes, and Remotion's default renders WebGL
   on the CPU.** Same 1920x1080 scene in both (five springing cards, an SVG
   path drawn with a dot riding it, one Egyptian Arabic and English line), five
   alternating runs per mode on a quiet machine (measured,
   `prototypes/creative-engine-probe/bench2.sh`, `bench3.sh`, `stats.sh`):

   | Length | HyperFrames 0.8.203 (auto, hardware GPU) | Remotion 4.0.539 default | Remotion `--gl=angle` |
   | --- | --- | --- | --- |
   | 10 s, 300 frames | 7.37 s (7.27 to 7.70) | 7.41 s (6.98 to 8.41) | 6.73 s (6.63 to 7.05) |
   | 60 s, 1800 frames | 23.41 s (22.57 to 24.48) | 27.76 s (27.58 to 28.17) | 23.75 s (23.06 to 23.96) |

   Wall time of the whole CLI call, bundle cached. Verdicts: at 60 s,
   HyperFrames and Remotion on ANGLE show no measurable difference (ranges
   overlap); Remotion's default is slower by about 4.3 s, taking 19 percent
   longer (ranges apart). At 10 s, Remotion on ANGLE is faster by about 0.6 s, which is
   HyperFrames' fixed setup of about 1.4 s (measured, its log line `setup
   1.4s`), so it shrinks with length (inferred). A first batch on a machine
   other sessions were loading (load average 15 to 19) ranged 7 to 16 s for
   every mode and is not used (measured, `bench.sh`). At about 0.4 s of wall
   per second of video, a 30-minute video is about 12 to 14 minutes of capture
   in either engine (inferred, linear in frames).

   Remotion's default GL is software: a still that prints
   `WEBGL_debug_renderer_info` read `ANGLE (Google, Vulkan 1.3.0 (SwiftShader
   Device (Subzero) ...)` by default and `ANGLE (NVIDIA, Vulkan 1.4.329
   (NVIDIA GeForce RTX 2070 Super with Max-Q Design ...))` with `--gl=angle`
   or `--gl=vulkan` (measured, `remotion still src/index.ts gpu`;
   `remotion gpu` itself fails here with `net::ERR_FAILED at chrome://gpu`).
   HyperFrames' auto probe picks the GPU (measured, log `beginframe capture ·
   hardware gpu`). GPU use over one 60 s render, sampled machine-wide every
   500 ms: HyperFrames mean 22 percent, peak 35, plus about 290 MiB; Remotion
   default mean 1 percent, no memory added; Remotion ANGLE mean 25 percent,
   peak 35, plus about 215 MiB (measured, `gpu-sample.sh`). Both sit far
   under 8 GB.
3. **On one identical lit Three.js scene, both engines are bit-stable on the
   GPU; #967's lead does not hold as an engine difference.** One `scene.mjs`
   (torus knot, 400 instanced boxes, a 2048 shadow map, antialias, drawn from
   `t`) is imported by a Remotion composition and bundled into a HyperFrames
   page driven by `hf-seek` (measured, `bench-lit.sh`, 4 s, 120 frames, 6
   runs each): HyperFrames hardware GPU 0 of 120 frames differ across runs;
   Remotion `--gl=angle` 0 of 120; Remotion SwiftShader 0 of 120. Time:
   HyperFrames 6.82 s (6.56 to 6.88), Remotion ANGLE 5.60 s (5.44 to 5.84),
   Remotion default 23.53 s (23.08 to 23.83), so WebGL on Remotion's default
   costs about 4 times the wall time (measured). #778's 96 to 407 differing
   frames on HyperFrames were a different scene (trails), so they point at
   that scene, not at the engine (inferred). The two engines' frames differ
   from each other on all 120 frames (measured), as #776 found across GPU
   modes: a determinism gate compares a render only with its own mode.
4. **2D determinism: HyperFrames held under load; Remotion ANGLE did not
   quite.** Frame hashes (`ffmpeg -f framemd5`) across 10 runs of the 10 s
   scene and 8 of the 60 s: HyperFrames 0 differing frames in every run;
   Remotion default 0; Remotion ANGLE 0 at 60 s, but at 10 s the two runs made
   under heavy load differed from the eight quiet ones on frames 52 to 54
   (the path draw), at 85 dB PSNR, so a few pixels one level apart (measured,
   `determinism.sh`, `compare-all.sh`). Invisible, but it fails an
   equal-pixels gate like `explainer-video`'s (inferred). Two runs is a thin
   sample.
5. **Egyptian Arabic shapes identically in both; the craft knowledge lives
   only in Remotion's skill.** The line `الـ hook بيوقف rm -rf قبل ما يتنفذ`
   with `dir="rtl"` on the element, IBM Plex Sans Arabic loaded locally,
   rendered joined, in the same bidi order, `rm -rf` kept as one run, in both
   engines (measured, frame at 8 s of each render, viewed side by side).
   Per-letter kinetic type is the real hazard: splitting into
   `inline-block` letters with `Array.from` breaks every join, and the
   zero-width-joiner split from Remotion's `remotion-markup/arabic-text.md`
   (added 2026-10-19 per #964) restores them; the same function ported to a
   HyperFrames page joins correctly there too (measured, `hf-letters`,
   `hyperframes snapshot --at 1.5`). HyperFrames' repo has no Arabic guidance
   beyond a font preset (measured, `gh search code --repo
   heygen-com/hyperframes arabic`: three hits, none on text animation). So
   the skill writes that technique as its own text (#964 says the same).
6. **Authoring a free scene costs about the same; the hazards differ.**
   Remotion: 66 lines of TSX plus a 3-line entry and a 12-line root, `spring()`
   and `@remotion/paths` built in. HyperFrames: one 77-line HTML file, but a
   damped spring had to be written by hand as a GSAP ease (12 lines; GSAP has
   none), and `hyperframes lint` passed it first time (measured, `wc -l`, the
   probe). Hazards (sourced): Remotion flickers on CSS `transition`,
   `@keyframes` and `setTimeout`
   ([css-animations](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/troubleshooting/css-animations.mdx)),
   needs `random()` not `Math.random()`, and `@remotion/three` advances R3F on
   `performance.now()`, so drei's time-driven helpers differ on every frame
   (#967, measured there). HyperFrames forbids wall clock, unseeded randomness
   and mid-render fetches
   ([determinism](https://github.com/heygen-com/hyperframes/blob/main/docs/concepts/determinism.mdx)),
   but seeks CSS `@keyframes`, WAAPI, Lottie, anime.js and Three.js itself
   ([runtimes](https://github.com/heygen-com/hyperframes/blob/main/skills/hyperframes/references/runtimes.md)),
   so more of an agent's web habits survive (inferred). Install: Remotion's
   probe took 497 MB of packages plus a 236 MB Chrome; HyperFrames 112 MB plus
   its cached Chrome (measured, `du -sh`).
7. **Motion range does not separate them.** Remotion ships `@remotion/three`,
   `lottie`, `noise`, `paths`, `shapes`, `transitions`, `motion-blur`,
   `effects` (light leaks), `sfx`, `captions`, `rive`, `skia`, and now
   `@remotion/gsap` (a `useGsapTimeline` hook), so GSAP code runs in both
   (sourced, `packages/` on `main`, measured `gh api`; ctx7
   `/remotion-dev/remotion`). HyperFrames seeks GSAP, CSS, WAAPI, Lottie,
   anime.js, Three.js and canvas, and has shader transitions and a WebGL2
   `data-vfx-chain` (sourced, runtimes reference; #771). Neither reaches
   hardware WebGPU here (#967, measured there).
8. **Audio and captions do not separate them.** Both place audio on the frame
   timeline and mix it with FFmpeg at encode; Remotion has `@remotion/captions`
   and whisper packages, HyperFrames `transcribe` (Parakeet or whisper.cpp,
   SRT or VTT) (sourced, ctx7 docs of each). `explainer-video` already owns
   its narration, word timing, Arabic alignment and captions on HyperFrames
   (sourced, `skills/explainer-video/`), which is #971's subject.

## What the bar videos change

Both bar videos are Remotion, made by Claude Code with no video skill (map
#961). They change the reason for the engine call, not the call:

- They show that Claude Code authors ambitious free scenes when nothing
  constrains it. #965 traced `explainer-video`'s flatness to its closed
  component vocabulary, fixed arc and style grammar, not to HyperFrames
  (sourced, #965's answer). So the engine is not what made them better
  (inferred).
- Every technique in them is measured or sourced in HyperFrames: springs and
  path draws (measured, this probe), parallax as layered transforms and seeded
  particles (sourced, HyperFrames'
  [runtimes and 3D prompting page](https://github.com/heygen-com/hyperframes/blob/main/docs/prompting/runtimes-and-3d.mdx)
  asks for "a seeded random layout"),
  kinetic type (measured, `hf-letters`), sound effects as audio clips
  (sourced).
- If the owner wants to reuse their code, HyperFrames' `remotion-to-hyperframes`
  skill translates most Remotion to HTML plus GSAP and checks it frame by
  frame, and refuses `useState`, `useReducer`, effects with dependencies and
  React UI kits (sourced,
  [SKILL.md](https://github.com/heygen-com/hyperframes/blob/main/skills/remotion-to-hyperframes/SKILL.md)).
  Their source was not available to this ticket, so how much of it translates
  was not measured.
- Remotion's larger React and Remotion corpus may help a model's first draft
  (inferred, unmeasured); #970's three-arm comparison is where that would
  show.

## OpenFilm, a third candidate

[OpenFilm](https://github.com/openfilm/openfilm) is MIT (measured, `gh api`),
`openfilm@0.2.5` on npm with `playwright-core` as its one dependency
(measured, `npm view`). A film is one `film.html` of tracks; each shot is a
page exposing `window.film.frame(t)`, "the same `t` always draws the same
picture", and `look` draws each sheet frame twice in shuffled orders to name
any that changed (sourced, README). It renders through Playwright's headless
shell with GPU flags it picks per platform (sourced, `src/host.mjs`).

It does not win the call (inferred): the repo was created 2026-10-04, 0.2.x,
one author made 90 of its 170 commits (measured, `gh api
.../contributors` and `.../commits`); `explainer-video`'s plumbing would have to be rebuilt on
it; and its `frame(t)` contract is what HyperFrames already hosts through
`hf-seek` (the lit probe above draws exactly that way). What to take from it
is #964's point: the outcome-only skill shape for the ambition stance, and its
double-draw shuffle check as a gate idea for #972. Not probed: render time,
determinism, Arabic, telemetry (`telemetry` appears in its desktop app's
files; not read).

## What changed since the baseline

- **ADR 0012 holds** for the new skill: same licence text, same engine
  verdict, now with like-for-like numbers #653 lacked (its lab throughputs
  were not like for like).
- **#653 said Remotion "rendered fastest in the lab".** Like for like it is
  level on ANGLE and slower on its default (finding 2).
- **#653 and #774 named `angle-egl` or `angle` for Remotion 3D on Linux.**
  `angle` reaches the NVIDIA GPU through Vulkan (measured here and in #967);
  `angle-egl` fails to create a context (#967). Remotion 5.0 makes `angle`
  the default (sourced, docs `open-gl.mdx`, via ctx7).
- **#653 thin item "no mixed Egyptian Arabic and English line rendered in
  Remotion"**: now rendered, identical to HyperFrames (finding 5).
- **HyperFrames cut its skills from 21 to 7** on 2026-10-21 (upstream PR
  #5651, per #964); the repo's `skills/` now lists `figma`, `hyperframes`,
  `hyperframes-cli`, `hyperframes-registry`, `media-use`,
  `remotion-to-hyperframes`, `slideshow` (measured, `gh api`). Remotion ships
  12 skills under `packages/skills/skills` plus Claude Code and Codex plugins
  (measured, `gh api`).
- **Versions**: HyperFrames 0.8.203 and Remotion 4.0.539 are both
  2026-10-26 releases (measured, `gh api .../releases/latest`).
  `explainer-video` pins HyperFrames 0.8.169 (sourced, its `package.json`).

## Recommendation

1. **One engine, HyperFrames**, at a pin the new skill shares with
   `explainer-video` if #971 picks shared plumbing. Not "both": a Remotion
   backend doubles every gate, caption layer and render path for an engine
   most company users must pay for (inferred).
2. **Write the free-authoring hazards as the skill's own knowledge**, not a
   menu: seeded randomness, no wall clock, `dir="rtl"` on text elements,
   word-level Arabic motion, the ZWJ split for per-letter motion, and a spring
   helper (GSAP has none).
3. **Keep the determinism gate per GPU mode** and record the mode with the
   render (#776 and finding 3).
4. **Leave Remotion out of v1.** If a user who holds a licence wants it
   later, it is a separate slice with a licence notice at selection, as ADR
   0012 says.

## Thin

- Bar video source was not available, so their port cost via
  `remotion-to-hyperframes` was not measured.
- Remotion's ANGLE 2D wobble rests on two loaded runs out of ten.
- GPU samples are machine-wide; other sessions shared the GPU at times.
- Model authoring quality per engine is unmeasured (#970).
- OpenFilm was read, not run.

## Probe

`prototypes/creative-engine-probe/`: the Remotion project (`remotion/`), the
HyperFrames pages (`hf/`, `hf-letters/`, `hflit/`), the shared lit scene
(`lit/scene.mjs`) and the timing and hash scripts. Not committed: the font
(IBM Plex Sans Arabic Bold, copied to `remotion/public/arabic.ttf` and each
HyperFrames page's `assets/arabic.ttf`), `gsap.min.js` (copied from
`node_modules/gsap/dist/` into `assets/`, never vendored, per #660), the
`hflit` bundle (`esbuild lit/scene.mjs --bundle --format=iife
--global-name=LitScene --outfile=hflit/assets/scene.js`), and `hf60/`, which
is `hf/` with `data-duration="60"` and the timeline end at 60.
