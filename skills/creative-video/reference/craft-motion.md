# Motion craft

## Contents

- [Decide in numbers](#decide-in-numbers)
- [Stills before the full render](#stills-before-the-full-render)
- [Every library runs on the frame's clock](#every-library-runs-on-the-frames-clock)
- [Charts, shapes and effects](#charts-shapes-and-effects)
- [3D only when the subject is spatial](#3d-only-when-the-subject-is-spatial)
- [Three.js pitfalls](#threejs-pitfalls)

What makes a scene's motion read as authored rather than generated, and what
keeps every frame rendering the same way twice. The `hyperframes` skill holds
the engine's side: `references/spec.md` (the `SPEC.md` template and the
defaults banned by name), `references/motion.md` (eases by role, the defaults
that look generated), `references/review.md` (the stills review) and
`references/runtimes.md` (how each runtime is seeked). This file adds why those
matter and the measured pitfalls the research found. It is knowledge, not a
list to pick from.

## Decide in numbers

The taste is already in the model; what fails is the default look when
nothing is decided. In HeyGen's eval of its skill pack (19 cases, 2 repeats
each), the skills lifted correctness and tool use from 11% to 71%, while a
blind judge scoring the frames alone gave 6.86 and 6.94 without them against
7.21 and 7.11 with them, a gap that swung between runs. Without direction the
model lands on one look: "without a reference, opus falls back to its default
look: centered text, gradient background, everything fading in" (Rexan Wong).
That look reads as generated because it fills every gap an adjective leaves,
identically in every run, so the viewer has seen it in every other generated
video. Its motion signs are the same entrance on every element, one ease at a
uniform 0.5 s, idle loops that breathe, and slides that cut or fade with
nothing carried across ("a PowerPoint slide that learned to move").

So write `SPEC.md` in numbers where you would have written adjectives: hex
values with a role each, the event rate, the ease for each role, durations in
frames, type sizes in px. Diverge before picking: three directions that are
three different films, one the bold one you would not pick first; a single
concept to approve or reject is weaker. Revise one variable at a time with an
absolute target ("slow every zoom to 0.7x"); "make it pop" is not a note, so
end a self-review in numbered, timestamped notes with values. A banned default
is a starting point you may override with a stated reason: style packs
contradict each other (one mandates "idle elements breathe", HyperFrames lists
breathing loops as generated), so taste is yours, and only defects are not.

Budget for many passes: "one prompt" showcases hide long work, such as a
45-second short that took 163 calls and about 7 hours (reported).

## Stills before the full render

You read images, not video, so frames are how you see your own work. Both bar
videos reviewed contact sheets of every scene before the final render; the
game show's agent, with no owner turns at all, found about ten layout bugs that
way (a wrapped logo, a flash showing early, overlapping badges, overflowing
text). Other sessions caught a flicker from unseeded randomness, subtitle words
glued together, a broken logo and a wrong gradient the same way. A still costs
seconds and shows a defect standing still; a full render costs minutes and
hides it in motion.

A fresh-eyes reviewer catches what you cannot. You read your frame through
your plan, so you see the object you meant; a reviewer who has not read the
plan sees what is there: an object that needs explaining ("those bars are
mirrors"), a default that crept in, a frame that says nothing with the
narration covered, a label too small to read in its window. Give it the stills
and nothing of your reasoning. A sheet with a phone-width row also catches type
that only reads at full size.

## Every library runs on the frame's clock

Determinism is a property of the clock, not of the library. In a probe of 12
compositions rendered twice at different concurrency (1 and 4), every library
driven by the frame gave 60 of 60 identical frames: a chart with its own
animation off, D3 used as maths, Observable Plot rebuilt per frame, flubber,
seeded rough.js, CSS keyframes seeked by delay. Every library left on its own
clock failed: Recharts' default animation 39 of 60, a D3 transition 0 of 60,
unseeded rough.js 0 of 60 (one static box boiled into 60 distinct frames),
infinite CSS keyframes 0 of 60. A wall-clock fault looks fine in preview and
jitters between render workers; rendering a few peak-motion frames twice and
comparing their hashes catches any of them without a list of allowed
libraries.

This fits the word anchors. In this skill a scene event anchors to an aligned
word through `window.at(scene, word, nth)`, which returns scene-local seconds
(`authoring.md` holds the anchors). That number is a position on the scene's
timeline: place the tween at it (`tl.to(el, vars, window.at(...))`), or compare
the seek time against it inside an `hf-seek` draw. The anchor says when; the
frame says what: every moving value is computed from the timeline time, so a
re-voice that moves the word moves the event, and each frame still renders from
its time alone.

- **CSS keyframes** seek when their iterations are finite; `infinite` is what
  failed.
- **GSAP** tweens sit at absolute seconds with finite repeats (the
  `hyperframes` skill's `references/runtimes.md`).
- **Randomness** is seeded or it changes per render: HyperFrames' local renders
  do not seed `Math.random` (`seedRandomFromFrame: false`). An After Effects
  `wiggle()` expression in a downloaded Lottie calls `Math.random` (lottie-web
  5.13.0), so that asset jitters differently every render. tsParticles cannot
  seek (a `requestAnimationFrame` clock and state that accumulates step by
  step); a particle field that renders the same is a pure function of a seed
  and the time.
- **Canvas, p5 and Three.js** draw from `e.detail.time` in the `hf-seek`
  listener, never from a `requestAnimationFrame` loop or `THREE.Clock`.

## Charts, shapes and effects

- **Charts**: turn the library's own animation off and feed it values computed
  from the timeline time; in HyperFrames, drive it from a GSAP tween's
  `onUpdate`. Recharts with `isAnimationActive={false}` was 60 of 60 stable.
  D3's `selection.transition()` runs its own clock: use D3 for scales, shapes
  and layout (`d3.scaleLinear`, `d3.line()`) and draw the marks as your own
  SVG each frame. visx animates through react-spring, a wall-clock spring.
  A chart teaches when its motion is the data's change over time, as Hans
  Rosling's bubbles crossing two centuries do.
- **Shape morphs**: flubber stays smooth when a curve morphs into straight
  lines. `@remotion/paths` `interpolatePath(0.02, circle, star)` turned a
  circle of two arc commands into a 10-sided polygon on the first in-between
  frame, a visible pop; its `interpolatePaths()` also needs matching move and
  close commands per subpath. flubber 0.4.2 is MIT and unpublished since 2022.
- **Path draws**: measure with `getTotalLength()` and animate the dash; avoid
  the `pathLength` attribute and `vector-effect: non-scaling-stroke` on a
  dashed path (HyperFrames' `chart-story` README).
- **Shader blocks need WebGPU.** 36 registry blocks (fractal, Worley and Gabor
  noise, aurora, plasma, nebula, godrays and more) bundle the `shaders` library
  on TypeGPU and declare `data-requires-webgpu`. Headless Chrome on the
  measured machine failed with "a usable WebGPU device could not be created".
  The block rendered only with both `PRODUCER_ALLOW_SOFTWARE_WEBGPU=true` and
  `PRODUCER_BROWSER_GPU_MODE=software` (the error names only the first). On
  that software path, 2 s of 1080p30 took 85 and 87 s wall (49 s of setup,
  then about 0.5 s a frame), frame-identical across runs: usable for a short
  loop, too slow for a full-length background. A noise field teaches only when
  the field is data (NASA's Perpetual Ocean streaks follow modelled currents);
  pure noise is texture, and glow and floating particles are banned defaults.
- **Shader transitions** had no teaching example in the research: narrated
  explainers hand over by a carried shape or a camera move, so a shader wipe is
  decoration between ideas.

## 3D only when the subject is spatial

Animation beats static pictures by d = 0.37 overall, d = 0.40 when it
represents the content rather than decorating it, d = 0.76 when highly
realistic and d = 1.06 for procedural skills (Höffler and Leutner, 26 studies).
But interactive 3D cell models helped only high spatial ability students; low
spatial ability students scored lower and reported more load (Huk 2006). Use
3D when the narration depends on a spatial relation: inside, behind, layered,
three or more dimensions of data, a path through a structure. Otherwise a free
3D scene lands on the banned defaults: a dark void with things floating in
it, glow, particles.

What strong 3D teaching shots share (Branch Education's exploded views,
3Blue1Brown's deformed 3D grid, Primer's three-trait scatter): the object is
the subject, not a backdrop; the camera moves only while the narration names
where it goes, and stops where the next noun is; each named part carries a
label in screen space; the whole assembly is the payoff after its parts.
Write a camera path in closed form from the time, such as
`CatmullRomCurve3.getPoint(ease(t))`, and an exploded gap as a function of
`t`, never as a value nudged each frame. Theatre.js is no help: unreleased
since 0.7.2 in 2024, its keyframes live in an exported JSON an agent writes
less legibly than a GSAP timeline.

## Three.js pitfalls

- **drei's ready-made motion runs on the wall clock.** If you use React Three
  Fiber, `useFrame` receives `state.clock` and `delta` that track wall time:
  Remotion renders each frame by calling `advance(performance.now())`, and
  with `frameloop: "never"` R3F sets `clock.elapsedTime` to that timestamp.
  `Float`, `Sparkles`, `Stars`, `Cloud`, `MeshTransmissionMaterial` (its time
  uniform), `MeshDistortMaterial`, `MeshWobbleMaterial` and `CameraShake` read
  it; `Stars`, `Float`, `Cloud`, `Sparkles` sizes and `AccumulativeShadows`
  also call `Math.random`. `@react-three/postprocessing` calls
  `composer.render(delta)`, so its noise, glitch and film grain accumulate wall
  time. A scene with `Float` and `Sparkles` differed on 60 of 60 frames between
  two renders; the same shape driven by the frame differed on 0. Compute each
  moving value from the timeline time yourself; static helpers (geometry,
  `RoundedBox`, `Line`, `Html`, `Text` with the fix below) carry no clock.
- **Stay on `WebGLRenderer`.** Neither engine got hardware WebGPU in headless
  Chrome on the measured machine: Remotion's experimental
  `<ThreeWebGPUCanvas>` fell back to three's WebGL2 backend, and HyperFrames'
  hardware flags gave a SwiftShader (CPU) WebGPU adapter. So TSL node
  materials and compute particles are out; closed-form WebGL shapes cover the
  teaching uses above.
- **troika text needs its sync before the frame.** drei's `<Text>` (troika)
  lays out glyphs after the frame is drawn: frames 0 to 3 came out blank at
  concurrency 4, 0 to 1 at 2, frame 0 at 1. Holding the frame until `onSync`
  alone did not help; calling R3F's `advance()` inside `onSync`, then releasing
  the frame, gave 0 blank frames and 0 of 60 differing. In HyperFrames, wrap
  the text's `sync()` callback in a promise, render inside it, and hand it to
  `e.detail.waitUntil(promise)`, called synchronously in the `hf-seek`
  listener, or register it in `window.__hf.buildReady["<key>"]`. Arabic
  shaped and ordered correctly through troika with a local font file.
- **GPU renders are not bit-stable on HyperFrames.** A lit scene on its GPU
  path differed on 96 to 407 of 2,165 frames between runs, its CLI bans
  hardware GL in distributed renders as "bitwise unstable", and 6 or more GPU
  workers silently fall back to screenshot capture (hyperframes#4584).
