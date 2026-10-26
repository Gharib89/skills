# Charts, graphics and visual effects in motion

Research for [#968](https://github.com/Gharib89/skills/issues/968) on the map
[#961](https://github.com/Gharib89/skills/issues/961) (creative video skill).
Date: 2026-10-26.

Builds on, and does not repeat:
[#657](https://github.com/Gharib89/skills/issues/657) effects
(`research/explainer-effects`), [#773](https://github.com/Gharib89/skills/issues/773)
motion references (`research/explainer-motion-refs`) and
[#658](https://github.com/Gharib89/skills/issues/658) diagrams
(`research/explainer-diagrams`). Only what is new or corrects them is here.

Labels: **measured** (a command or render was run, named inline), **sourced**
(a primary source says so, linked), **inferred** (my reading, no direct proof).

## Answer

1. **Determinism is a property of the clock, not of the library, so the new
   skill can leave the agent free to pick any chart or effect library and
   enforce one cheap gate instead of a library list.** In a 12-composition
   Remotion probe, every library driven by the frame rendered identical PNGs
   across two renders at concurrency 1 and 4 (Recharts with its animation off,
   D3 used as maths, Observable Plot rebuilt per frame, flubber,
   `@remotion/paths`, `@remotion/noise`, seeded rough.js, CSS keyframes seeked by
   delay: each 60 of 60 frames identical). Every library left on its own clock
   failed: Recharts' default animation 39 of 60, a D3 transition 0 of 60,
   unseeded rough.js 0 of 60, infinite CSS keyframes 0 of 60 (measured, probe
   below). The defect gate that follows: render a sample of frames twice at
   different concurrency and fail on any hash mismatch. It catches every one of
   these faults with no menu of allowed libraries, which fits the map's "hard
   rules only where a real defect stands behind them".
2. **Correction to #658: CSS keyframes are seekable in both engines.** Remotion
   documents `animation-play-state: paused` plus a negative `animation-delay`
   (sourced, [third-party integrations](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/third-party.mdx)
   "CSS animations"), and the probe rendered it 60 of 60 identical (measured).
   HyperFrames seeks CSS `@keyframes` automatically when iterations are finite
   (sourced, vendored `hyperframes` skill `references/runtimes.md`). So Mermaid's
   dash edges and D2's animated step SVG are not ruled out by seeking, as #658
   said; D2's per-step size change and the bidi faults still stand.
3. **Morphing: `@remotion/paths` pops on curve-to-line morphs; flubber does
   not.** `interpolatePath(0.02, circle, star)` turned a `makeCircle` circle
   (two arc commands) into a 10-sided polygon on the first in-between frame, a
   visible jump; flubber's interpolator stayed round and blended smoothly
   (measured: frames 0, 1, 4 and 12 compared side by side, and the printed path
   at t=0.02). The new multi-keyframe `interpolatePaths()` (since 4.0.529) also
   needs matching move and close commands per subpath (sourced,
   [interpolate-paths](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/paths/interpolate-paths.mdx)).
   flubber is MIT but unpublished since 2022 (measured, `npm view flubber`).
4. **HyperFrames' shader noise and backgrounds need WebGPU, which this machine's
   headless Chrome does not expose.** 36 registry blocks (fractal, Worley and
   Gabor noise, aurora, plasma, nebula, godrays and more) bundle the
   `shaders` library (shaders.com, MIT) on TypeGPU and declare
   `data-requires-webgpu` (measured: tree listing of `heygen-com/hyperframes`,
   `lib/shaders.iife.js` per block; licence file in the block). Rendering
   `fractal-noise` failed with "a usable WebGPU device could not be created"
   on HeadlessChrome 152 here (measured, `hyperframes render`, 0.8.203). It
   rendered only with both `PRODUCER_ALLOW_SOFTWARE_WEBGPU=true` and
   `PRODUCER_BROWSER_GPU_MODE=software`; the error message names only the
   first (measured, and read in the CLI's `dist` source). On SwiftShader, 2 s of
   1080p30 took 85 and 87 s wall (49 s setup, 31 to 33 s capture, about 0.5 s a
   frame), and both runs were frame-identical, 60 of 60 (measured,
   `ffmpeg -f framemd5`). Usable for a short pre-rendered loop, too slow for a
   full-length background.
5. **Remotion's effects do not reach a DOM chart directly.** `@remotion/effects`
   grew from 73 to 83 effects at 4.0.539 (new include `paper`,
   `roughen-edges`, `fractal-noise`, `shatter`, `speckle`), each seeded (measured:
   package `exports`; sourced, effect pages' `seed` props). They apply only to
   canvas-backed components (`<Solid>`, `<Img>`, `<Video>`, the shapes,
   `<RemotionRiveCanvas>`, `<HtmlInCanvas>`) (sourced,
   [effects index](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/effects/index.mdx)).
   An SVG chart gets glow or grain only through `<HtmlInCanvas>`, whose Chrome
   bug "HTML-in-canvas does crash page on WebGL context loss" is still open
   (sourced, [html-in-canvas-bugs](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/html-in-canvas-bugs.mdx));
   that is a likely cause of the `HtmlInCanvasMotionBlur` crash #657 reported
   (inferred). Otherwise glow on SVG is an SVG filter or CSS `filter`, which
   #657 already flagged as GPU-slow.
6. **Rive is a poor default in both engines.** `@remotion/rive` plays only a
   linear animation (`LinearAnimationInstance`, advanced by the frame delta),
   has no state-machine prop, fetches `rive.wasm` 2.31.5 from unpkg at render
   time, and is under the Remotion License, not MIT (measured: read
   `packages/rive/src/RemotionRiveCanvas.tsx`; `npm view @remotion/rive`).
   HyperFrames has no Rive adapter: its built-in seekers are GSAP, CSS,
   Anime.js, Lottie, Three.js, Web Animations and TypeGPU (sourced,
   [frame-adapters](https://github.com/heygen-com/hyperframes/blob/main/docs/concepts/frame-adapters.mdx)).
   Rive's teaching strength is the state machine (Duolingo drives character
   lip-sync from visemes with it, sourced,
   [Duolingo blog](https://blog.duolingo.com/world-character-visemes)), which
   neither wrapper exposes. Free-plan `.riv` exports also "play a Rive splash
   screen" (sourced, [rive.app/pricing](https://rive.app/pricing)). For the
   map's open "cast" item, a lip-synced host in Rive needs a custom seek adapter
   over `@rive-app/canvas-advanced` (inferred, untried).
7. **Lottie: an After Effects `wiggle()` expression is unseeded.** lottie-web
   5.13.0's `wiggle` calls `BMMath.random`, which is `Math.random` (measured:
   read `build/player/lottie.js`). A downloaded LottieFiles asset that uses it
   jitters differently on every render; the gate in finding 1 catches it.
   `@remotion/lottie` depends on lottie-web only, so no `.lottie` (dotLottie)
   files or Lottie state machines (measured: package `dependencies`);
   HyperFrames seeks dotLottie as well (sourced, `runtimes.md`).

## Probe

A throwaway Remotion 4.0.539 project, 640x360, 30 fps, 60 frames per
composition. Each was rendered twice as a PNG sequence
(`remotion render --sequence --concurrency=1`, then `--concurrency=4`), and each
frame's md5 was compared across the two runs. "Distinct" is the count of
unique frames in a run (a 45-frame ramp then a hold gives 46).

| Composition | What it does | Identical across runs | Distinct (c1 / c4) |
|---|---|---|---|
| RechartsDefault | Recharts 3.10.1 `BarChart`, default animation | 39/60 | 7 / 17 |
| RechartsFrame | same, `isAnimationActive={false}`, values from `interpolate(frame)` | 60/60 | 43 / 43 |
| D3Transition | d3 7.9.0 `selection.transition().duration(1500)` | 0/60 | 23 / 60 |
| D3Frame | d3 scales and `d3.line()` on frame-driven data | 60/60 | 46 / 46 |
| PlotFrame | Observable Plot 0.6.17 `Plot.plot()` rebuilt every frame | 60/60 | 46 / 46 |
| RoughUnseeded | rough.js 4.6.6 rectangle, no `seed` | 0/60 | 60 / 60 (boils) |
| RoughSeeded | same, `seed: 7` | 60/60 | 1 / 1 |
| MorphRemotion | `interpolatePath` circle to star | 60/60 | 46 / 46 |
| MorphFlubber | flubber 0.4.2 circle to star | 60/60 | 46 / 46 |
| NoiseField | 400 dots displaced by `@remotion/noise` `noise3D` | 60/60 | 60 / 60 |
| CssDefault | `@keyframes` with `infinite`, untouched | 0/60 | 60 / 39 |
| CssSeeked | same, `animation-play-state: paused`, `animation-delay: -t` | 60/60 | 60 / 60 |

The probe ran one render pair per composition, so it says nothing about speed.

## Techniques: what is new per technique

Each entry: library, deterministic under frame time, Remotion, HyperFrames,
licence, and one example of the technique teaching a concept. Baseline facts
from #657, #658 and #773 are not repeated.

### Animated charts and data stories

- **Libraries**: Recharts 3.10.1 (MIT), d3 7.9.0 (ISC), Observable Plot 0.6.17
  (ISC), visx 4.0.0 (MIT) (measured, `npm view`). Deterministic only with the
  library's own animation off and the data driven by the frame (measured,
  probe). visx animates through `@visx/react-spring`, a wall-clock spring, so
  the same rule applies (inferred; Remotion lists react-spring as having "no
  direct compatibility", sourced, third-party page).
- **Remotion**: Remotion's own prompt-to-motion-graphics template teaches
  charts hand-built from `spring()` per bar and `strokeDashoffset` per pie
  segment, no chart library (sourced,
  [charts.md](https://github.com/remotion-dev/remotion/blob/main/packages/template-prompt-to-motion-graphics/src/skills/charts.md)).
- **HyperFrames**: seven registry chart items (`animated-bar-chart`,
  `data-chart`, `decline-chart`, `bar-chart-race`, `chart-story`,
  `week-in-merges`, `mk-line-graph`) (measured,
  `hyperframes catalog --query chart`). `chart-story` is "inline SVG built
  synchronously from the variables, no chart library, fully deterministic"
  (sourced, its README). Any other library is driven from a GSAP `onUpdate`
  (sourced, `references/types/data.md`).
- **Recommendation** (inferred): D3 for scales, shapes and layout maths, the
  marks drawn as the agent's own SVG; a full chart library only with its
  animation off. Both engines' own guidance already lands here.
- **Example**: [Hans Rosling, 200 Countries, 200 Years, 4 Minutes](https://www.youtube.com/watch?v=jbkSRLYSojo)
  (BBC, 2010): one bubble chart animates through two centuries so the viewer
  watches health and wealth rise together (measured title, `yt-dlp`).

### Diagrams that build

- **New**: HyperFrames ships `flowchart` and `flowchart-vertical` blocks and a
  `whiteboard-ink` component that draws any multi-stroke SVG one measured
  stroke at a time with a pen nib riding the ink front (sourced, catalog docs
  and `whiteboard-ink` README). Mermaid and D2 are back in play for seeking
  (finding 2).
- **Example**: [3Blue1Brown, But what is a neural network?](https://www.youtube.com/watch?v=aircAruvnKk)
  (2017): the network diagram gains a layer, then weights, then activations,
  each as it is named (measured title).

### SVG path draw and morph

- **Draw**: `evolvePath` (baseline) and, in HyperFrames, `getTotalLength`
  dash draws; `chart-story` warns against the `pathLength` attribute and
  `vector-effect: non-scaling-stroke` on dashed paths (sourced, README).
- **Morph**: `@remotion/paths` `interpolatePath`, `interpolatePaths` (MIT,
  code from d3-interpolate-path, BSD-3-Clause); flubber (MIT); GSAP MorphSVG in
  HyperFrames (free licence, baseline). HyperFrames has 11 morph items
  (`morph-text`, `facet-morph`, `code-morph`, `cross-warp-morph` and others)
  (measured, catalog query). All deterministic under frame time (measured for
  the first two); quality differs (finding 3).
- **Example**: [3Blue1Brown, Linear transformations and matrices](https://www.youtube.com/watch?v=kYB8IZa5AuE)
  (2016): the whole grid morphs under a matrix, so the matrix is seen as a
  motion of space. [But what is a Fourier series?](https://www.youtube.com/watch?v=r6sGWTCMz2k)
  (2019) draws a path with chained rotating vectors (measured titles).

### Kinetic typography

- **New**: HyperFrames exposes `window.__hyperframes.fitTextFontSize` and a
  reflow-free `pretext` measurer (sourced, `runtimes.md`); its 62 text items
  include `morph-text` (SVG threshold plus blur) and `particle-text-dissolve`
  (measured, catalog; sourced, READMEs). CSS animation libraries become usable
  in Remotion through the delay technique (finding 2). The #773 rule (words,
  never letters, for Arabic) is unchanged.
- **Example**: 3Blue1Brown's equation moves, where a term slides across the
  equals sign rather than being retyped, as in the Fourier video above
  (inferred from the channel's use of Manim `TransformMatchingTex`, #657).

### Shader transitions

- **New**: Remotion transitions are 20 presentations at 4.0.539, unchanged
  (measured, `exports`), plus a custom HTML-in-canvas presentation API.
  `@hyperframes/shader-transitions` 0.8.203 publishes no `license` field on npm
  (measured, `npm view`), though the repo is Apache-2.0 (measured, `LICENSE`).
  HyperFrames lists 60 shader items in its catalog (measured).
- **Example**: none found that teaches. #773 measured narrated explainers
  cutting 0 to 10 times a minute and handing over by shape wipe or camera, so a
  shader transition is decoration between ideas, not an explanation (inferred).

### Particles

- **Libraries**: tsParticles 4.5.0 (MIT) is not seekable: its clock is
  `requestAnimationFrame` and its state accumulates step by step, though
  `setRandom()` can seed it (measured: read `esm/Utils/MathUtils.js`; inferred
  for seeking). Deterministic particles are a pure function of seed and time:
  `@remotion/noise` or `random(seed)` in Remotion (measured, NoiseField), and
  in HyperFrames the `particle-text-dissolve` pattern, which samples target
  points once from the rendered text bitmap with a fixed LCG seed and repaints
  the whole field from the timeline time (sourced, README). Because it samples
  the browser's own rendering, it should keep Arabic joined (inferred, untried).
- **Example**: [3Blue1Brown, Simulating an epidemic](https://www.youtube.com/watch?v=gxAaO2rsdIs)
  (2020): each dot is a person, and the spread is watched rather than told
  (measured title).

### Noise fields

- **Remotion**: `@remotion/noise` (MIT) `noise2D/3D/4D` with a string seed,
  deterministic (measured); `fractal-noise`, `noise`, `noise-displacement`,
  `turbulent-displace` effects on canvas components (measured, exports).
- **HyperFrames**: the WebGPU noise blocks (finding 4); otherwise a seeded PRNG
  in an `hf-seek` canvas (sourced, `runtimes.md`).
- **Example**: [NASA, Perpetual Ocean](https://www.youtube.com/watch?v=CCmTY0PKGDs)
  (2012): streaks flow along modelled surface currents, so a flow field
  teaches circulation when the field is data, not noise (measured title). A
  pure noise field is texture (inferred).

### Glow, blur and grain

- **New**: effect reach in Remotion (finding 5). In HyperFrames, grades, grain,
  blur and vignettes on footage go through `hyperframes media-treatment`, never
  CSS filters (sourced, vendored `hyperframes` skill `SKILL.md` rule 11);
  `grain-overlay` uses an SVG `feTurbulence` tile (measured, read source).
- **Example**: glow as state in the neural network video above, where a
  neuron's brightness is its activation (measured title; the reading is mine).

### Lottie and Rive

- Findings 6 and 7. Licences: lottie-web 5.13.0 MIT, dotlottie-web 0.81.0 MIT,
  Rive runtimes 2.47.1 MIT, `@remotion/lottie` and `@remotion/rive` under the
  Remotion License (measured, `npm view`).
- **Example**: Duolingo's World Characters lip-sync to speech through a Rive
  state machine fed with visemes (sourced, Duolingo blog above). It is an app,
  not a video, and needs the state machine neither wrapper supports.

### Sketch and hand-drawn looks

- **New**: unseeded rough.js boils on every frame (measured, 60 distinct frames
  of one static box; #658 had inferred it). HyperFrames has `hw-*`
  hand-written blocks, but `hw-path-text` ships a Latin-only Caveat subset
  (measured: `Caveat-700-latin.woff2` in the tree), and `whiteboard-ink` draws
  the agent's own paths. Remotion adds seeded `roughen-edges` and `paper`
  effects for canvas content (sourced, effect docs).
- **Example**: [RSA Animate, Changing Education Paradigms](https://www.youtube.com/watch?v=zDZFcDGpL4U)
  (2010): a hand draws the argument as the speaker makes it (measured title).

## Licence changes against the baseline

| Package | Licence | Version | Source |
|---|---|---|---|
| `@remotion/rive` | Remotion License | 4.0.539 | measured, `npm view` |
| `@remotion/noise`, `@remotion/paths`, `@remotion/shapes` | MIT | 4.0.539 | measured |
| `shaders` (shaders.com), TypeGPU | MIT | 4.0.5, 0.12.3 | measured, `npm view`; block licence file |
| `@hyperframes/shader-transitions` | no npm field (repo Apache-2.0) | 0.8.203 | measured |
| flubber / d3-interpolate-path | MIT / BSD-3-Clause | 0.4.2 / 2.3.0 | measured |
| Recharts / d3 / Plot / visx | MIT / ISC / ISC / MIT | 3.10.1 / 7.9.0 / 0.6.17 / 4.0.0 | measured |
| tsParticles | MIT | 4.5.0 | measured |
| Rive editor | free exports carry a splash screen | n/a | sourced, pricing page |

## Thin

- The probe ran in Remotion only; HyperFrames was probed for the WebGPU block
  alone. Chart libraries under HyperFrames' GSAP `onUpdate` are documented,
  not rendered here.
- Whether HyperFrames seeks CSS transitions (as opposed to keyframes), which
  shiki magic move uses, is not documented and was not tried.
- Hardware WebGPU in headless Chrome was not attempted with other flags or in
  `--docker`; the SwiftShader timing is two runs, not five, so it is an order
  of magnitude, not a benchmark.
- The Rive state-machine adapter and Arabic in `particle-text-dissolve` are
  inferences, untried.
- The `interpolatePath` pop was measured on one shape pair (arcs to lines);
  shapes built from cubic curves were not tried.
