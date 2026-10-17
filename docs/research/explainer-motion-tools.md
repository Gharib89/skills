# Skills and tools that make motion videos

Research for [#775](https://github.com/Gharib89/skills/issues/775) on the
[rich-visuals map](https://github.com/Gharib89/skills/issues/770). Builds on
[#657](https://github.com/Gharib89/skills/issues/657)
(`research/explainer-effects`, `docs/research/explainer-effects.md`), which
already settled the licences of GSAP, lottie-web, gl-transitions, LYGIA and
Shadertoy; this file refreshes what moved and adds skills and asset sources.

Labels: **measured** (a command was run, named inline), **documented** (a
primary source says so, linked or pathed), **inferred** (my reading, no direct
proof), **guess**. Dates and versions are as of 2026-10-17.

## Answer

1. **HyperFrames' own skills are the only agent skills written against our
   engine's seek contract**, and they are Apache-2.0. `hyperframes-core`
   (determinism rules with lint IDs), `hyperframes-animation` (adapters for
   GSAP, Lottie, Three.js, anime.js, CSS, WAAPI, TypeGPU) and
   `hyperframes-keyframes` (seek-safe camera moves, SVG draw and morph) are
   worth taking in through the lock at a pinned ref, as maintainer-side
   skills that the ship runs building new scene components load. They should
   not be composed into `explainer-video`'s user runs: the skill writes
   compositions from a scene file in `scripts/render/compose.mjs`, so a run's
   agent never hand-writes HyperFrames HTML (measured: `grep -n
   gsap.timeline skills/explainer-video/scripts/render/compose.mjs`), and the
   `hyperframes` router skill would compete for "make a video" triggers
   (inferred).
2. **No new animation runtime is needed for the first spec.** GSAP (already a
   dependency at 3.14.2, npm has 3.15.0), lottie-web and dotlottie-web, and
   Three.js all have HyperFrames adapters that seek them per frame (measured:
   `gh api repos/heygen-com/hyperframes/contents/packages/core/src/runtime/adapters`).
   Rive is the only runtime worth a later look (MIT runtimes, no HyperFrames
   adapter, state machines only step forward). Theatre.js, Motion Canvas and
   Motion (motion.dev) are skips.
3. **One determinism trap is new**: GSAP's ScrambleText plugin calls unseeded
   `Math.random` 4 times (measured: `npm pack gsap@3.15.0`, then `tar -xzOf gsap-3.15.0.tgz
   package/ScrambleTextPlugin.js | grep -o Math.random | wc -l`), so it breaks
   the determinism gate unless `Math.random` is swapped for a seeded PRNG
   while its timeline is built.
4. **Third-party skills give text to borrow, not code to vendor.** The useful
   ones are MIT (calesthio's GSAP composition and kinetic-type skills,
   iart-ai's kinetic-typography, LottieFiles' motion-design, greensock's
   gsap-skills); the popular Three.js skill (CloudAI-X) has no licence and
   animates from wall-clock time; Pixel Point's `animate-text` catalog, which
   HyperFrames itself defers to, has no licence file either. The installed
   `remotion-best-practices` has no licence of its own, so its rules are
   borrowed as ideas, not text.
5. **Asset sources**: Poly Haven and ambientCG (CC0, keyless APIs) cover 3D
   models, HDRIs and textures; Lucide, Tabler, Heroicons and Material Symbols
   (npm, permissive) cover icons; Fontsource covers fonts, with eleven OFL
   Arabic families, seven of them variable. Lottie files are the weak
   category: LottieFiles' licence is share-alike, lordicon's free tier forbids
   derivatives.

## Agent skills

Searched with `npx -y skills find <q>` for gsap, three.js, threejs, lottie,
motion, animation, motion design, video, hyperframes, remotion, kinetic
typography, svg animation, rive, theatre, shader and webgl (measured; raw
output kept outside the repo). Licences from `gh api repos/<o>/<r>` and the
repo tree (`gh api repos/<o>/<r>/git/trees/HEAD?recursive=1`); a repo with no
LICENSE file is all rights reserved.

### HyperFrames' own skills

`heygen-com/hyperframes` is Apache-2.0, latest release v0.8.169 published
2026-10-17T17:22 (measured: `gh api repos/heygen-com/hyperframes/releases/latest`,
`gh api .../contents/LICENSE`). It releases about daily (inferred from the
0.8.160 to 0.8.169 gap since 2026-10-15), so any lock entry pins a ref.

Skills under `skills/` (measured: `gh api repos/heygen-com/hyperframes/contents/skills`):
hyperframes (router), hyperframes-cli, hyperframes-core,
hyperframes-animation, hyperframes-keyframes, hyperframes-creative,
hyperframes-registry, hyperframes-audio, hyperframes-studio, media-use,
faceless-explainer, general-video, motion-graphics, product-launch-video,
pr-to-video, music-to-video, embedded-captions, talking-head-recut,
slideshow, figma, remotion-to-hyperframes. Install counts on skills.sh run
from about 290K (figma) to 1.1M (hyperframes-cli) (measured: `npx skills
find hyperframes`). The index still lists old `@gsap`, `@lottie`, `@three`
and `@typegpu` skills whose folders are now
`skills/hyperframes-animation/adapters/*.md` (measured: tree listing), so an
install by those old names would miss (inferred).

What each relevant one holds:

- **hyperframes-core**, `references/determinism-rules.md`: paused GSAP
  timeline on `window.__timelines[<composition-id>]`, register it only after an
  async build ends (lint `gsap_timeline_registered_before_async_build`), no
  `Date.now()` or `performance.now()`, seeded PRNG only, no render-time
  fetches, `repeat: -1` only under a finite root `data-duration`, never tween a
  clip element's visibility (lint `gsap_animates_clip_element`), and
  `window.__hyperframes.pretext` for reflow-free text measuring (measured:
  `gh api .../skills/hyperframes-core/references/determinism-rules.md`). Our
  determinism gate could name these lint IDs (inferred).
- **hyperframes-animation**, `adapters/`: animate-text, animejs,
  css-animations, gsap (four files), html-in-canvas-patterns, lottie, three,
  typegpu, waapi (measured: contents listing). The three adapter renders on
  the `hf-seek` event from `window.__hfThreeTime` and bans
  `requestAnimationFrame` and `setAnimationLoop`; it also warns that a clean
  lint or software-renderer frame does not certify GPU arithmetic, so frames
  must be checked on the real GPU (documented: `adapters/three.md` line 158).
  That last point bears directly on the map's open question about GPU frames
  and the equal-pixels gate.
- **hyperframes-keyframes**: punch-ins, Ken Burns, camera moves, SVG draw and
  morph, FLIP, described as seek-safe (measured: skill description).
- **animate-text adapter**: defers to Pixel Point's `animate-text` skill for
  24 named text effects (per-character, per-word, per-line, whole element)
  and refuses to vendor it because upstream has no licence (documented:
  `adapters/animate-text.md`). `pixel-point/animate-text` still has no LICENSE
  file, last push 2026-04-24 (measured: `gh api repos/pixel-point/animate-text`
  and its tree). The effect names are a usable vocabulary for a scene file;
  only the 8 per-word and 2 per-line effects suit Arabic, since letters must
  not move apart (inferred from the map's Arabic rule).
- **faceless-explainer, motion-graphics, general-video,
  product-launch-video**: whole-video authoring flows that overlap
  `explainer-video` (measured: descriptions). Their beat and scene ideas can
  be borrowed; composing them would hand the run to a second pipeline
  (inferred).
- Six more house-style skills live under the repo's `.claude/skills/`
  (motion-doctrine, seam-craft, cut-the-curve, captions-overlay,
  changelog-video, oversized-cursor); seam-craft and cut-the-curve cover scene
  seams and transitions (measured: tree listing). Borrow.

### Third-party skills

| Skill (source) | Licence | Last push | Installs | Seek-aware? | What it would add |
|---|---|---|---|---|---|
| gsap-animation-composition (calesthio/generative-media-skills) | MIT | 2026-07-14 | 93 | Yes: seekable playhead, seeded or precomputed randomness, idempotent callbacks, warns `ticker.fps` is not deterministic | The clearest third-party write-up of render-safe GSAP |
| title-kinetic-typography (same repo) | MIT | 2026-07-14 | 139 | Partial: frames and timecode, tool-agnostic | Title direction; "check the worst frame" QA |
| kinetic-typography (iart-ai/kinetic-typography-skills) | MIT | 2026-06-22 | 1.7K | Partial: `?t=N` freeze harness (`tl.pause(); tl.seek(t)`), split after `document.fonts.ready` | Reveal recipes |
| gsap-core, gsap-timeline, gsap-plugins, gsap-utils (greensock/gsap-skills) | MIT | 2026-07-29 | 60K to 69K | No: live web pages, ScrollTrigger, React | Plugin facts (SplitText, MorphSVG, CustomEase) |
| text-to-lottie (diffusionstudio/lottie) | MIT | 2026-07-25 | 10.3K | Partial: inspects `?frame=N` in a Skottie player | Authoring Lottie JSON from text, which the Lottie adapter can seek (inferred) |
| motion-design (LottieFiles/motion-design-skill) | MIT | 2026-05-18 | 17.6K | No: UI motion, Disney principles | Easing and timing tables |
| animation-vocabulary (emilkowalski/skills) | MIT | 2026-10-11 | 217K | No: glossary | Shared motion terms for the critic |
| threejs-* (CloudAI-X/threejs-skills) | None (no LICENSE) | 2026-07-09 | 18.3K | No: `THREE.Clock` and rAF loops | Nothing usable |
| svg-animations (supermemoryai/skills) | None | 2026-10-14 | 2.5K | No: SMIL and CSS in real time | Nothing |
| hyperframes-motion-director (geekjourneyx) | AGPL-3.0 | 2026-07-26 | 249 | Yes | Licence rules it out |
| OpenMontage (calesthio) | AGPL-3.0 | 2026-10-16 | 1.1K | not read | Licence rules it out |
| theatre-js (noklip-io/agent-skills) | MIT | 2026-01-31 | 97 | not read | 1 star, runtime is a skip anyway |

All rows measured with `npx skills find` (installs), `gh api repos/<r>`
(licence, push) and a grep of each SKILL.md for paused, seek, Clock,
requestAnimationFrame, seed and Math.random. No Rive skill turned up: the
`rive` query returned only unrelated hits, and two freshtechbro entries that
mention Rive date from 2025-11-20 (measured).

### The installed `remotion-best-practices`

Source `remotion-dev/skills`, `skills/remotion-best-practices`, installed
2026-10-01 (measured: `jq` over `~/.agents/.skill-lock.json`). The repo has no
licence (measured: `gh api repos/remotion-dev/skills --jq .license` is null, no
LICENSE in its root) and mirrors `packages/skills` of the Remotion monorepo,
whose licence is the Remotion License (measured: its `package.json`
`repository.url`; `gh api repos/remotion-dev/remotion --jq .license.spdx_id`
is NOASSERTION, the custom licence). So its prose is not ours to copy; its
rules transfer as ideas (inferred). The ones that apply to HyperFrames:

- **Every motion is a function of the frame.** CSS `transition` and
  `animation` and Tailwind animation classes do not render; shaders and models
  must not animate themselves, and `useFrame()` from R3F is forbidden
  (`remotion-markup/REFERENCE.md`, `3d.md`). HyperFrames states the same for
  its runtime (above), so this is confirmation, not news.
- **Annotation progress driven by the timeline**: highlight, circle,
  underline, strike-through, box and bracket marks with a `progress` value
  (`text-highlights.md`). We already depend on `roughjs` 4.6.6 (measured:
  `skills/explainer-video/package.json`), so a GSAP-driven rough-notation
  component is a short port (inferred).
- **Fit text before animating it**: `measureText`, `fitText`, `fillTextBox`
  (`measuring-text.md`); HyperFrames has `fitTextFontSize` and `pretext` for
  this.
- **Light leak as a transition overlay** with a seed and a `progress` that
  reveals then retracts (`light-leaks.md`); a seeded WebGL or CSS version is
  borrowable.
- **Moving maps are a fixed plate**: render the map once at the largest
  zoom, keep its camera still and pan with CSS transforms, because per-frame
  `jumpTo()` shimmers in headless capture
  (`remotion-maps/techniques/maplibre/references/render-stability.md`). This
  applies to HyperFrames' mapbox and maplibre adapters too (inferred).
- **Motion blur**: `HtmlInCanvasMotionBlur` averages sub-frame captures in a
  canvas, 8 samples by default (`motion-blur.md`); the effects research found
  it crashed in the lab, so treat it as an idea only.

## Animation runtimes with a seekable clock

HyperFrames adapters (measured: `gh api
repos/heygen-com/hyperframes/contents/packages/core/src/runtime/adapters`):
animejs, css, d3, google-maps, gsap, leaflet, lottie, mapbox, maplibre, three,
typegpu, waapi. No Rive, Theatre.js, Motion Canvas or Motion adapter.

| Runtime | Licence | Seek call | Deterministic headless | Maintenance |
|---|---|---|---|---|
| GSAP 3.15.0 and plugins (SplitText, MorphSVG, DrawSVG, MotionPath, CustomEase, Flip, ScrambleText) | Standard no-charge licence, commercial use allowed; bans only no-code visual animation builders that compete with Webflow; "AI-generated code is not a Prohibited Use" (documented: gsap.com/standard-license) | adapter calls `tl.totalTime(t, true)` | Yes; ScrambleText needs a seeded `Math.random`; SplitText after fonts load | npm modified 2026-04-13 (measured: `npm view gsap`) |
| lottie-web 5.13.0 | MIT | `goToAndStop(frame, true)`, whole frames | Yes for SVG; expressions with `wiggle` or `random` untested (guess) | npm 2025-05-21, push 2025-09-01 |
| @lottiefiles/dotlottie-web 0.81.0 | MIT | `setFrame(frame)` | With care: WASM canvas | release 2026-10-06 |
| three r186 | MIT | adapter sets `window.__hfThreeTime`, dispatches `hf-seek`, waits on `DefaultLoadingManager` | With care: WebGL frames depend on GPU or SwiftShader | release 2026-09-24 |
| @rive-app/canvas 2.44.2, rive-runtime | MIT (runtimes) | linear: `instance.time = t`, `apply`, `artboard.advance(0)`; state machine: `advanceAndApply(dt)` forward only | With care: own rAF loop must be off (`autoplay: false`); a backward seek replays from 0 in fixed steps | release 2026-10-10 |
| Theatre.js @theatre/core 0.7.2 | core Apache-2.0, studio AGPL-3.0-only | `sheet.sequence.position = t` | Yes | npm 2024-05-19, push 2024-08-14; README says work moved private |
| Motion Canvas 3.17.2 | MIT | `player.requestSeek(frame)` | No when embedded: own canvas app on rAF | release 2024-12-14 |
| anime.js 4.5.0 | MIT | `seek(ms)` | Yes | release 2026-06-22 |
| Motion (motion.dev) 14.3.0 | MIT | `controls.time = t` after `pause()` | With care: WAAPI half is hooked by the waapi adapter, the JS half runs a rAF driver nothing seeks | npm 2026-10-15 |
| @react-three/fiber 9.8.2, drei 10.7.9 | MIT | `frameloop="demand"`, `invalidate()` on `hf-seek` (inferred) | With care: `useFrame` is rAF-clocked | 2026-10-15, 2026-09-25 |

Sources: `npm view <pkg> license version time.modified`, `gh api
repos/<o>/<r>` and `.../releases/latest` (measured); seek calls from the
adapter sources `adapters/lottie.ts`, `adapters/three.ts` (measured), Rive's
`rive_advanced.mjs.d.ts` and the rive-docs low-level API page via ctx7
(documented), Theatre's `TheatreSequence.ts:81`, Motion Canvas's
`Player.ts:521` and Motion's `JSAnimation.ts` (measured: read in source). The
Theatre AGPL split is in its README (documented).

What each adds (inferred): GSAP carries kinetic type, counters, diagram
motion and, through MorphSVG and DrawSVG, line-drawn diagrams; Lottie plays
designer-made icons and mascots exactly as authored; Three.js gives depth,
light and a real camera; Rive would add rigged characters and UI
micro-animations from `.riv` files through a roughly 60-line custom adapter on
HyperFrames' experimental `FrameAdapter` interface (`getDurationFrames`,
`seekFrame`, documented: `docs/concepts/frame-adapters.mdx`). Whether the Rive
editor's plan terms limit exporting `.riv` files was not checked.

## Asset sources

No assets were downloaded; probes fetched metadata and licence text only.

| Source | Category | Licence | Scripted access | Verdict |
|---|---|---|---|---|
| Poly Haven | models, HDRIs, textures | CC0, no credit (documented: polyhaven.com/license) | keyless API, 2387 assets: 997 HDRIs, 869 textures, 521 models (measured: `curl -s 'https://api.polyhaven.com/assets?type=all' \| jq length`) | Fetch at build |
| ambientCG | textures, HDRIs | CC0 (documented: ambientcg.com/license) | keyless v3 API, 2908 assets (measured: `curl 'https://ambientcg.com/api/v3/assets?limit=1'`) | Fetch at build |
| Kenney, Quaternius | low-poly models | CC0 (documented: kenney.nl/support, quaternius.com/faq.html) | zip downloads, no API (inferred) | Vendor a subset |
| Sketchfab | models | per model | download returned 401 without OAuth (measured) | Skip |
| Khronos glTF-Sample-Assets | models | per model; `LICENSES/` includes CC-BY-NC, CC-BY-NC-SA and vendor EULAs (measured: `gh api`) | raw GitHub | Skip for video |
| three.js `examples/models` | models | repo MIT, models not (measured: grep of example HTML) | raw GitHub | Skip |
| Lucide (`lucide-static` 1.59.0) | icons | ISC (measured: LICENSE read; GitHub shows NOASSERTION because of an extra notice) | npm | Fetch at build |
| Tabler (`@tabler/icons` 3.49.0), Heroicons 2.2.0 | icons | MIT | npm | Fetch at build |
| Material Symbols (`@material-symbols/svg-400` 0.48.0) | icons | Apache-2.0, keep NOTICE | npm | Fetch at build |
| Phosphor (`@phosphor-icons/core` 2.1.1) | icons | MIT | npm, last release 2024-03 | Vendor a subset |
| Iconify (`@iconify/json` 2.2.544) | icons | per set: of 243 sets, 112 MIT, 31 Apache, 10 CC0, 4 ISC, 52 CC-BY-4.0, plus GPL, CC-BY-SA and 2 NC (measured: `collections.json`) | npm | Fetch behind an SPDX allowlist |
| Simple Icons 16.35.0 | brand logos | CC0 data; marks stay their owners' trademarks (documented: DISCLAIMER.md) | npm | Fetch only to name real products |
| LottieFiles free animations | Lottie | Lottie Simple License: commercial use and no credit, but any distribution "must contain (and be subject to) the same terms" and modifications are derivative works under the same terms (measured: `curl -sL https://lottiefiles.com/page/license`) | keyless GraphQL `graphql.lottiefiles.com/2022-08` worked but is undocumented (measured; stability inferred) | Vendor a curated, pinned subset with creator credits |
| useAnimations | Lottie | MIT, no credit (documented: FAQ; npm) | npm `react-useanimations` 3.1.1 | Vendor a subset |
| lordicon free | Lottie | CC BY-ND 4.0 modified: credit required, no derivatives (documented: lordicon.com/licenses) | needs an account | Skip |
| Fontsource | fonts | OFL-1.1 for every Arabic package checked (measured: `npm view`) | npm pins versions; `api.fontsource.org` keyless | Fetch at build |
| Google Fonts | fonts | OFL for the Arabic families checked (measured: METADATA.pb) | Developer API 403 without key, keyless `css2` 200 (measured) | Fallback to Fontsource |

The prior effects research called LottieFiles files "commercial use, no
attribution needed"; that holds, but it missed the share-alike clause. Whether
a rendered MP4 counts as a "display ... or distribution of Files" that must
carry the licence terms is unclear (inferred), so a curated subset with a
credits line naming the creator and the licence is the safe reading.

Arabic families, all OFL with an Arabic subset (measured: google/fonts
METADATA.pb, cross-checked with `api.fontsource.org/v1/variable/<id>`):

| Family | Axes or weights | Fontsource |
|---|---|---|
| Noto Sans Arabic | wght 100 to 900, wdth 62.5 to 100 | variable |
| Noto Naskh Arabic | wght 400 to 700 | variable |
| Noto Kufi Arabic | wght 100 to 900 | variable |
| Cairo | wght 200 to 1000, slnt -11 to 11 | variable |
| Readex Pro | wght 160 to 700, HEXP 0 to 100 | variable |
| Alexandria | wght 100 to 900 | variable |
| Rubik | wght 300 to 900 | variable |
| Vazirmatn | wght 100 to 900 | variable (upstream repo last pushed 2023-06) |
| IBM Plex Sans Arabic | static 100 to 700 | static only |
| Tajawal | static 200 to 900 | static |
| Almarai | static 300, 400, 700, 800 | static |

Variable families let Arabic kinetic type animate weight or width on whole
words, which keeps letters joined (inferred).

## Recommendation for the spec

- Add `hyperframes-core`, `hyperframes-animation` and `hyperframes-keyframes`
  to `skills-lock.json` at a pinned HyperFrames ref, as maintainer-side
  skills for the ship runs that build scene components, and re-pin them with
  the HyperFrames bump. Do not add the `hyperframes` router or the
  whole-video skills, and do not make `explainer-video` invoke any of them.
- Keep GSAP as the one motion runtime for 2D; bump it with HyperFrames; seed
  `Math.random` around ScrambleText or leave ScrambleText out.
- Use HyperFrames' Lottie and Three.js adapters as they are; 3D follows the
  three adapter's `hf-seek` contract whether it runs live or as a cached clip
  insert. Leave Rive for a later slice if characters are wanted.
- Borrow into `explainer-video`'s own prose and components: the determinism
  lint IDs for the gate, the fixed-plate rule for maps, a timeline-driven
  rough-notation component on `roughjs`, a seeded light-leak overlay, and the
  `animate-text` effect names (per-word and per-line only in Arabic).
- Assets: setup fetches fonts from Fontsource and icons from Lucide or Tabler
  by npm; 3D, HDRI and texture fetches go to Poly Haven and ambientCG by API;
  Lottie stays a small vendored, credited subset.

## Summary table

| Name | Kind | Licence | Deterministic in headless Chrome | Maintenance | Verdict | Why |
|---|---|---|---|---|---|---|
| hyperframes-core | skill | Apache-2.0 | Yes, it defines the contract | daily releases, v0.8.169 2026-10-17 | Vendor (lock, pinned, maintainer-side) | Engine's own determinism rules and lint IDs |
| hyperframes-animation | skill | Apache-2.0 | Yes | same | Vendor (lock, pinned, maintainer-side) | GSAP, Lottie, Three.js adapter rules in one place |
| hyperframes-keyframes | skill | Apache-2.0 | Yes (seek-safe) | same | Vendor (lock, pinned, maintainer-side) | Camera moves, SVG draw and morph |
| hyperframes (router), faceless-explainer, motion-graphics, general-video | skill | Apache-2.0 | Yes (inferred) | same | Borrow | Overlap explainer-video; the router would steal triggers |
| seam-craft, cut-the-curve | skill | Apache-2.0 | Yes (inferred) | same | Borrow | Scene seam and transition craft |
| remotion-best-practices | skill | none in repo; Remotion License upstream | Yes (frame-driven) | push 2026-10-16 | Borrow ideas | Fixed-plate maps, annotation progress, text fitting; text not ours to copy |
| animate-text (pixel-point) | skill | none | Yes (named specs) | push 2026-04-24 | Borrow names only | No licence; vocabulary for scene files |
| gsap-animation-composition, title-kinetic-typography (calesthio) | skill | MIT | Yes / partial | push 2026-07-14 | Borrow | Best render-safe GSAP and title guidance |
| kinetic-typography (iart-ai) | skill | MIT | Partial | push 2026-06-22 | Borrow | Reveal recipes, freeze harness |
| greensock/gsap-skills | skill | MIT | No (web pages) | push 2026-07-29 | Borrow | Plugin facts only |
| text-to-lottie (diffusionstudio) | skill | MIT | Partial | push 2026-07-25 | Borrow, later | Lottie authoring route |
| motion-design (LottieFiles), animation-vocabulary | skill | MIT | No | 2026-05-18, 2026-10-11 | Borrow | Easing tables, critic vocabulary |
| CloudAI-X threejs-skills, supermemoryai svg-animations | skill | none | No (wall clock) | 2026-07, 2026-10 | Skip | No licence, real-time loops |
| hyperframes-motion-director, OpenMontage | skill | AGPL-3.0 | Yes / not read | 2026-07, 2026-10 | Skip | Licence |
| GSAP 3.15.0 and plugins | runtime | GSAP standard no-charge | Yes; ScrambleText needs seeding | npm 2026-04-13 | Compose (already a dependency) | HyperFrames default runtime |
| lottie-web, dotlottie-web | runtime | MIT | Yes (SVG); with care (WASM) | 2025-09, 2026-10-06 | Compose via HF adapter | Designer-made icon and character motion |
| three r186 | runtime | MIT | With care (GPU frames) | 2026-09-24 | Compose via HF adapter | Depth, light, camera |
| Rive runtimes 2.44.2 | runtime | MIT | With care (forward-only state machines) | 2026-10-10 | Skip for now, borrow later | No HF adapter; rigged characters if wanted |
| Theatre.js 0.7.2 | runtime | Apache-2.0 core, AGPL studio | Yes | push 2024-08-14 | Skip | Stale, development moved private |
| Motion Canvas 3.17.2 | runtime | MIT | No when embedded | release 2024-12-14 | Skip | Competing pipeline on rAF |
| anime.js 4.5.0 | runtime | MIT | Yes | 2026-06-22 | Skip | GSAP covers it |
| Motion 14.3.0 | runtime | MIT | With care (rAF half unseeked) | 2026-10-15 | Skip | GSAP covers it |
| R3F 9.8.2, drei 10.7.9 | runtime | MIT | With care (`useFrame`) | 2026-10 | Skip | Scenes are not React |
| Poly Haven | assets | CC0 | n/a | live API | Fetch at build | Models, HDRIs, textures, keyless |
| ambientCG | assets | CC0 | n/a | live API | Fetch at build | Textures, HDRIs, keyless |
| Kenney, Quaternius | assets | CC0 | n/a | active | Vendor a subset | Low-poly models, no API |
| Lucide, Tabler, Heroicons, Material Symbols | assets | ISC, MIT, MIT, Apache-2.0 | n/a | active | Fetch at build | Permissive icons by npm |
| Iconify | assets | per set | n/a | daily | Fetch behind SPDX allowlist | Breadth, mixed licences |
| Simple Icons | assets | CC0 plus trademarks | n/a | active | Fetch, naming products only | Brand marks |
| LottieFiles free | assets | Lottie Simple License, share-alike | n/a | active | Vendor curated subset, credited | Undocumented API, share-alike clause |
| useAnimations | assets | MIT | n/a | 2026-10 | Vendor a subset | Clean small UI set |
| lordicon free | assets | CC BY-ND modified | n/a | n/a | Skip | No derivatives |
| Sketchfab, glTF-Sample-Assets, three.js example models | assets | per model, mixed | n/a | active | Skip | Token or per-file licence checks |
| Fontsource (Arabic OFL families) | assets | OFL-1.1 | n/a | 2026-07 | Fetch at build | Pinned npm, seven variable Arabic families |

## Thin

- Install counts come from `npx skills find` and drift daily.
- The HyperFrames registry's block and component counts were not re-measured
  here; the HyperFrames-now ticket owns that.
- Lottie expressions, Rive state-machine stepping and dotlottie-web WASM were
  read in source and docs, not rendered twice and diffed.
- Rive editor export terms, and whether an MP4 is a "distribution of Files"
  under the Lottie Simple License, are open.
- Kenney and Quaternius access was inferred from their sites, not probed.
