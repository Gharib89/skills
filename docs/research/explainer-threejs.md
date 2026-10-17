# Three.js explainer scenes on an 8 GB GPU

Research for [#774](https://github.com/Gharib89/skills/issues/774) on the map
[#770](https://github.com/Gharib89/skills/issues/770). Date: 2026-10-17.
Builds on `research/explainer-engines` (#653) and `research/explainer-effects`
(#657); facts settled there are not repeated.

Labels: **measured** (a command was run, named inline), **documented** (a
primary source says so, linked or cited by file and line), **inferred** (my
reasoning from those), **guess** (plausible, unproven).

## Answer

1. **The strongest explainer shapes are closed-form in time**: a dot globe
   with tube arcs, data flowing along lines or tubes, particles morphing
   between two shapes, an exploded stack, and SDF text. Each is drawn from a
   `uProgress` uniform, a `setDrawRange` count or a dash offset, all computed
   from the seek time. That makes them seek-safe in HyperFrames (inferred from
   the sources below). Simulated motion (GPGPU flow fields, physics, anything
   that integrates the previous frame) is not seek-safe; it needs baking
   (Lusion's vertex-animation textures) or a cached sequential pre-render.
2. **Cost is small for this GPU.** The published heavy cases are 12,000
   instanced dots in one draw call (GitHub globe), 60,000 dots (Stripe globe),
   and 200,000 compute particles (`webgpu_compute_particles`) (documented).
   A 1080p RGBA8 render target is 8.3 MB and troika's default glyph atlas tops
   out at 16 MiB (inferred arithmetic), so VRAM is not the binding limit at
   3 workers; frame time and capture are. No frame time on this machine is
   known yet: that is the task ticket's measurement.
3. **HyperFrames never uses Vulkan for WebGL.** Its Linux hardware mode is
   ANGLE over GL-EGL; its software mode is SwiftShader (measured, `npm pack
   hyperframes@0.8.160`, `getBrowserGpuArgs`). The lab's HyperFrames render
   probed the GPU as `ANGLE (NVIDIA ... RTX 2070 Super with Max-Q Design ...
   OpenGL ES 3.2)` but drew no WebGL, so HyperFrames plus Three.js on this GPU
   is untested (measured, `grep` of `video-lab/hyperframes/out/render.log` and
   its compositions).
4. **GPU frames are not promised to be pixel-identical.** HyperFrames bans
   hardware GL in distributed renders because "Hardware GL is bitwise unstable
   across drivers" (measured, string in the 0.8.160 `dist`), and its `main`
   docs report one-level pixel differences between parallel workers at chunk
   boundaries even on one machine (documented, below). The map's determinism
   gate has to choose: software GL, one worker, or a tolerance for GPU frames
   (inferred).
5. **The lab's "dropped frames" were not dropped frames.** In motioncraft
   (Remotion 4.0.529, three 0.160.1), every frame with a transparent React
   Three Fiber canvas lost both the 3D layer and the DOM background under
   `--gl=angle` and `--gl=vulkan`; `--gl=swangle` drew them correctly
   (measured, motioncraft session transcript, below). In remotion-markup
   (Remotion 4.0.535, three 0.186.1, opaque canvas) live 3D rendered fine on
   `--gl=vulkan`. The root cause was never isolated. Records #652 and #657 that
   say "dropped frames" describe a blank WebGL composite.

## Scene archetypes

Each row: reference works, the technique, and costs the source states.

### Globes (strongest data-on-a-map shape)

- **GitHub globe** (documented,
  [how we built the GitHub globe](https://github.blog/engineering/engineering-principles/how-we-built-the-github-globe/)):
  about 12,000 five-sided circles in one `InstancedMesh` (about 8,000 on a
  lower tier), placed by sampling a world PNG; arcs are `CubicBezierCurve3`
  plus `TubeGeometry` grown with `setDrawRange`; a shader halo sphere at 1.15x;
  no textures, antialias off; quality steps down below 55.5 fps.
- **Stripe globe** (documented, [stripe.com/blog/globe](https://stripe.com/blog/globe)):
  `DOT_COUNT = 60000` sunflower-pattern dots (`CircleGeometry(2,5)`), cut to
  about 20,000; arcs as tubes of about 3,000 vertices each, draw range animated
  over 2.5 s; `antialias: false`.
- **three-globe / globe.gl** (MIT, 2.45.6 and 2.46.2, measured `npm view`):
  `pointsMerge` and `hexBinMerge` merge into one object "for improved
  rendering performance"; arc resolution knobs (documented, README). Labels use
  `TextGeometry` with helvetiker (measured by the survey agent,
  `src/layers/labels.js`), so Arabic labels need troika instead (inferred).
  **Determinism risk**: it runs its own `requestAnimationFrame` loop and tween
  group, and dash animation through `frame-ticker` (rAF plus `Date.now()`),
  incrementing `dashTranslate` by elapsed delta (measured by the survey agent:
  `src/globe-kapsule.js:362`, `src/layers/arcs.js:109-117`, `npm pack
  frame-ticker@1.0.3`). HyperFrames virtualises `Date.now`, `performance.now`
  and rAF (below), but state that accumulates per delta still breaks the
  "seeks work in any order" contract (inferred). Mitigation: transitions to 0,
  `arcDashAnimateTime(0)`, `pauseAnimation()`, and set dash uniforms from the
  seek time (inferred).
- **threejs.org**: `webgpu_tsl_earth`, `webgl_instancing_scatter` (measured by
  the survey agent, examples `files.json`).

### Flowing data (packets along edges)

- **threejs.org examples** (measured by the survey agent): `webgl_lines_fat`
  (`Line2`, pixel-width lines), `webgl_lines_dashed`,
  `webgl_geometry_extrude_splines` (tube along a spline, follow camera),
  `webgl_modifier_curve_instanced` (`InstancedFlow` moves meshes along
  curves), `webgl_buffergeometry_drawrange` (growing line),
  `webgl_postprocessing_unreal_bloom_selective` (glow on chosen objects).
- **Codrops "Animated Mesh Lines"** (documented,
  [2019-01-08](https://tympanus.net/codrops/2019/01/08/animated-mesh-lines/)):
  MeshLine strips animated by the `dashOffset` uniform, no geometry rebuild.
  `dashOffset = f(t)` is seek-safe (inferred).
- **Libraries**: `meshline` (pmndrs, MIT, 3.3.1, last publish 2024-06) and
  `three.meshline` (MIT, 2.0.0); no internal clock found (measured by the
  survey agent, `grep` of `src/`).

### Particle assemblies (shape A becomes shape B)

- **Three.js Journey `particles-morphing-shader`** (documented,
  [lesson](https://threejs-journey.com/lessons/particles-morphing-shader)):
  `position` plus an `aPositionTarget` attribute mixed by `uProgress` in the
  vertex shader, avoiding per-frame attribute writes. Seek-safe by
  construction (inferred).
- **HyperFrames `code-particle-assemble` block** (measured, vendored registry
  at `9c11715`): `THREE.Points` with a seeded mulberry32 PRNG, a paused GSAP
  timeline, render only from `tl.eventCallback("onUpdate", render)`, never
  rAF, `preserveDrawingBuffer: true`. A ready-made seek-safe pattern.
- **GPGPU** (`GPUComputationRenderer`): `webgl_gpgpu_birds` 1,024 agents,
  `webgl_gpgpu_protoplanet` 4,096, `webgpu_compute_particles` 200,000
  (measured by the survey agent, example source); Codrops
  [dreamy GPGPU particles](https://tympanus.net/codrops/2024/12/19/crafting-a-dreamy-particle-effect-with-three-js-and-gpgpu/)
  (documented). These integrate state frame to frame, so a seek to frame N
  needs N steps from a known start (inferred): pre-render sequentially, or
  bake like Lusion's Houdini vertex-animation textures (983 KB for 4,096
  vertices, documented, [awwwards case study](https://www.awwwards.com/case-study-for-lusion-by-lusion-winner-of-site-of-the-month-may.html)).

### Exploded diagrams and architecture stacks

- **HyperFrames `exploded-stack` block** (measured, vendored registry, three
  0.184.0): "every frame is render(t), driven by one linear GSAP clock",
  timeline registered on `window.__timelines`, `alpha: true`,
  `preserveDrawingBuffer: true`. Closest existing piece to an architecture
  stack.
- **Codrops "Exploding 3D Objects"** (documented,
  [2019-03-26](https://tympanus.net/codrops/2019/03/26/exploding-3d-objects-with-three-js/)):
  fragments moved in the vertex shader by `position += direction * progress`.
- **Exploded GLTF** (documented, [A. Naili](https://blog.anaili.fr/articles/exploded)):
  each part moves along `normalize(part.position - epicenter)`, driven by
  GSAP. Draw calls equal the part count (inferred).
- **Isometric slabs**: `OrthographicCamera` at (10,10,10) with box or
  `RoundedBoxGeometry` slabs (documented,
  [isometric rooms](https://danieljohnmorris.com/writing/threejs-isometric-rooms/)).
  No studio-grade primary source for explainer stacks was found (see Thin).
- **threejs.org**: `webgl_clipping_stencil` (capped cutaways),
  `webgl_postprocessing_outline`, `webgl_postprocessing_gtao`.

### 3D text and code

- **troika-three-text** (MIT, 0.52.5, measured `npm view`): parses
  .ttf/.otf/.woff and handles "right-to-left/bidirectional layout, joined
  scripts like Arabic" (documented, README). Defaults `sdfGlyphSize: 64`,
  `textureWidth: 2048`, `useWorker: true` (measured, `src/TextBuilder.js:9-17`
  at `a24a359`); 2048 x 2048 x 4 channels holds 4,096 glyphs (documented, same
  file), at most 16 MiB as RGBA8 (inferred).
  - Layout is asynchronous: wait for `sync(cb)` or `synccomplete` (documented,
    README "Handling Asynchronous Updates"). The HyperFrames three adapter only
    waits on `THREE.DefaultLoadingManager` (measured, `adapters/three.ts`), so
    troika's sync must be registered on `window.__hf.buildReady` (documented,
    `skills/hyperframes-animation/adapters/three.md`; pairing inferred).
  - Missing glyphs load Noto fallback fonts from jsDelivr by default
    (documented, README "Unicode Fallback Fonts"): a mid-render fetch that
    breaks determinism unless every Arabic and Latin font is local and
    `preloadFont` runs first (inferred).
  - SDFs are generated on the GPU through `webgl-sdf-generator`, falling back
    to JS on failure (measured, `src/SDFGenerator.js:15-30`), so glyph pixels
    may differ between hardware and SwiftShader (guess).
  - Not usable with WebGPU/TSL (documented,
    [Codrops 2026-01-28](https://tympanus.net/codrops/2026/01/28/webgpu-gommage-effect-dissolving-msdf-text-into-dust-and-petals-with-three-js-tsl/)).
  - Whole-word Arabic motion: one `Text` per word keeps joining inside a word
    but leaves line-level bidi ordering to us; `BatchedText` (experimental)
    draws many in one call (measured, `src/BatchedText.js:40-50`). The
    alternative is the HTML text layer over the canvas, as #653 recommended
    (inferred).
- **Code panels**: `THREE.HTMLTexture` ships in r186 on the WICG
  HTML-in-Canvas API (`requestPaint`/`onpaint`) (measured, `gh api
  .../src/textures/HTMLTexture.js?ref=r186`). The lab's other HTML-in-Canvas
  user, Remotion's `HtmlInCanvasMotionBlur`, failed with "No cached paint
  record for element" on angle, vulkan and swangle (measured, remotion-markup
  session transcript), so treat it as unproven under capture (inferred).
  `CanvasTexture` (`webgl_materials_texture_canvas`) is the safe route
  (inferred).
- **TextGeometry** cannot join Arabic (settled in #653).

## Libraries

| Library | Licence | Version (2026-10-17) | Role | Seek hazard |
|---|---|---|---|---|
| three | MIT | 0.186.1 (r186) | renderer | `Clock` deprecated since r183, `Timer` reads `performance.now()` (measured, `gh api` of `src/core/Clock.js`, `Timer.js` at r186); `EffectComposer.render()` with no delta uses it |
| postprocessing (pmndrs) | Zlib | 6.39.5 | bloom, DOF, noise, SMAA | `EffectPass` accumulates `material.time += deltaTime * timeScale` (measured, `src/passes/EffectPass.js:575` at `9cf03cf`); the material has a `time` setter, so set it from seek time and pass delta 0 (inferred). `NoiseTexture` and `GlitchEffect` call `Math.random` (measured, `grep`) |
| troika-three-text | MIT | 0.52.5 | Arabic-capable SDF text | async layout, CDN fallback fonts (above) |
| GSAP | Standard no-charge licence | 3.15.0 | camera and property timelines | none when the timeline is paused and seeked; HyperFrames seeks every timeline on `window.__timelines` (documented, determinism page) |
| three-globe, globe.gl | MIT | 2.45.6, 2.46.2 | globes | own rAF loop and tween state (above) |
| meshline, three.meshline | MIT | 3.3.1, 2.0.0 | thick and dashed lines | none found |
| camera-controls | MIT | 3.1.2 | camera rigs | `update(delta)` takes the caller's delta (measured by the survey agent) |
| three-stdlib | MIT | 2.36.1 | addons | `OutlinePass` pulses on `performance.now()` (measured by the survey agent) |
| lamina | MIT, repo archived | 1.2.2 | layered materials | avoid: archived (measured by the survey agent, `gh api`) |

Licences and versions: `npm view <pkg> version license` and `gh api
repos/<repo> --jq .license.spdx_id` (measured). Codrops demo code licences
were not checked (see Thin).

## Determinism under a seeked clock

- **HyperFrames' page shim** replaces `Date`, `performance.now` and
  `requestAnimationFrame` with virtual time; queued rAF callbacks run once per
  `seekToTime` with the virtual timestamp (measured, vendored
  `packages/producer/src/services/fileServer.ts:290-380`). `setTimeout` is not
  replaced (measured, `grep`).
- **`Math.random` is not seeded in a local render**: the default shim is built
  with `seedRandomFromFrame: false`; only distributed renders seed it per frame
  (measured, `fileServer.ts:389-393`; both variants present in the 0.8.160
  `dist`). Every particle field needs its own seeded PRNG (inferred), as
  `code-particle-assemble` does.
- **Two seek-safe authoring patterns** exist in the registry (measured):
  1. `hf-seek` listener calling `renderAt(time)` (`canopy-part-title`,
     `cuboid-carousel`, `wireframe-portal-title`, the adapter doc).
  2. a paused GSAP timeline whose `onUpdate` calls `renderer.render`
     (`exploded-stack`, `code-particle-assemble`).
  The adapter doc also forbids clock deltas and "post-processing passes that
  depend on previous frame history" (documented, `adapters/three.md`
  "Avoid").
- **Registry hygiene**: `code-3d-extrude`, `code-particle-assemble` and
  `code-shader-dissolve` still mention `requestAnimationFrame` and load three
  0.147.0, while newer blocks use 0.184.0 to 0.185.1 (measured, `grep` over
  `registry/blocks/*/*.html`). Vendoring a block means pinning one three
  version (inferred).

## Headless Chrome and the GPU

### What Chrome does (documented, Chromium source)

- `chrome-headless-shell` and new headless both force
  `--ozone-platform=headless` and add `--use-angle=swiftshader-webgl` unless
  `--use-gl`, `--use-angle` or `--enable-gpu` is passed
  (`headless/lib/headless_content_main_delegate.cc` about lines 259-271;
  `chrome/browser/headless/headless_mode_init.cc:96-114`, which notes "Vulkan
  initialization crashes unless Angle implementation is specified
  explicitly").
- `--enable-gpu` only stops forcing SwiftShader; "Neither approach guarantees
  that hardware GPU support will be enabled" (`headless/public/switches.h:64-71`).
- Vulkan: feature `Vulkan` is off by default except Android
  (`ui/gl/gl_switches.cc:411`); `--use-vulkan` only initialises it and
  `--enable-features=Vulkan` is needed for compositing
  (`gpu/command_buffer/service/gpu_switches.cc:57-61`); ANGLE-on-Vulkan is the
  default only when Skia also uses Vulkan, because ANGLE's share-group locks
  are otherwise "not thread safe" (`gl_switches.cc`, `IsDefaultANGLEVulkan`).
  The Linux NVIDIA blocklist entries cover only nouveau, drivers older than
  295 and video decode (measured by the GPU agent, scan of
  `gpu/config/software_rendering_list.json`). So Vulkan on Linux desktop is an
  off-by-default path, neither supported nor blocklisted (inferred).
- SwiftShader: the silent WebGL fallback is deprecated and "WebGL context
  creation will soon fail instead"; `--enable-unsafe-swiftshader` opts back in
  and explicit `--use-angle=swiftshader` stays supported
  ([swiftshader.md](https://chromium.googlesource.com/chromium/src/+/main/docs/gpu/swiftshader.md));
  removal shipped on desktop at M139 (measured by the GPU agent, chromestatus
  API, feature 5166674414927872).
- `HeadlessExperimental.beginFrame` needs BeginFrameControl, which is "headless
  shell only" (`Target.pdl:162`); `--deterministic-mode` expands to
  begin-frame control, `--run-all-compositor-stages-before-draw` and four
  more (`headless/lib/browser/command_line_handler.cc:36-54`). No Chromium doc
  says whether BeginFrame works with hardware compositing or WebGL.
- GPU pixels: the GL ES 3.0 spec promises identical results only for the same
  implementation and state, "a weak requirement" (Appendix A.1); Chromium's
  own GPU pixel tests keep "multiple approved images per test" because output
  differs "in a handful of pixels"
  (`docs/gpu/gpu_pixel_testing_with_gold.md:37-43`).

### What HyperFrames does

- **0.8.160 (the skill's pin)**, `getBrowserGpuArgs` (measured, `npm pack
  hyperframes@0.8.160`, `dist/chunk-PLEMSN3E.js`): software is `--use-gl=angle
  --use-angle=swiftshader --enable-unsafe-swiftshader`; Linux hardware is
  `--use-gl=angle --use-angle=gl-egl --enable-gpu-rasterization
  --ignore-gpu-blocklist --disable-software-rasterizer`. The `dist` also carries
  `--deterministic-mode`, `--enable-begin-frame-control` and
  `--run-all-compositor-stages-before-draw`.
- **`main` at `2061154`** (documented by the GPU agent,
  `packages/engine/src/services/browserManager.ts` and `config.ts`):
  - auto mode probes the WebGL renderer string and treats SwiftShader,
    llvmpipe and similar as software;
  - a failed BeginFrame probe relaunches in screenshot capture;
  - software mode is clamped to screenshot capture because BeginFrame "stalls
    the compositor on shader-heavy frames under CPU raster" (not found in the
    0.8.160 `dist`, measured `grep`; so this is newer than the pin);
  - parallel workers "are not bit-identical to each other", with one-level
    differences at 30-frame chunk boundaries, and `--workers 1` is the advice
    for bit-exact output (`docs/prompting/rules-and-anti-patterns.mdx:38`).
- **Open issue**: [#4584](https://github.com/heygen-com/hyperframes/issues/4584),
  `--browser-gpu` with 6 or more workers on one GPU times out the BeginFrame
  probe and silently falls back to screenshot capture (RTX 3090, ANGLE EGL)
  (measured by the GPU agent, `gh issue list`). Closed
  [#1260](https://github.com/heygen-com/hyperframes/issues/1260): Three.js
  black in the MP4 on macOS SwiftShader.

### Remotion's `--gl` values, for the lab record

`vulkan` maps to `--use-angle=vulkan --use-vulkan=native
--disable-vulkan-fallback-to-gl-for-testing --disable-vulkan-surface
--ignore-gpu-blocklist --enable-gpu` plus features `Vulkan,UseSkiaRenderer`;
`swangle` to ANGLE on SwiftShader; `angle-egl` to `--use-angle=gl-egl`
(documented, `packages/renderer/src/open-browser.ts` at `80ec1aad`). Remotion
recommends `angle-egl` for Linux GPUs and captures with
`Page.captureScreenshot`, not BeginFrame (documented,
[gl-options](https://www.remotion.dev/docs/gl-options); measured by the GPU
agent, `grep` of `screenshot-task.ts`). Its docs say nothing about Vulkan
frame drops.

## Why the lab's live 3D failed (#652, #657)

Evidence from the motioncraft session of 2026-10-15 (measured, Python scan of
`~/.claude/projects/-home-ribo-wip-projects-video-lab-motioncraft/a0e907c9-*.jsonl`,
lines 854-891):

- The operator brief fixed `--gl=vulkan --hardware-acceleration=if-possible
  --concurrency=3`.
- The session noted "`--gl=angle` stills lost the dark background on frames
  with 3D", compared vulkan and swangle on frame 99, and concluded: "both
  `angle` and `vulkan` break any frame with WebGL 3D (background and 3D
  vanish); `swangle` renders correctly."
- 90 non-3D frames took 6.1 s on vulkan against 53.5 to 56.5 s on swangle, two
  runs each, so it kept vulkan for the 2D layers and pre-rendered 3D on
  swangle (`cache3d`, 121 s per #652).
- The 3D scene (`src/components/Three.tsx`): `ThreeCanvas` with
  `gl={{alpha: true}}`, `shadows`, `meshPhysicalMaterial` with transmission,
  a PMREM `RoomEnvironment`, and an optional `BokehPass` whose shader the
  project patched because it "forces output alpha to 1" (measured, `grep`).

Contrast, remotion-markup on 2026-10-14 (measured, `grep -oP` over its
session transcript and `src/scenes/*.tsx`): `three/vulkan: OK`,
`three/angle: OK` in an isolated probe; final 62 s render in 33 s with
`--gl=vulkan` at concurrency 6, live R3F Tunnel and Lattice scenes on an
opaque canvas (`<color attach="background">`) with basic and standard
materials. One earlier probe reported "`<ThreeCanvas>` timed out under
`--gl=vulkan`" before the isolated run passed.

So: the failure was a blank composite, reproducible per frame, on both GPU
backends, for one scene shape; not dropped frames. What differs between the
two projects is a transparent canvas over DOM, transmission and shadow passes,
three 0.160 against 0.186, and Remotion 4.0.529 against 4.0.535 (measured).
Which of those triggers it is unknown. My guess is the transparent canvas's
alpha under GPU compositing, since the DOM background vanished with it
(guess). The task ticket can settle it with one opaque and one transparent
canvas per backend.

Two consequences (inferred): the motioncraft verdict says nothing yet about
HyperFrames, whose GPU path is ANGLE GL-EGL with BeginFrame rather than
Remotion's Vulkan with screenshots; and an opaque Three.js canvas with the
overlay text in HTML avoids the one shape known to fail here.

## Implications for the map

- 3D live in the composer is plausible for closed-form scenes (globe, flows,
  morph, exploded stack, SDF text) on an opaque canvas; simulated scenes go
  through the cache (inferred).
- The video gate's equal-pixels rule holds by HyperFrames' own account only for
  SwiftShader or one worker; a GPU-only component needs either a per-frame
  tolerance or `--workers 1` for the determinism run (inferred).
- The measurement ticket should time, per scene, hardware ANGLE GL-EGL against
  SwiftShader at 1 and 3 workers, record `nvidia-smi` peak VRAM and
  `renderer.info.render.drawCalls`, and diff two runs pixel for pixel
  (inferred). `WebGLRenderer.info.memory` gives counts, not bytes;
  `WebGPURenderer` `Info.memory.total` gives bytes (documented,
  [Info](https://threejs.org/docs/pages/Info.html),
  [WebGLRenderer](https://threejs.org/docs/pages/WebGLRenderer.html), via
  `npx ctx7@latest docs /websites/threejs`).

## Thin

- No studio primary source (Active Theory, Lusion, Resn, awwwards) shows an
  explainer-style architecture stack or exploded GLTF; those references are
  tutorials and blogs. Active Theory's and Lusion's write-ups date from 2016 to
  2019. Resn and the threejs.org showcase were not surveyed.
- Codrops demo licences were not checked; treat their code as reference, not
  vendorable, until checked.
- The Three.js Journey GPGPU lesson's particle count is paywalled.
- The motioncraft root cause is unisolated; its comparison images were in a
  scratchpad that no longer exists (measured, `ls`).
- HyperFrames `main` behaviour (screenshot clamp for software, worker
  variance note) is newer than the 0.8.160 pin; which release carries it was
  not checked. crbug 535256667 (stale SwiftShader layer after a BeginFrame
  seek) is fixed in code, milestone unknown.
- No Chromium source says whether BeginFrame works with hardware compositing
  and WebGL; HyperFrames issue #4584 is the only field report.
- Frame time, VRAM and pixel stability on this RTX 2070 Super Max-Q are
  unmeasured by design.
