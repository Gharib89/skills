# Three.js and 3D in teaching videos

Research for [#967](https://github.com/Gharib89/skills/issues/967) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.

Baseline, not repeated here: [#653](https://github.com/Gharib89/skills/issues/653)
(`research/explainer-engines`), [#774](https://github.com/Gharib89/skills/issues/774)
(`research/explainer-threejs`, `docs/research/explainer-threejs.md`: scene
archetypes, libraries, seek hazards in HyperFrames, headless GPU flags) and
[#778](https://github.com/Gharib89/skills/issues/778)
(`prototype/explainer-3d-path`: live HyperFrames 3D on the GPU, SwiftShader
for the determinism frame). This file reports only what is new or corrects
them. #774 and #778 measured HyperFrames; the Remotion side of 3D was left at
"root cause unisolated". This ticket measures it.

Labels: **measured** (a command was run, named inline), **sourced** (a primary
source says so, linked or cited by file and line), **inferred** (my reasoning
from those).

Machine: RTX 2070 Super Max-Q, 8 GB, driver 595.99.02, Node 24.20.0.
Versions (measured, `npm view`, 2026-10-26): three 0.186.1, @remotion/three
4.0.539, @react-three/fiber 9.8.2, @react-three/drei 10.7.9,
@react-three/postprocessing 3.2.2, postprocessing 6.39.5, troika-three-text
0.52.5, @theatre/core 0.7.2, hyperframes 0.8.203.

## Answer, ranked by how much it changes the new skill

1. **Freely authored React Three Fiber in Remotion is not deterministic by
   default, and the reason is one line.** `@remotion/three` renders each frame
   by calling `advance(performance.now())` (sourced,
   `@remotion/three@4.0.539` `dist/esm/index.mjs:61-67`). With `frameloop:
   "never"` R3F then sets `clock.elapsedTime = timestamp` and `delta =
   timestamp - elapsedTime` (sourced, `@react-three/fiber@9.8.2`
   `dist/events-*.esm.js:17518-17526`), so every `useFrame` callback sees the
   wall clock, in milliseconds. drei's ready-made motion reads exactly that
   clock: `Float`, `Sparkles`, `Stars`, `Cloud`, `MeshTransmissionMaterial`
   (time uniform), `MeshDistortMaterial`, `MeshWobbleMaterial`, `CameraShake`;
   `Stars`, `Float`, `Cloud`, `Sparkles` sizes and `AccumulativeShadows` also
   call `Math.random` (sourced, `grep` of `@react-three/drei@10.7.9`
   `core/*.js`). `@react-three/postprocessing` renders with
   `composer.render(delta)` inside `useFrame` (sourced, `dist/index.js:431-446`),
   so pmndrs `EffectPass` time (noise, glitch, film grain) accumulates that
   wall-clock delta (inferred, with #774's `EffectPass.js:575`).
   **Measured**: a scene with drei `Float` and `Sparkles` differs on 60 of 60
   frames between two renders, on `--gl=angle`, `vulkan` and `swangle` alike
   (`seq.sh DreiClock <gl> 1|2`, `compare.py`). The same scene shape driven only
   by `useCurrentFrame()` differs on 0 of 60. Remotion's own docs say the
   same rule in prose ("you must write your animations declaratively using
   Remotion's `useCurrentFrame` API" instead of `useFrame`, sourced,
   [ThreeCanvas](https://www.remotion.dev/docs/three-canvas)), but nothing
   enforces it. **For a skill whose stance is maximum freedom**, this is the
   defect most likely to ship: an agent reaching for the drei catalogue gets
   motion that looks fine in preview and jitters between render tabs. It needs
   a gate, not a style rule: a two-render equal-pixels check of a 3D scene's
   peak-motion frames, plus a cheap lint for `useFrame` reading
   `clock`/`delta` and for `Math.random` without a seed (inferred).

2. **On Remotion, this GPU's 3D frames were bit-stable; on HyperFrames (#778)
   they were not.** Remotion `--gl=angle` and `--gl=vulkan` both land on
   `ANGLE (NVIDIA, Vulkan 1.4.329 (NVIDIA GeForce RTX 2070 Super with Max-Q
   Design ...))` (measured, `GLInfo` still reads `UNMASKED_RENDERER_WEBGL`),
   and produce identical frames to each other. A lit exploded stack with
   soft shadows (R3F `shadows`, `meshStandardMaterial`), and a transparent
   canvas with a transmission sphere and a PMREM `RoomEnvironment`, rendered
   at concurrency 3, differ on **0 of 60 frames across 3 runs each** (measured,
   `seq.sh Opaque|TransparentHeavy angle 1..3`). #778 measured 96 to 407
   differing frames of 2,165 for a lit scene on HyperFrames' ANGLE GL-EGL path
   with BeginFrame capture. Not like for like (different scene, length,
   capture path and ANGLE backend), so this is a lead for the engine ticket
   ([#966](https://github.com/Gharib89/skills/issues/966)), not a verdict:
   if it holds for the #778 trails scene, Remotion keeps an equal-pixels gate
   on the GPU with no SwiftShader detour (inferred). The probe that settles it
   is the #778 trails scene ported to `ThreeCanvas`, five alternating runs.

3. **3D earns its place when the subject is spatial, and costs learners when
   it is decoration.** Huk (2006) found interactive 3D models in a cell
   biology lesson helped only high spatial ability students; low spatial
   ability students scored lower and reported higher cognitive load (sourced,
   [doi:10.1111/j.1365-2729.2006.00180.x](https://doi.org/10.1111/j.1365-2729.2006.00180.x)).
   Höffler and Leutner's meta-analysis (26 studies, 76 comparisons) found
   animation beats static pictures at d = 0.37 overall, d = 0.40 when
   representational rather than decorational, d = 0.76 when highly realistic,
   d = 1.06 for procedural-motor knowledge (sourced,
   [doi:10.1016/j.learninstruc.2007.09.013](https://doi.org/10.1016/j.learninstruc.2007.09.013)).
   HyperFrames' own current skill bans "glow, bloom, neon ... floating
   particles as decoration" and "a black or dark navy void ... with small
   elements floating in its middle" as defaults (sourced, vendored
   `.claude/skills/hyperframes/references/spec.md:50-62` at `683e9b1`), which
   is where a free 3D scene lands by default (inferred). So the teaching craft
   should carry a test, not a menu: use 3D when the narration depends on a
   spatial relation (inside, behind, layered, three or more dimensions of
   data, a path through a structure), move the camera only while the
   narration names where it goes, and keep a label on each part it names
   (inferred, from the examples below).

4. **troika text (drei `<Text>`) is missing from the first frame each Remotion
   tab renders, and one `advance()` fixes it.** drei's `Text` suspends on
   `preloadFont` (sourced, `core/Text.js:34-37`), yet the glyph layout still
   lands after R3F has drawn. Measured on `--gl=angle`: frames 0 to 3 blank
   at concurrency 4, 0 to 1 at 2, 0 at 1, the same on `vulkan` and `swangle`
   (`seq.sh ArabicText`, a white-pixel scan). A `delayRender` released in
   `onSync` alone did not help (still 4 blank). Calling R3F's `advance()` in
   `onSync` and then releasing the frame gave 0 blank frames and 0 of 60
   differing across two runs (measured, `ArabicTextSynced`). Arabic shapes and
   orders correctly through drei `Text` with a local IBM Plex Sans Arabic
   file (measured, frame inspected). Remotion's docs state the general rule:
   after an async texture update "call `advance(performance.now())` instead of
   `invalidate()`" (sourced, ThreeCanvas behaviour notes). The HyperFrames
   equivalent stays #774's `__hf.buildReady` registration, or
   `e.detail.waitUntil(promise)` inside the `hf-seek` listener (sourced,
   vendored `references/runtimes.md`; present in both 0.8.160 and 0.8.203,
   measured `grep` of the runtime).

   ```tsx
   const SyncedText = ({onSynced, ...p}) => {
     const advance = useThree((s) => s.advance);
     const onSync = useCallback(() => { advance(performance.now()); onSynced(); }, [advance, onSynced]);
     return <Text {...p} onSync={onSync} />;
   };
   ```

5. **Neither engine gets hardware WebGPU on this machine as shipped, so stay
   on `WebGLRenderer`.**
   - Remotion's `<ThreeWebGPUCanvas>` (new in `@remotion/three/webgpu`,
     "EXPERIMENTAL", needs three 0.167+, R3F 9, React 19; sourced,
     [three-webgpu-canvas](https://www.remotion.dev/docs/three-webgpu-canvas))
     reported three's **WebGL2 fallback backend** on `angle`, `vulkan` and
     `swangle` (measured, `stills.sh`, the `WebGPU` composition prints
     `renderer.backend`).
   - HyperFrames 0.8.203 adds `--enable-unsafe-webgpu` in hardware mode but
     enables Chrome's `Vulkan` feature only for software WebGPU (sourced,
     `dist/chunk-KBCV6BHL.js:1501-1560`). In its cached
     `chrome-headless-shell` 152.0.7977.30, HyperFrames' Linux hardware flags
     yield a WebGPU adapter of `google | swiftshader`, a CPU device; adding
     `--enable-features=Vulkan` yields `nvidia | turing` (measured,
     `probe.mjs`). So a `data-requires-webgpu` scene renders WebGPU on the CPU
     here. Worth an upstream issue; not worth designing around (inferred).
   - Consequence: TSL node materials and compute particles (#774's 200,000
     particle example) are off the table for now; the closed-form WebGL
     shapes #774 listed cover the teaching uses below (inferred).

6. **Corrections to #774 on the Remotion lab record.**
   - The motioncraft blank composite did not reproduce on current versions:
     a transparent (`alpha: true`) canvas over a DOM background, with
     shadows, a transmission material and a PMREM environment, rendered the
     3D and the background on every frame on `angle`, `vulkan` and `swangle`
     (measured, `TransparentHeavy`, 60 frames each, background-pixel scan).
     #774's guess (the transparent canvas's alpha) is therefore wrong as
     stated; what remains of motioncraft's shape is three 0.160, Remotion
     4.0.529 and its patched `BokehPass` (inferred).
   - `--gl=angle-egl`, which Remotion's docs recommend for Linux GPUs (#774),
     fails here with `THREE.WebGLRenderer: Error creating WebGL context`
     (measured, `stills.sh`), while `--gl=angle` already reaches the NVIDIA GPU
     through ANGLE on Vulkan (measured, item 2). Use `angle`.

7. **Theatre.js is not a fit for an agent.** Its public repo's last commit is
   2024-04-11 ("Add the 1.0 notice": development "temporarily moved ... to a
   private repo"), the last npm release is 0.7.2 of 2024-05-19 (measured,
   `gh api repos/theatre-js/theatre/commits`, `npm view @theatre/core time`).
   Core is Apache-2.0, Studio (the keyframe editor) is AGPL-3.0-only
   (measured, `npm view`). Seeking is clean (`sheet.sequence.position = t`,
   sourced, [core API](https://www.theatrejs.com/docs/latest/api/core)), but
   keyframes live in a Studio-exported state JSON keyed by sheet and object
   ids (sourced, same docs); an agent writes the same camera path more
   legibly as `interpolate()` or a GSAP timeline (inferred).

8. **HyperFrames since the 0.8.160 pin (#778), 3D-relevant only.** 0.8.203 is
   current (measured, `npm view`). Unchanged: Linux GPU flags (ANGLE GL-EGL),
   `Math.random` unseeded in local renders (`VIRTUAL_TIME_SHIM` built with
   `seedRandomFromFrame: false`, sourced, `dist/chunk-UNBGZQZ6.js:654`), the
   "Hardware GL is bitwise unstable" ban on distributed GPU renders (`:8315`).
   Changed: `--workers auto` no longer drops a WebGL film of 900 or more
   frames to one worker (fixed in 0.8.182, sourced,
   [hyperframes#5604](https://github.com/heygen-com/hyperframes/issues/5604)).
   Still open: [#4584](https://github.com/heygen-com/hyperframes/issues/4584),
   6 or more GPU workers silently fall back to screenshot capture.

## Teaching uses of 3D, with examples

Timestamps are the videos' own chapter marks (sourced, `yt-dlp --dump-json`
chapters). Each "seen at" frame was pulled and looked at (measured, `yt-dlp
--download-sections` plus `ffmpeg`, one 360p frame). None of these were made
with Three.js; they are references for what the shot does, and the right
column says how each maps onto a seek-safe Three.js shape from #774.

| Technique | Example (chapter, seen at) | What the 3D does that 2D cannot | Seek-safe shape |
| --- | --- | --- | --- |
| Exploded view with callouts | Branch Education, [How does Starlink Satellite Internet Work?](https://www.youtube.com/watch?v=qs2QcycggWU&t=208s), 3:28 "Parts Inside a Dishy McFlatface", seen at 3:50: the dish's layers stacked apart, one labelled "Aluminium Backplate" | shows order and containment of layers at once | #774 exploded stack, `gap = f(t)`, labels as projected HTML (#778) or drei `Html` |
| Exploded teardown | Branch Education, [How do CPUs Work?](https://www.youtube.com/watch?v=16zrEPOsIcI&t=208s), 3:28 "Teardown of a Laptop", seen at 3:45: board, battery and parts pulled apart | where the part sits in the whole before zooming in | same, per-part offsets along `normalize(part - centre)` |
| Object to diagram zoom | same video, 4:39 "A CPU Die", seen at 5:00: die photo with the core's block diagram laid over it | ties an abstract block diagram to physical silicon | orthographic push-in, a textured plane crossfading to an SVG/HTML diagram |
| Camera flight to the subject | Branch Education, [How do Graphics Cards Work?](https://www.youtube.com/watch?v=h9Z4oGN89MU&t=296s), 4:56 "GPU GA102 Architecture", seen at 5:10: the card in 3D, camera moving onto the chip | scale and location: where the thing lives | closed-form camera path (`CatmullRomCurve3.getPoint(ease(t))`), no `useFrame` |
| Show the data the machine works on | same video, 17:49 "Object Transformations", seen at 18:05: a cowboy hat model drawn as its vertices | makes "a model is a list of vertices" literal | `THREE.Points` on the mesh's own positions, morph by `uProgress` (#774 particle morph) |
| Full assembly after parts | Animagraffs, [How a Car Engine Works](https://www.youtube.com/watch?v=ZQvfHyfgBtA&t=448s), 7:28 "Full Model", seen at 7:35: the whole engine with exhaust after one chapter per subsystem | the payoff shot: each explained part in place | visibility per subsystem by chapter, cutaway by `clippingPlanes` (#774 `webgl_clipping_stencil`) |
| Transforming space | 3Blue1Brown, [Three-dimensional linear transformations](https://www.youtube.com/watch?v=rHLEWRxRGiM&t=52s), 0:52 "3D transformations", seen at 1:10: a 3D grid deformed by a matrix, basis vectors coloured | a 3x3 matrix as a motion of all of space | grid `LineSegments` with positions `lerp(p, M p, t)` computed per frame |
| Directions in data space | 3Blue1Brown, [Transformers, the tech behind LLMs](https://www.youtube.com/watch?v=wjZofJX0v4M&t=747s), 12:27 "Word embeddings", seen at 15:00: E(woman) minus E(man) as arrows over a 3D grid floor | "meaning is a direction" needs more than two axes | arrows from `ArrowHelper` or cones on lines, slow orbit `angle = f(t)` |
| Three variables at once | Primer, [Simulating Natural Selection](https://www.youtube.com/watch?v=0ZGbIKd0XrM&t=353s), 5:53 "Multi-trait evolution", seen at 6:40: speed, size and sense as a 3D scatter | three traits co-evolving, one point per creature | instanced points, positions from data, appear by `setDrawRange` |
| Projecting a higher dimension | 3Blue1Brown, [Visualizing the 4d numbers Quaternions](https://www.youtube.com/watch?v=d4EgbgTm0Bg&t=1045s), 17:25 "Mapping 4d to 3d", seen at 20:50: the unit quaternion "1" on 3D axes | stereographic projection made visible | closed-form projection in a vertex shader, parameter `t` |
| Wave fields | Branch Education, Starlink, 18:54 "Starlink: Phase Array Beam Steering", seen at 19:10: two antennas' wavefronts and the constructive-interference beam | interference is a spatial pattern | shader plane, `sin(k r - w t)` per antenna, `t` from the seek |

Not used, checked: Welch Labs' [AlexNet video](https://www.youtube.com/watch?v=UZDiGooFs54)
frames at 8:20 and 9:20 were 2D; Sebastian Lague's
[Simulating Fluids](https://www.youtube.com/watch?v=rSKMYc1CQHE) at 45:00 and
46:00 showed code and the Unity editor (measured, frames). A simulated fluid
is #774's "not seek-safe, bake it" case anyway.

What the examples share (inferred): the 3D object is the subject, not a
backdrop; the camera move ends where the narration's next noun is; each named
part gets a label in screen space; the full assembly is the payoff after the
parts. This is craft knowledge for the skill, not a component list.

## How, per engine

**Remotion (`@remotion/three`)** (sourced unless marked):

- `<ThreeCanvas width height>` wraps R3F's `Canvas`; during a render it forces
  `frameloop: "never"` and advances once per frame; a `<Sequence>` inside it
  needs `layout="none"` ([docs](https://www.remotion.dev/docs/three-canvas)).
- Everything moving is a function of `useCurrentFrame()`. Banned in practice:
  `useFrame` reading `state.clock` or `delta`, drei's clocked components (item
  1), unseeded `Math.random`, `@react-three/postprocessing` time effects
  (inferred from item 1). Static drei helpers (geometry, `RoundedBox`, `Line`,
  `Html`, `Text` with the sync fix) carry no clock (inferred, `grep`).
- `useOffthreadVideoTexture()` gives the exact video frame as a texture during
  renders; `useVideoTexture()` is the Studio and Player variant
  ([docs](https://www.remotion.dev/docs/three)). Useful for a screen recording
  on a 3D monitor.
- Render with `--gl=angle` on this machine (item 6). Remotion 5.0 will default
  to ANGLE with a SwiftShader fallback (sourced, three-webgpu-canvas page);
  5.0 is not released (measured, `npm view remotion dist-tags`: latest
  4.0.539).

**HyperFrames (Three.js adapter)**: #774 and #778 stand. One addition: async
per-frame work (troika sync, a WebGPU `renderAsync`) goes in
`e.detail.waitUntil(promise)`, called synchronously in the `hf-seek` listener
(sourced, the runtime's seek dispatcher in `hyperframe.runtime.iife.js`:
"hf-seek waitUntil() must be called synchronously from the event listener").

## Probe

Source on this branch: `prototypes/creative-threejs-probe/` (never merged).
`bun install`, put an Arabic `.ttf` at `public/arabic.ttf` (the probe used IBM
Plex Sans Arabic Bold, OFL), then `bash stills.sh`, `bash seq.sh <comp> <gl>
<run> [concurrency]`, `python3 compare.py out`, and `node probe.mjs <path to
chrome-headless-shell>`. Compositions are 640x360 at 30 fps, 60 frames.

| Measurement | angle | vulkan | swangle |
| --- | --- | --- | --- |
| Renderer | ANGLE Vulkan, NVIDIA | ANGLE Vulkan, NVIDIA | ANGLE Vulkan, SwiftShader |
| `Opaque` run to run differing | 0/60 (3 runs) | 0/60 | 0/60 |
| `TransparentHeavy` run to run differing | 0/60 (3 runs) | not repeated | 0/60 (2 runs) |
| `TransparentHeavy` frames missing 3D or background | 0/60 | 0/60 | 0/60 |
| `DreiClock` run to run differing | 60/60 | 60/60 | 60/60 |
| `ArabicText` blank frames, concurrency 4 | 4 (frames 0-3) | 4 | 4 |
| `ArabicTextSynced` blank frames, concurrency 4 | 0 (2 runs, 0/60 differ) | not run | not run |
| `WebGPU` backend | WebGL2 fallback | WebGL2 fallback | WebGL2 fallback |

`--gl=angle-egl`: every composition failed to create a WebGL context.
`Opaque` angle and vulkan frames are identical to each other; swangle differs
from both on 60/60 (measured), as expected from a different rasteriser.

## Thin

- Item 2 compares unlike scenes; the decisive run (the #778 trails scene in
  `ThreeCanvas`, five alternating runs, GPU and SwiftShader) is not done.
- Remotion render wall times were not compared: the 60-frame probes are
  dominated by bundling (5 to 21 s each, measured) and say nothing about
  per-frame 3D cost.
- drei `Html` labels under `frameloop: "never"` were not rendered; that they
  track the camera on the same frame is inferred from drei running its
  projection in `useFrame` before Remotion takes the frame.
- The motioncraft blank composite is now unreproduced rather than explained.
- Example videos were checked at one frame each; the "seen at" description is
  of that frame, not of the whole chapter.
