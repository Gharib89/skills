# Effects and animation techniques for explainer-video

Research for [#657](https://github.com/Gharib89/skills/issues/657) on the
[explainer-video map](https://github.com/Gharib89/skills/issues/651).

Labels: **measured** (a command was run, named inline), **documented** (a
primary source says so, linked), **inferred** (my reading, no direct proof).

## Answer

An explainer reads as produced when its motion is **caused** (things move
because the narration names them, and on the beat), **continuous** (scenes hand
over through a transition or a camera move instead of a hard cut) and has a
**material layer** (grain, light, blur, depth) that a template lacks. All of it
is reachable in Remotion with commercial-safe, first-party packages, at the
condition that the expensive layers (3D, multi-sample motion blur, WebGL
effects) are opt-in per style profile and pre-rendered or cached.

1. **Remotion carries the most built-in technique**: 20 transition
   presentations, 73 WebGL2 canvas effects, camera motion blur, R3F 3D, Lottie
   and a GSAP bridge, all first-party at 4.0.535 (measured: `grep` over each
   package's `exports` in `video-lab/remotion-markup/node_modules/@remotion`).
   Its licence is free only for individuals and companies of up to 3 people
   (documented: `node_modules/remotion/LICENSE.md`); this is the one
   commercial-safety caveat in the stack.
2. **HyperFrames is the closest rival** (Apache-2.0): GSAP by default, Three.js
   and Lottie through frame adapters, 14 WebGL shader transitions, and a
   registry of 210 blocks and 238 components (measured: `ls registry/blocks |
   wc -l` in the vendored repo). It rendered 60 s of 1080p in 94 s on this
   machine (measured: `out/render.log`).
3. **Motion Canvas and Manim are narrower**: both MIT, both have a camera,
   eases and transforms; Motion Canvas has node shaders, Manim has the best
   maths transforms. Neither has motion blur, Lottie or a transition library to
   match Remotion's, and Motion Canvas has not released since v3.17.2 on
   2024-12-14 (measured: `gh api repos/motion-canvas/motion-canvas/releases/latest`).
4. **Licences that bite**: Shadertoy code (default CC BY-NC-SA, see Thin),
   LYGIA shaders (Prosperity 3.0, non-commercial after a 30-day trial) and
   anything2explainer's code (PolyForm Noncommercial) cannot ship in a
   commercial-safe default. gl-transitions (all 125 MIT or BSD), GSAP (free
   standard licence), lottie-web, Three.js, pmndrs/postprocessing can.
5. **Render cost is set by three things**: samples (motion blur multiplies
   frame renders), GPU-bound CSS and WebGL in headless Chrome, and 3D. The lab's
   fix for 3D was to cache it: motioncraft pre-rendered its 3D layer to PNG
   frames on software GL and composited them (measured: `mc-cache/*/manifest.json`).

## Engines and libraries at a glance

| Library | Licence | Version | Role in effects | Source |
|---|---|---|---|---|
| Remotion core, `@remotion/transitions`, `@remotion/effects`, `@remotion/lottie` | Remotion License: free for individuals, non-profits and for-profits with up to 3 employees; company licence above that. 5.0 will count contractors too | 4.0.535 | Engine, transitions, WebGL effects, Lottie | documented: `remotion/LICENSE.md`; [PR 3750](https://github.com/remotion-dev/remotion/pull/3750) (open); transitions and effects say `UNLICENSED` in `package.json`, so the root licence applies (inferred) |
| `@remotion/motion-blur`, `@remotion/three`, `@remotion/gsap`, `@remotion/paths`, `@remotion/rough-notation` | MIT (package field) | 4.0.535 | Blur, R3F 3D, GSAP seek, path draw, hand-drawn marks | measured: `npm view <pkg> license` |
| HyperFrames | Apache-2.0 | 0.8.160 (2026-10-15) | HTML engine, GSAP default, shader transitions | measured: `gh api repos/heygen-com/hyperframes`, vendored `LICENSE` |
| Motion Canvas | MIT | 3.17.2 (2024-12-14) | Generator-timed vector scenes, camera, node shaders | measured: `gh api` releases, `npm view` |
| Manim Community | MIT | 0.22.0 (2026-10-08) | Maths transforms, moving camera, 3D scenes | measured: `gh api repos/ManimCommunity/manim` |
| Three.js | MIT | n/a | 3D, particles (Points), shaders | measured: `gh api repos/mrdoob/three.js` |
| pmndrs/postprocessing, drei | Zlib, MIT | n/a | Bloom, DOF, film grain for Three.js | measured: `gh api repos/pmndrs/...` |
| GSAP (incl. SplitText, MorphSVG, DrawSVG, MotionPath) | Webflow "standard no charge" licence, commercial use allowed; banned only in no-code visual animation builders that compete with Webflow; "AI-generated code is not a Prohibited Use" | 3.15.0 | Easing, timelines, kinetic type, SVG morph and draw | documented: [gsap.com/standard-license](https://gsap.com/standard-license); measured: `npm view gsap license` |
| anime.js | MIT | n/a | Easing and timelines (alternative to GSAP) | measured: `gh api repos/juliangarnier/anime` |
| lottie-web, dotlottie-web | MIT | 5.13.0 | Lottie playback | measured: `gh api`, `npm view lottie-web` |
| LottieFiles free animations | Lottie Simple License: commercial use, no attribution needed | n/a | Ready-made icons, mascots | documented: [lottiefiles.com/page/license](https://lottiefiles.com/page/license) |
| gl-transitions | MIT package; per shader 123 MIT, 1 BSD-3, 1 BSD-2 | 1.75.0 | 125 GLSL scene transitions (also WGSL, MSL ports) | measured: `npm pack gl-transitions` then `jq '.[].license'` |
| LYGIA shader library | Prosperity 3.0: non-commercial, 30-day commercial trial | n/a | Noise, SDF, blur, lighting GLSL | documented: [LICENSE.md](https://github.com/patriciogonzalezvivo/lygia/blob/main/LICENSE.md) |
| Theatre.js | Apache-2.0 | last push 2024-08-14 | Keyframed camera for Three.js | measured: `gh api repos/theatre-js/theatre` (stale) |

## Techniques, one by one

### Transitions

- **Remotion**: `TransitionSeries` with 20 presentations: blur-slide,
  book-flip, clock-wipe, crosswarp, cross-zoom, dissolve, dreamy-zoom, fade,
  film-burn, flip, iris, linear-blur, none, push-cut, ripple, slide, swap, wipe,
  zoom-blur, zoom-in-out (measured: exports of `@remotion/transitions`
  4.0.535). `TransitionSeries.Overlay` lays a light leak or flash over a cut
  (lab: `remotion-markup/src/Main.tsx`, clock-wipe, wipe, fade and two
  overlays).
- **HyperFrames**: `@hyperframes/shader-transitions` gives 14 WebGL shaders
  (domain-warp, whip-pan, sdf-iris, cinematic-zoom, chromatic-split, glitch,
  light-leak and others), driven by a GSAP timeline and pre-capturing scene
  samples, with an html2canvas fallback (documented: its README). Lab: the
  hyperframes poster film uses "staggered blocks" and "circle iris"
  (`videos/hyperframes/STORYBOARD.md`).
- **Motion Canvas**: `slideTransition`, `zoomInTransition`, fade, plus
  `useTransition` for custom ones (documented: motion-canvas docs via ctx7).
- **Manim**: no scene transitions; continuity comes from `Transform` and
  `TransformMatchingTex` within one scene (documented: Manim docs).
- **Any WebGL engine**: gl-transitions' 125 shaders port as fragment shaders.
- **Cost**: CSS presentations are cheap; WebGL ones (crosswarp, ripple,
  film-burn) need a GPU in headless Chrome to stay fast (inferred from the
  Remotion GPU page below).

### Camera moves

- **Remotion 2D**: a wrapper `<div>` with `transform: scale() translate()`
  interpolated by frame; anything2explainer ships a `CameraRig` with keyed
  `camAt()` eases (lab: `anything2explainer/video/src/fx.tsx`).
- **Remotion 3D**: `@remotion/three`'s `ThreeCanvas` with a frame-driven camera
  (lab: `remotion-markup/src/scenes/Tunnel.tsx`, a fly-through of 36 rings and
  140 star streaks; `Lattice.tsx`, an orbiting lit lattice). Rendering needs
  `--gl=angle` or the canvas comes out empty (documented:
  [remotion.dev/docs/three-webgpu-canvas](https://www.remotion.dev/docs/three-webgpu-canvas)).
- **HyperFrames**: real camera moves only through the Three.js adapter; CSS
  `perspective` is "projected rectangles" (documented:
  `docs/prompting/runtimes-and-3d.mdx`). Registry has `camera-dolly-zoom`,
  `cinematic-zoom` blocks (measured: `ls registry/blocks`).
- **Motion Canvas**: a `Camera` node with zoom, centring and follow (documented:
  `docs/getting-started/camera.mdx`).
- **Manim**: `MovingCameraScene` animates `self.camera.frame`; `ThreeDScene`
  orbits (documented: Manim examples, `FollowingGraphCamera`).

### Motion blur

- **Remotion `<CameraMotionBlur>`**: averages `samples` sub-frame renders over
  `shutterAngle`; default 10 samples, recommended 5 to 10 (documented:
  [camera-motion-blur](https://www.remotion.dev/docs/motion-blur/camera-motion-blur)).
  Cost: each output frame renders its children `samples` times, so 10 samples
  is about 10x the cost of that layer (inferred from the doc's "render ten
  frames with different time offsets"). Lab: `Tunnel.tsx` wraps only the
  kinetic words ("every frame is a function of"), with `shutterAngle={260}
  samples={10}`, which keeps the multiplier off the 3D layer.
- **Remotion `<Trail>`**: layered ghost copies, cheaper look-alike (documented:
  [trail](https://www.remotion.dev/docs/motion-blur/trail)).
- **Remotion `<HtmlInCanvasMotionBlur>`**: uses Chrome's HTML-in-canvas
  (`drawElementImage`) (documented:
  [html-in-canvas-motion-blur](https://www.remotion.dev/docs/motion-blur/html-in-canvas-motion-blur);
  measured: `grep drawElementImage` in the package). In the remotion-markup lab
  run it crashed on 4.0.535 (lab session verdict, not reproduced here), so it is
  not a default.
- **Fake blur**: a directional `filter: blur()` on the moving element only
  (anything2explainer's `DirBlur`, `common/lib.tsx`), or the `whip-pan` shader
  transition in HyperFrames. HyperFrames also has a motion-blur component used
  by its `gooey-split` block (documented: `docs/catalog/blocks/gooey-split.mdx`).
- **Motion Canvas, Manim**: none built in (inferred: not found in either docs
  set via ctx7).

### Kinetic type

- **Remotion**: per-word `spring()` or `interpolate()` with `Easing`, words
  timed to narration word marks; the house pipeline's `kinetic` scene does
  exactly this, "words spring in" (lab: `ship-explainer-video-v2/STYLE.md`).
  remotion-markup's `Slam` throws one word per beat under motion blur.
- **GSAP SplitText** (now free) splits lines, words and characters; in Remotion
  it runs through `@remotion/gsap`'s `useGsapTimeline()`, which seeks a paused
  timeline to the current frame (documented:
  [use-gsap-timeline](https://www.remotion.dev/docs/gsap/use-gsap-timeline)).
- **HyperFrames**: GSAP is the default for "fades, slides, staggers, counters,
  kinetic type" (documented: `runtimes-and-3d.mdx`). The poster film animates
  the Anybody variable font's width and weight axes as the show (lab:
  `STORYBOARD.md` frame 4, `font-variation-settings`).
- **Glitch entrance**: anything2explainer's `GlitchIn` is a 12-frame opacity
  sequence plus optional RGB-split copies (feColorMatrix tints) and slice
  offsets (lab: `video/src/common/Glitch.tsx`). Its code is PolyForm
  Noncommercial, so the technique must be re-implemented, not copied (inferred).
- **Arabic**: per-character splitting breaks Arabic joining; split by word for
  right-to-left lines (inferred; to confirm in the Arabic rendering ticket).

### Masks and reveals

- **CSS everywhere** (Remotion, HyperFrames): `clip-path` polygons and circles,
  `mask-image` gradients, `mix-blend-mode: difference` (lab: hyperframes posters
  INVERT and REVEAL use exactly these, `STORYBOARD.md` frames 2 and 3).
- **Line draw**: `@remotion/paths` `evolvePath()` (MIT) on SVG strokes, GSAP
  DrawSVG; on maps, a MapLibre line layer sliced by distance with turf (lab:
  `remotion-maps/src/MapLayer.tsx`, `lineSliceAlong` for the travelled route).
- **Hand-drawn marks**: `@remotion/rough-notation` (MIT) circles, underlines,
  highlights (measured: in remotion-markup's dependencies).
- **Light sweep**: bars of light swept across a title with an eased x
  (anything2explainer `LightSweep`, `fx.tsx`; same licence caveat).
- **Motion Canvas**: node `clip`, `cache` plus `compositeOperation` (inferred:
  not confirmed in this pass). **Manim**: `Create`, `Write`,
  `DrawBorderThenFill`, `LaggedStart` (lab: `video-lab/manim/merge_base.py`).

### Glow, light and grain (material layer)

- **Remotion `@remotion/effects`**: 73 WebGL2 or 2D canvas effects applied via
  an `effects` prop on canvas components such as `<Solid>`: light-leak,
  light-trail, glow, shine, chromatic-aberration, film grain (`noise`), halftone,
  scanlines, vignette, LUT, zoom-blur and more (measured: package `exports`;
  `getContext("webgl2")` in most modules). Lab: `remotion-markup/src/parts.tsx`
  `LightLeak` over a full-frame `<Solid>`; film grain there is an SVG
  `feTurbulence` reseeded each frame.
- **Glowing line**: two stacked line layers, a wide blurred one under a sharp
  one (lab: `remotion-maps` `route-glow`, `line-width: 16, line-blur: 12`).
- **Halo rings, hero glow**: SVG ellipses with ripples and radial gradients
  (anything2explainer `HaloRing`, `HeroGlow`; licence caveat).
- **Three.js**: pmndrs/postprocessing bloom and noise (Zlib).
- **Style tension**: the house `explainer-style` skill bans glow, particles and
  radial washes outright (lab: `ship-explainer-video-v2/.claude/skills/explainer-style/SKILL.md`
  "No glow"). So the material layer is a style-profile choice, not a default
  for every style (inferred).

### Particles and shaders

- **Determinism first**: every particle must be seeded per frame, not by
  `Math.random()`; Remotion's `random(seed)` does this (lab: `Tunnel.tsx`
  star field built with `random(\`a${i}\`)`).
- **Remotion**: DOM or SVG dots for under a few hundred; Three.js `Points` or
  instanced meshes for thousands; `@remotion/noise` for organic drift.
- **Shaders**: Remotion effects or a custom WebGL canvas; Motion Canvas `shaders`
  prop on any node with GLSL (documented: `docs/advanced/shaders.mdx`);
  HyperFrames blocks like `code-shader-dissolve`, `code-particle-assemble`
  (measured: `ls registry/blocks`).
- **Audio-reactive**: `visualizeAudio()` bins are linear in frequency, so the lab
  resampled 512 bins onto a log axis (40 Hz to 12 kHz) with a +4.5 dB/octave tilt
  (lab: `remotion-markup/src/useSpectrum.ts`). Useful for a ducked score's
  visualiser, if a style wants one.

### 3D inserts

- **Remotion + R3F** (`@remotion/three`, MIT; three MIT): lab
  `remotion-markup` Tunnel and Lattice scenes rendered live.
- **Pre-render and cache**: motioncraft isolates 3D in a transparent composition
  and runs `motioncraft cache3d`, which writes PNG frames plus a manifest that
  hashes every source file, then composites them with `<CachedFrames>` (lab:
  `motioncraft/video/public/mc-cache/shapes3d-*/manifest.json`, 156 and 103
  frames; `src/scenes/Shapes3D.tsx` header "pre-render it with software GL").
  On this machine the live Vulkan path dropped 3D frames, so the cache was
  rendered with software GL (lab session verdict). motioncraft is MIT, so the
  pattern can be borrowed (measured: its `LICENSE`). Its own docs warn that
  `--require-gpu` cannot prove hardware use and ask for an `angle` versus
  `swangle` comparison on a short segment (documented:
  `references/gpu-cloud-render.md`).
- **HyperFrames**: Three.js through its seek-safe adapter (`window.__hfThreeTime`,
  `hf-seek` event) (documented: `runtimes-and-3d.mdx`); a `code-3d-extrude`
  block exists.
- **Manim**: `ThreeDScene` (CPU Cairo renderer by default; an OpenGL renderer
  exists for preview) (documented: Manim configuration guide).

### Lottie

- **Remotion `@remotion/lottie`** seeks lottie-web per frame; data loads under
  `delayRender()` (documented: [after-effects](https://www.remotion.dev/docs/after-effects)).
  Package is under the Remotion License (measured: `npm view`).
- **HyperFrames**: Lottie adapter, `lottie-character-walk` block; "don't ask the
  agent to redraw it" (documented: `runtimes-and-3d.mdx`).
- **Assets**: LottieFiles free animations under the Lottie Simple License are
  commercial-safe without attribution (documented above).
- **Cost**: SVG renderer per frame, cheap for icons, heavier for full-frame
  characters (inferred).

### Easing libraries

- **Remotion**: `Easing.bezier`, `spring()`, `interpolate()`; GSAP eases through
  `@remotion/gsap`. The poster film's ease vocabulary was mostly `power4.out`,
  `expo.inOut`, `back.out(1.4 to 1.7)` and `steps(n)` for typing (measured:
  `grep -o 'ease: "…"'` over `videos/hyperframes/compositions`).
- **GSAP**: full ease set incl. CustomEase (free licence; the licence page does
  not name CustomEase explicitly, see Thin).
- **anime.js** (MIT): a GSAP alternative with no Webflow clause.
- **Motion Canvas**: `easeInOutCubic` and family; **Manim**: `rate_func`s.

## Render cost on this machine

| Case | Number | Basis |
|---|---|---|
| HyperFrames, 60 s at 1080p30, 3 workers, hardware GPU, beginframe capture | 94.3 s wall, 827 MB max RSS | measured: `hyperframes/out/render.log` |
| motioncraft (Remotion), 57 s at 1080p30, 3D from cache | 56.7 s wall | measured: `motioncraft/video/out/render.log` |
| `CameraMotionBlur samples=N` | about N times the wrapped layer's cost | inferred from docs |
| GPU-bound CSS (`box-shadow`, `text-shadow`, gradients, `filter: blur()`, `drop-shadow`), WebGL, canvas | "significant slowdown" in headless Chromium without GPU; precompute to images | documented: [remotion.dev/docs/gpu](https://www.remotion.dev/docs/gpu), [performance](https://www.remotion.dev/docs/performance) |
| HyperFrames blurs and backdrop filters | "Use fewer large `backdrop-filter` and `filter: blur()` layers", pre-render static stacks | documented: `docs/guides/performance.mdx` |

## Recommendation

- Build effects as **Remotion components in the skill's template**, using only
  MIT or Remotion-License first-party packages, GSAP (via `@remotion/gsap`),
  lottie-web and gl-transitions. Note the Remotion company licence in setup
  output for organisations over 3 people.
- Ship a small **effects vocabulary** keyed by the style profile, not on by
  default: transition family, camera (2D rig, 3D opt-in), kinetic-type mode,
  material layer (none, grain, light leak, glow), motion blur (none, trail,
  camera with samples at most 6). The house "no glow" style is one valid
  setting.
- **3D is always cached**: an isolated transparent composition, pre-rendered to
  PNG frames keyed by a source hash (motioncraft's pattern, MIT), so storyboard
  revisions that touch text never re-render 3D, and Vulkan frame drops never
  reach the final cut.
- Keep `HtmlInCanvasMotionBlur`, Shadertoy code, LYGIA and anything2explainer
  code out of the skill; re-implement the glitch, light-sweep and halo
  techniques from their descriptions.
- Every effect is frame-pure and seeded, so a storyboard still matches the
  final frame.

## Thin

- Shadertoy's default licence (CC BY-NC-SA 3.0) is from memory: `shadertoy.com/terms`
  returned 403 to WebFetch and curl.
- The HtmlInCanvasMotionBlur crash and the Vulkan 3D frame drops are lab session
  verdicts passed to me; I did not reproduce them (no rendering allowed).
- Whether `@remotion/transitions` and `@remotion/effects` (`UNLICENSED` in
  `package.json`, no licence file) fall under the root Remotion License is
  inferred, not stated by Remotion.
- GSAP CustomEase is not named on the licence page, though the FAQ says "All of
  GSAP including the plugins".
- No render time for remotion-markup (live 3D plus motion blur) was logged, so
  the cost of live R3F on this GPU is unmeasured.
- Motion Canvas masking and Manim 3D render cost were not checked in depth.
