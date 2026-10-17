# HyperFrames today, at 0.8.169

Research for [#771](https://github.com/Gharib89/skills/issues/771) on the map
[#770](https://github.com/Gharib89/skills/issues/770). Date: 2026-10-17.
Builds on `research/explainer-engines` (#653) and `research/explainer-effects`
(#657); what they settled (licence, Arabic shaping, lab render costs, the
technique survey) is not repeated here.

Labels: **measured** (a command was run on this machine, named inline; reading
a file of the HyperFrames clone at tag `v0.8.169` with `git show`, `sed` or
`grep` counts as measured), **inferred** (my reasoning from measured facts),
**guess** (no direct evidence).

Sources: npm (`npm view`, `npm pack`), a clone of
[heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) at `main`
`20611541b` (2026-10-17) with tags `v0.8.160` and `v0.8.169`, its `releases/`
notes, and real renders on this machine (RTX 2070 Super Max-Q) through the
skill's own Chrome home (`~/.cache/explainer-video/chrome/...`).

## Answer

1. **Upgrading 0.8.160 to 0.8.169 is a pin bump, not a migration.** No
   release note between them says breaking, deprecated, removed or renamed
   (measured, `grep -inE 'break|deprecat|remov|renam' releases/v0.8.16[1-9].md`:
   no hit). The render flags, `check --json --at`, `browser ensure`, the
   runtime file and the pinned Chrome (150.0.7871.124) are unchanged
   (measured, below). A 30 s cut of the real `dora-core` video and all 39 of
   its stills render **pixel-identical** under both versions (measured,
   `ffmpeg -f framemd5`), and `hyperframes check` returns the same report.
   Nothing in `scripts/render/` has to change.
2. **The one behaviour change that matters to us is RTL**: 0.8.168 dropped the
   `html_dir_attribute_breaks_render` lint (#5744). A page with
   `<html lang="ar" dir="rtl">` fails lint on 0.8.160 and passes on 0.8.169;
   it rendered correctly on both (measured, below). So `--strict` no longer
   forbids `dir` on `<html>`; the composer's per-element `dir` still works.
3. **The composer uses none of HyperFrames' extras** (measured,
   `grep -nE "registry|shader|HyperShader|vfx|__hfThree|__hfLottie|__hfAnime|transition"`
   over `scripts/render/compose.mjs` and `render.mjs`: no hit). Unused today:
   21 agent skills, 210 blocks, 237 components, 14 shader transitions (plus
   33 transition blocks and 37 transition components), 5 `data-vfx-chain`
   kernels, 7 documented seek adapters (plus 5 undocumented readiness
   adapters), and 30 camera items.
4. **Recount** of the 2026-10-15 numbers: skills 21, blocks 210, shader
   transitions 14 all hold. Components are **237, not 238**: the earlier
   `ls | wc -l` counted `registry/components/CATALOG.md` (measured,
   `git ls-tree v0.8.160:registry/components | grep -v tree`). None of the four
   counts moved between 0.8.160 and 0.8.169; `registry/` has an empty diff
   (measured, `git diff --stat v0.8.160 v0.8.169 -- registry`).
5. **Determinism on this GPU holds for WebGL, Three.js and Lottie, and WebGPU
   is the gap.** A WebGL shader-transition block, a Three.js block and a
   Lottie block each rendered twice on the hardware GPU with 0 differing
   frames. The 40 WebGPU blocks refuse on the hardware path here ("no hardware
   WebGPU adapter") and on SwiftShader take 240 to 386 s for a 2 s clip
   (deterministic, but about 100 times over the map's render budget) (measured,
   below).

## Upgrade 0.8.160 to 0.8.169

### What changed (62 commits, 9 releases, 2026-10-15 to 2026-10-17)

Measured, `git log --format='%h %s' v0.8.160..v0.8.169` and `releases/v0.8.16*.md`:

| Area | Change | Touches us? |
| --- | --- | --- |
| Lint | `html_dir_attribute_breaks_render` removed; a producer render test (`packages/producer/tests/html-dir-rtl`) now guards RTL export (#5744, 0.8.168) | Yes: `<html dir="rtl">` now passes `--strict` (measured below) |
| Lint, timeline | Lint flags clips nested in a timed element that never show (#5732) | No finding on `dora-core` (measured, `check` lint `errorCount` 0) |
| Check | Overlap pass: at most 240 samples, half uniform, skips runtime-hidden scenes; video-alpha text judging; geometry seeks skip video waits (#5764, #5770, #5758, #5657, #5715) | Same report on `dora-core` (measured below) |
| Core runtime | Scenes stop animating after their clip ends; hold a clip at 0 until due; scrub-back fixes; caption line after a jump back; timed SVG clips hide outside their window (#5741, #5716, #5766, #5690, #5661, #5693, #5692) | Frames identical on the measured cut (measured); these target preview playback (inferred from titles) |
| Producer | Render at 720p and 480p from a larger composition (#5724); 25 fps for distributed renders (#5423); one-pass assemble (#5768) | New options only; we render 1080p30 locally |
| CLI | Telemetry adds CPU busy (#5646); sandbox and Chrome warm-up messages (#5734, #5705, #5781) | No; telemetry is off in `hyperframesEnv()` |
| Beats | `beats` without Chrome, TypeScript tracker (#5634) | No; `dist/beat-analyzer.global.js` is gone from the npm package (measured, `ls dist` diff of `npm pack` 0.8.160 vs 0.8.169), the skill never loads it (measured, `grep -rn "beat-analyzer\|hyperframes.*beats" skills/explainer-video/scripts`: no hit) |
| Build | NodeNext-resolvable declarations from every package (#5532) | No |

- **Dependencies**: `dependencies`, `bin` and `engines` of the `hyperframes`
  package are byte-identical between the two tarballs (measured,
  `diff` of `jq '{dependencies,bin,engines}'` over `npm pack` output).
- **Chrome**: both pin `150.0.7871.124` (measured, `grep -oE '1[3-5][0-9]\.0\.[0-9]{4}\.[0-9]+'`
  over each `dist/`), so `ensureChrome`'s download and `findChrome` are
  untouched, and the Chrome home still sits under `homedir()/.cache/hyperframes/chrome`
  with no setting to move it (measured, `packages/cli/src/browser/manager.ts:61`).
- **Render flags**: the only diff in `packages/cli/src/commands/render.ts` is
  CPU telemetry and a sandbox remediation (measured, `git diff v0.8.160 v0.8.169 -- packages/cli/src/commands/render.ts`).
  `--strict --quiet --fps --workers --quality looks --format png-sequence -o`
  all still exist.
- **Runtime contract the probe uses**: `dist/hyperframe.runtime.iife.js` still
  ships (measured, `ls dist`), and no diff in `packages/core|engine|producer`
  touches `__renderReady`, `__hfStartupError`, `__player.renderSeek`,
  `__hf.seek`, `__hfWaitForSeekCompletion` or `data-no-timeline` (measured,
  `git diff ... | grep -E 'window\.__|renderSeek|data-no-timeline'`: only test
  fixtures).

### Proof on the real composition

All measured on this machine, scratch copies of
`explainer-videos/explainers/dora-core/composition`, root `data-duration`
cut from 978.71 to 30, the skill's exact render arguments
(`render --strict --quiet --fps 30 --workers 3 --quality looks`), the skill's
Chrome home, telemetry off:

| Run | Result |
| --- | --- |
| 0.8.160 video | exit 0, 900 frames, wall 24.4 s |
| 0.8.169 video, twice | exit 0, 900 frames each, wall 27.3 s and 29.5 s |
| Decoded frames, 0.8.160 vs 0.8.169 | **0 of 900 differ** (`ffmpeg -map 0:v -f framemd5`) |
| Decoded frames, 0.8.169 vs 0.8.169 | 0 of 900 differ |
| Audio | same MD5 on all three (`ffmpeg -map 0:a -f md5`) |
| Stills page (`stillsPage()` from `compose.mjs`, 39 scenes, `--format png-sequence`) | 39 PNGs each; **0 of 39 differ** in decoded RGBA (`cmp` of `ffmpeg -f rawvideo -pix_fmt rgba`) |
| `check --json --at 2,10,20,28` | exit 0 both; reports equal after removing version, run id and paths (`jq -S` then `diff`) |

The wall times are one or two runs each, so they are no speed verdict
(inconclusive).

### What upgrading touches

- `skills/explainer-video/package.json`: `"hyperframes": "0.8.169"`, and a
  regenerated `package-lock.json` (measured, `grep -rn 0.8.160`: these two
  plus the comment below, the derived `.claude/skills/` copy, and ADR 0012's
  dated evidence line).
- `skills/explainer-video/scripts/lib/backend.mjs:42`: the comment naming
  0.8.160 as the version that downloads Chrome to the home folder (still true
  of 0.8.169, measured above).
- **Nothing in `skills/explainer-video/scripts/render/`** (measured, identical
  frames and stills; and `grep` shows `render.mjs` only passes CLI flags that
  are unchanged).
- Every run re-renders once after the bump: `renderInputs` hashes
  `package-lock.json` into the render and stills cache keys (measured,
  `scripts/lib/tools.mjs:19`), so old caches miss (inferred).
- ADR 0012 cites "HyperFrames 0.8.160, `dir="rtl"` scoped to text elements";
  it stays true as history, no edit needed (inferred).
- Optional, not required: with the lint gone the composer could put
  `dir="rtl"` on `<html>` for Arabic runs instead of per element. Not worth a
  change unless a new component needs page-level direction (inferred).

### RTL lint, measured

A one-clip page `<html lang="ar" dir="rtl">` with the line
`مرحبا بالعالم Kubernetes`, rendered without `--strict`:

- 0.8.160: `lint --json` reports 1 error, `html_dir_attribute_breaks_render`;
  render exit 0, frame at 0.9 s mean luma 219.5, text shaped and right
  aligned (measured, `ffmpeg signalstats` and a viewed PNG).
- 0.8.169: lint 0 errors; render identical luma (measured, same commands).

So the blank-video bug the lint guarded was already fixed by 0.8.160 on this
machine; only the lint lagged (inferred). The map's Arabic parity rule is
unaffected by the upgrade.

## Inventory at 0.8.169

### Agent skills (21)

Licence: the repository's Apache-2.0 for all (measured, `LICENSE`, `CREDITS.md`
"All code in this repository is ... distributed under the Apache 2.0
License"). Exceptions inside: `talking-head-recut` is adapted from
vtake-skills (MIT, notice retained in `skills/talking-head-recut/NOTICE.md`),
and `hyperframes-creative` vendors three OFL-1.1 fonts (measured,
`find skills -iname 'LICEN*' -o -iname 'NOTICE*' -o -iname 'OFL*'`). The set
and its files are unchanged since 0.8.160 (measured, `git ls-tree`).

Measured, `SKILL.md` frontmatter of each, file count by `find | wc -l`:

| Skill | Files | What it gives an explainer | Use for us |
| --- | --- | --- | --- |
| `hyperframes` | 31 | Mandatory entry point and router | Reference only |
| `hyperframes-core` | 11 | Composition contract: `data-*` timing, `class="clip"`, tracks, sub-compositions | Already followed |
| `hyperframes-animation` | 122 | 12 adapter notes, 22 scene blueprints (`camera-journey`, `kinetic-type-beats`, `dataviz-countup`, `spatial-pan-stations`, `constellation-hub`), 48 motion rules, 15 CSS transition families | **Highest value**: vendor as reference for camera, kinetic type, transitions |
| `hyperframes-keyframes` | 3 | Seek-safe punch-in, Ken Burns, camera moves, match and whip handoffs, depth rules | High: camera grammar |
| `hyperframes-creative` | 79 | Design spec handling, palettes, typography, beat planning | Medium: style profile schema 2 |
| `hyperframes-registry` | 12 | Search, install and wire registry items | Needed if we vendor blocks |
| `motion-graphics` | 23 | Kinetic type, count-up, chart hit, map, lower-third | Medium |
| `faceless-explainer` | 29 | Text to explainer, our exact job, as an orchestrated flow | Compare, not compose: it runs `init`, `skills update` against GitHub and HeyGen `auth status` (measured, its Step 0) |
| `hyperframes-audio` | 8 | Mix: fades, ducking, voiceover carve | Out of scope (voice and score stay) |
| `hyperframes-cli` | 11 | The CLI loop | Reference |
| `general-video`, `product-launch-video`, `pr-to-video`, `music-to-video`, `slideshow`, `talking-head-recut`, `embedded-captions`, `media-use`, `figma`, `remotion-to-hyperframes`, `hyperframes-studio` | 2 to 169 | Other workflows | No |

Documentation: `docs/guides/skills.mdx` covers installing the set
(`npx skills add heygen-com/hyperframes`), and eight creation workflows have
their own guide (`faceless-explainer`, `general-video`, `motion-graphics`,
`slideshow`, `pr-to-video`, `product-launch-video`, `music-to-video`, captions
and recuts); the core and reference skills are documented only by their own
`SKILL.md` (measured, `ls docs/guides`). No skill is marked experimental; the
one `grep -l experimental skills/*/SKILL.md` hit, `talking-head-recut`, names
a style family, not a status (measured). Composing them live is a poor fit: several call home
(`skills update`, HeyGen sign-in, `media-use`'s catalog), which breaks the
skill's pinned, offline render (inferred). Vendoring their reference files
through the lock, as the map allows, fits.

### Registry: 210 blocks, 237 components, 8 examples

Measured, `registry/registry.json` item types and each `registry-item.json`.

- **Licence**: 415 of 455 items carry no `license` field, so the repository's
  Apache-2.0 applies (inferred from `CREDITS.md`). 36 WebGPU shader blocks say
  `Apache-2.0 AND MIT` (they vendor `shaders` 4.0.0, MIT, per
  `lib/shaders.THIRD-PARTY-LICENSES.txt`); `weight-wave` is `OFL-1.1`;
  `caret-swap` is `MIT AND OFL-1.1`; `kinetic-center-build` is `MIT`. The seven
  3D-motion blocks vendor three.js (MIT), GSAP 3.14.2 (GSAP Standard
  License), three-mesh-bvh, opentype.js (MIT), Clipper (BSL-1.0) and d3-delaunay
  (ISC); six of their texture assets are "origin to be confirmed with the
  author" (measured, `CREDITS.md`). Those six assets fail a commercial-safe
  default until confirmed (inferred).
- **Experimental**: 19 items carry `"stability": "experimental"`: 18 blocks
  (`cosmic-orb`, `gallery-tunnel`, `halftone-field`, `ios26-liquid-glass`,
  `liquid-glass-notification`, `liquid-glass-widgets`, `lt-neon-border`,
  `macos-tahoe-liquid-glass`, `rack-focus`, `spiral-galaxy`, eight `vfx-*`)
  and 1 component (`filmed-screen`). The rest carry no stability flag, so
  documented (measured; each of the 210 and 237 has a page under
  `docs/catalog/blocks|components`, `ls | wc -l`).
- **Shape**: 195 of 210 blocks are 1920x1080 (measured). Blocks are whole
  timed scenes (`duration` 2 to 25.8 s, all 210 carry one); components are
  primitives with no duration (measured, `duration` over every
  `registry-item.json`: 210 blocks and 8 examples have one, 0 components).
- **Network**: blocks load GSAP and Lottie from `cdn.jsdelivr.net` (measured,
  `grep '<script src'` in `whip-pan`, `lottie-character-walk`); the
  composer's lint refuses `../` assets and keeps everything local, so a
  vendored block needs its CDN scripts rewritten to local copies (inferred).
- **RTL**: only 3 registry files mention RTL at all (measured,
  `grep -rliE '\brtl\b' registry`). Items are authored left to right, and the
  per-character type components (`char-slam-explode`, `top-down-letters`,
  `scramble-reveal`, `matrix-decode`, `typewriter` and kin) would break Arabic
  joining under the map's whole-words rule (inferred). Each vendored item
  needs an Arabic check.

Families by tag (measured, tag tally plus name match; an item can be in
several):

| Family | Blocks | Components | Examples |
| --- | --- | --- | --- |
| Transitions | 33 | 37 | `transitions-push`, `-radial`, `-3d`, `-blur`, `whip-pan`, `sdf-iris`; `match-cut`, `iris-reveal`, `zoom-through-transition`, `whip-pan-cut` |
| Camera | 10 | 20 | `camera-dolly-zoom`, `rack-focus` (experimental), `frost-sequence-camera-orbit`; `push-in`, `pull-back-reveal`, `pan-stations`, `camera-shake`, `parallax-zoom`, `focus-rack`, `cursor-zoom-follow`, `camera-rig-depth-stack` |
| 3D | 28 | 2 | `orbit-card`, `cuboid-carousel`, `code-3d-extrude`, `glass-shard-title`; `three-orbiting-cards` |
| WebGPU shaders | 40 | 0 | `plasma`, `aurora`, `mesh-gradient`, `godrays`, `fractal-noise` |
| HTML-in-canvas | 11 | 1 | all experimental: the liquid-glass and `vfx-*` set |
| Kinetic type | 14 | 46 | `kinetic-center-build`, `per-word-rise`, `per-word-crossfade`, `headline-slam`, `variable-axis-type`, `marker-highlight` |
| Data | 13 | 8 | `data-chart`, `bar-chart-race`, `flowchart`, `world-map`; `count-up`, `animated-bar-chart`, `chart-story` |
| UI, code, cursor | 26 | 24 | `code-diff`, `code-typing`, `terminal-simulator`, `agent-cursor`, `cursor-drag-drop`, `chat-thread` |
| Lottie | 1 | 0 | `lottie-character-walk` |

These map straight onto the map's "not yet specified" vocabulary: kinetic
type, count-ups and charts, a flowchart, a timeline, a browser and cursor mock,
and a 3D orbit all exist as items (inferred).

### Shader transitions (14)

`@hyperframes/shader-transitions` 0.8.169: `domain-warp`, `ridged-burn`,
`whip-pan`, `sdf-iris`, `ripple-waves`, `gravitational-lens`,
`cinematic-zoom`, `chromatic-split`, `glitch`, `swirl-vortex`,
`thermal-distortion`, `flash-through-white`, `cross-warp-morph`, `light-leak`
(measured, `packages/shader-transitions/src/shaders/registry.ts`, 14 keys,
same at v0.8.160).

- **Licence**: unclear in the package. Its README says "MIT", its
  `package.json` has no `license` field and npm reports none, and the
  repository is Apache-2.0 (measured, `npm view @hyperframes/shader-transitions license`
  empty, `jq .license`). Either licence is commercial-safe (inferred).
- **Seekable and deterministic**: in render, "rendering uses deterministic
  per-frame compositing" instead of preview's pre-capture (measured, README).
  The `whip-pan` registry block (a WebGL2 context, `preserveDrawingBuffer`)
  rendered twice on the hardware GPU: 120 frames, 0 differ (measured, below).
- **Status**: documented; the native capture path uses Chrome's experimental
  `drawElementImage` when present, `html2canvas` otherwise (measured, README).
- **Wiring**: `init({scenes, transitions:[{time, shader, duration}]})` on one
  page with every scene as an element (measured, README). Our composer mounts
  scenes as `data-composition-src` sub-compositions; whether `init` can
  capture those is untested (guess: it needs scene element IDs in the root
  DOM, which mounted sub-compositions provide).

### `data-vfx-chain`

- Five WebGL2 kernels: `fractal-noise`, `wave-warp`, `displacement-map`
  (first release, #4306, 2026-09-23) and `luma-matte`, `noise` (backdrop and
  two-source kernels, #4330) (measured, `ls packages/core/src/vfx`, `git log`).
  The guide still lists backdrop as "not yet" and names three kernels, so the
  guide lags the code (measured, `docs/guides/vfx-chain.mdx` capture table).
- **Deterministic**: "Same backend, same `(u_t, params)` produces
  byte-identical pixels"; kernels read no clock or randomness (measured,
  guide's Determinism section). Not rendered here.
- **Cost**: any node forces screenshot capture; `self` and `backdrop` nodes pin
  the whole render to **one worker** (measured, guide's Capture table). On a
  2-minute budget that is the price to weigh (inferred).
- **Status**: documented, but `self` and `backdrop` depend on the experimental
  `drawElementImage` API (measured, guide). Only one registry item uses it
  (`filmed-screen`, experimental) (measured, `grep -rl vfx-chain registry`).
- Licence: Apache-2.0, it is core runtime (inferred).

### Frame adapters

The runtime ships 12 adapters (measured, `ls packages/core/src/runtime/adapters`,
same set at v0.8.160). The `FrameAdapter` interface itself is "experimental
v0 API" (measured, `docs/concepts/frame-adapters.mdx`); authoring through the
built-in adapters is the documented path.

| Adapter | Seek model | Deterministic rule | Documented | Library licence |
| --- | --- | --- | --- | --- |
| `gsap` | timeline seek | default path | Yes | GSAP Standard License (from #657) |
| `css` | seeks CSS animation handles, else negative delay | finite iterations, or `data-duration` | Yes | n/a |
| `waapi` | `currentTime` | `fill: both`, no rAF clocks | Yes | n/a |
| `animejs` | `instance.seek(ms)` on `window.__hfAnime` | `autoplay: false`, `createSeededRandom`; v4 auto-discovery broken, register by hand | Yes | MIT (measured, `npm view animejs license`) |
| `lottie` | `goToAndStop` on `window.__hfLottie` | no per-animation offset, all play on composition time | Yes | MIT (measured, `npm view lottie-web license`) |
| `three` | sets `__hfThreeTime`, `hf-seek` event | render from that time; root needs `data-duration`; preload assets | Yes | MIT (from #653) |
| `typegpu` | `__hfTypegpuTime`, `hf-seek` with `waitUntil` | await `onSubmittedWorkDone`; `data-requires-webgpu` | Yes | MIT (measured, `npm view typegpu license`) |
| `d3`, `leaflet`, `mapbox`, `maplibre`, `google-maps` | readiness only: wait for transitions or tiles | none stated | **No**: no hit in `docs/` or skills (measured, `grep -rlE 'maplibre\|leaflet\|mapbox\|google-maps'`) | varies |

Seek and determinism rules measured from `skills/hyperframes-animation/adapters/*.md`.

### Camera

- No camera primitive in the runtime: 2D camera is a GSAP-keyed wrapper
  transform (`hyperframes-keyframes`, `camera-journey` blueprint), 3D camera
  is Three.js (measured, `skills/hyperframes-keyframes/SKILL.md`).
- 10 camera blocks and 20 camera components (table above). `rack-focus` and
  `filmed-screen` are experimental; the rest are documented (measured).

## Determinism on this machine

Each registry block copied to its own folder, rendered twice with 0.8.169
(`render --quiet --fps 30 --workers 3 --quality looks`), frames compared with
`ffmpeg -f framemd5` (all measured):

| Block | Exercises | GPU path | Frames | Differ | Unique frames |
| --- | --- | --- | --- | --- | --- |
| `whip-pan` | WebGL2 shader transition | hardware, ANGLE on the RTX 2070 | 120 | 0 | 69 |
| `orbit-card` | Three.js r185 (vendored) | hardware | 300 | 0 | 247 |
| `lottie-character-walk` | lottie-web 5.12.2 | hardware | 225 | 0 | 220 |
| `plasma` | WebGPU (`data-requires-webgpu`) | hardware | refused: "no hardware WebGPU adapter could be obtained" | | |
| `plasma` | WebGPU on SwiftShader (`--no-browser-gpu`, `PRODUCER_ALLOW_SOFTWARE_WEBGPU=true`) | software | 60 | 0 | 60; wall 386 s and 241 s |

- The equal-pixels determinism gate holds for hardware-GPU WebGL and Three.js
  frames here, run to run (measured, two runs each). That answers part of the
  map's open "Video gates for motion and 3D" question for these paths.
- WebGPU: the bundled `chrome-headless-shell` gets no hardware WebGPU adapter
  on this Linux box with HyperFrames' default flags (measured). Software
  WebGPU is deterministic but about 2 minutes per second of video (measured),
  so the 40 WebGPU blocks are out of the 10-minute budget unless a hardware
  route is found (inferred).

## Library versions beside the pin

`gsap` 3.15.0 (skill pins 3.14.2, registry blocks load 3.14.2), `lottie-web`
5.13.0, `three` 0.186.1, `animejs` 4.5.0, `typegpu` 0.12.8 (measured,
`npm view <pkg> version`).

## Recommendation

- **The HyperFrames bump is its own first slice, and a small one**: change the
  pin and lock, the `backend.mjs` comment, refresh the derived copy; proof is
  the frame-hash comparison above re-run on a full video. No `scripts/render/`
  change (measured basis above).
- **Vendor references, not live skills**: `hyperframes-animation` (blueprints,
  rules, transitions) and `hyperframes-keyframes` give the camera, kinetic type
  and transition grammar the visual vocabulary ticket needs (inferred).
- **Pull registry items in through the lock, per item**: rewrite CDN scripts
  to local files, check Arabic, skip the six unconfirmed-origin assets and the
  18 experimental items (inferred).
- **Allowed now**: GSAP transitions, the 14 shader transitions (one page, see
  the wiring caveat), Three.js and Lottie, all measured deterministic on this
  GPU. **Not yet**: WebGPU blocks (no hardware adapter here) and capturing
  `data-vfx-chain` nodes (one worker, experimental API).

## Thin

- Hardware WebGPU was tried only with HyperFrames' default Chrome flags; a
  Vulkan feature flag or a different Chrome (`HYPERFRAMES_BROWSER_PATH`) might
  expose the RTX 2070 adapter. Not tried.
- `data-vfx-chain` and `@hyperframes/shader-transitions` inside our
  sub-composition layout were not rendered; the 14-shader determinism claim
  rests on one registry block.
- The 0.8.160 vs 0.8.169 equality is on the first 30 s and the 39 stills of
  one LTR video, not a full render or an Arabic run.
- Two determinism runs per block prove repeatability on one machine and one
  driver, not across drivers.
