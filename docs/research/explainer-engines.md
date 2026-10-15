# Video engines for explainer-video

Research for [#653](https://github.com/Gharib89/skills/issues/653) on the map
[#651](https://github.com/Gharib89/skills/issues/651). Date: 2026-10-15.

**Answer:** build on **HyperFrames** (Apache-2.0, HTML plus seekable
animation, deterministic Chrome capture, its own Three.js adapter). It is the
only candidate that passes the commercial-safe default rule, renders headless on
this machine, shapes Arabic through Chromium, and is written for agents.
Remotion is the stronger 3D and React ecosystem but its licence makes it an
opt-in, never the default. Manim, Motion Canvas and Revideo each fail one hard
criterion (mixed Arabic and English, headless render, or maintenance). A
standalone Three.js capture rig would rebuild what HyperFrames' adapter already
does.

Labels: **measured** (a command or lab render), **documented** (the owner's
docs, licence or source), **inferred** (my reasoning from those).

## Comparison

| Engine | Licence for a public skill | Headless deterministic render | Arabic and RTL | 3D and shaders | Agent fit |
| --- | --- | --- | --- | --- | --- |
| HyperFrames 0.8.x | Apache-2.0: safe | Yes, `beginframe` capture, GPU or SwiftShader | Chromium shaping; `<html dir="rtl">` blanks render, scope `dir` per element | Three.js and TypeGPU adapters, WebGL2 VFX chain | Built for agents, 21 skills, lint |
| Remotion 4.0.x | Source-available; companies of 4+ people pay | Yes, Chromium; 3D needs a `--gl` choice | Chromium shaping; fonts must be loaded | `@remotion/three` (React Three Fiber) | Strong: official skills, large corpus |
| Manim CE 0.22 | MIT: safe | Yes, Cairo on CPU | Pango shaping, but mixed RTL and LTR documented as broken | 3D scenes, OpenGL renderer optional | Good for maths diagrams |
| Motion Canvas 3.17 | MIT: safe | No official headless render | Canvas text, `textDirection` | 2D canvas only | Dormant since early 2025 |
| Revideo 0.11 | MIT: safe | Yes, `renderVideo()` | Inherits Motion Canvas text | 2D canvas | Small, bursty, telemetry on by default |
| Three.js standalone | MIT: safe | Only with a hand-built capture rig | `TextGeometry` cannot join Arabic; troika-three-text can | Full | Rig is ours to maintain |

## Licence

- **Remotion** (documented, [LICENSE.md on main](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md),
  same text in the lab's installed `remotion@4.0.507`): free for "an
  individual", "a for-profit organization with up to 3 employees", non-profits,
  and evaluation "not yet using it in a commercial way"; free users may use it
  "non-commercially or commercially". Everyone else "is required to obtain a
  Company License". npm declares it `SEE LICENSE IN LICENSE.md`; GitHub reports
  `NOASSERTION` (measured, `gh api repos/remotion-dev/remotion`). The FAQ says
  it is "source-available software, but it is not open source"
  ([licence FAQ](https://www.remotion.dev/docs/license/faq)).
- **Remotion 5.0 terms** (documented, open
  [PR #3750](https://github.com/remotion-dev/remotion/pull/3750), not yet
  released; latest release is v4.0.535 of 2026-10-12, measured via `gh api`):
  eligibility becomes "an organization or team of individuals with up to 3
  people", contractors count toward the size, Company Licenses are bound to new
  Terms and Conditions, and operating a service where end users upload their own
  Remotion code is disallowed even for free users. The FAQ already applies the
  contractor rule: outside freelancers' "headcount aggregates with yours for the
  4-person threshold".
- **Remotion price** (documented, [remotion.pro/license](https://www.remotion.pro/license)):
  "Remotion for Creators", "$25/mo per seat", one seat per user, "intended for
  low volume video creations through coding and prompting"; the FAQ prices it
  per "person who writes Remotion code themselves or using agentic coding
  tools". "Remotion for Automators" is "$0.01 per render, $100/mo minimum" for
  apps such as "prompt-to-video apps". Enterprise starts at $500 per month.
- **What it means for this skill** (inferred): the skill never ships Remotion
  code, so publishing an MIT skill that writes Remotion projects is allowed (the
  FAQ allows "a service that generates Remotion code using artificial
  intelligence"). The licence lands on each user who runs it: an individual or a
  team of 3 or fewer is free, an employee of a 4+ person company (contractors
  counted) needs a $25 per month Creators seat, since the skill's user is a
  person writing Remotion code through an agentic tool. The skill cannot know
  which case applies, so a Remotion default is not commercial-safe under the
  map's rule. Remotion can be an opt-in backend with a licence notice at
  selection.
- **HyperFrames**: Apache-2.0 (documented,
  [LICENSE](https://github.com/heygen-com/hyperframes/blob/main/LICENSE), npm
  `"license": "Apache-2.0"` in the lab's `hyperframes@0.8.158`). CLI telemetry
  is on and can be turned off with `npx hyperframes telemetry disable`
  (documented, `docs/guides/feedback.mdx`).
- **Manim CE, ManimPango, manim-voiceover, Motion Canvas, Revideo, Three.js,
  troika**: MIT (measured, `gh api repos/<repo> --jq .license.spdx_id`).
  Revideo "anonymously counts how many videos are rendered, via PostHog",
  disabled with `DISABLE_TELEMETRY=true` (documented,
  [README](https://github.com/midrender/revideo)).

## Render on 8 GB GPU and 30 GB RAM

Lab renders on the owner's machine, all 1920x1080, concurrency 3 (measured,
`~/wip/projects/video-lab/*/out/`, durations by `ffprobe`). Content differs per
project, so these are not an A/B benchmark.

| Project (engine) | Output | Render | Throughput |
| --- | --- | --- | --- |
| motioncraft (Remotion, `--gl=vulkan`) | 57 s at 30 fps, 1710 frames | 56.7 s | about 30 fps; 3D pre-rendered on software GL because vulkan and angle dropped live 3D frames |
| anything2explainer (Remotion) | 61 s at 30 fps, 1831 frames | 63 s | about 29 fps |
| hyperframes (HyperFrames) | 60 s at 30 fps, 1800 frames | 94.3 s wall (92.5 s internal) | about 19 fps, "beginframe capture, hardware gpu", 3 workers, logged maxrss 827 MB |
| manim (Manim CE) | 62.5 s at 60 fps | not logged | n/a |

- **HyperFrames** (documented,
  [determinism](https://hyperframes.heygen.com/concepts/determinism)): time is
  `floor(frame) / fps`, every animation is seeked never played, Chrome's
  `HeadlessExperimental.beginFrame` captures each frame, FFmpeg encodes and
  mixes `<audio>`. `--browser-gpu` uses the host GPU for Chrome and WebGL, or
  "deterministic SwiftShader"; auto-detect locally, off in Docker; `--gpu`
  adds NVENC encoding (documented, `docs/packages/cli.mdx`).
- **Remotion 3D** (documented, [docs/three](https://www.remotion.dev/docs/three)):
  "Three.JS does not render with the default OpenGL renderer", the docs
  recommend `angle`. The lab found angle and vulkan dropped live 3D frames
  (measured, motioncraft), so a Remotion 3D path needs the software fallback or
  pre-rendering.
- **Manim** (documented, [manim source](https://github.com/ManimCommunity/manim)):
  default renderer is Cairo on the CPU, so it does not compete for the one GPU
  slot (inferred).
- **VRAM** (inferred): all browser engines at concurrency 3 sit far under 8 GB;
  the binding limit is the map's one-GPU-job rule, so render must not overlap
  TTS.

## Arabic and right-to-left

The skill needs Egyptian Arabic lines with English technical terms inline, so
the test is mixed bidi text with contextual joining.

- **HyperFrames** (documented,
  [lint rules](https://hyperframes.heygen.com/reference/lint-rules)):
  "`<html dir="rtl">` or `<html dir="auto">` renders correctly in preview and
  snapshot but produces a fully blank or black video from render", fix: keep
  `lang`, drop `dir` from `<html>`, set `direction: rtl` or `dir="auto"` on text
  elements. The lint rule `html_dir_attribute_breaks_render` still exists on
  `main` as of 2026-10-14 (measured, vendored clone). The tracking issue
  [#1934](https://github.com/heygen-com/hyperframes/issues/1934) closed
  "completed" on 2026-07-06; the catalog RTL PR
  [#1541](https://github.com/heygen-com/hyperframes/pull/1541) closed unmerged
  (measured, `gh api`). Shaping itself is Chromium's (inferred).
- **Remotion**: Chromium layout, so shaping and bidi match the browser
  (inferred). Non-Latin fonts must be loaded explicitly or render as boxes
  ([#4628](https://github.com/remotion-dev/remotion/issues/4628), Korean Noto,
  documented). No open Arabic or RTL bug found (measured, issue search).
- **Manim**: `Text` uses Pango, which shapes `مرحبا بالعالم`, but the docs'
  own example warns "don't mix RTL and LTR languages nothing shows up then"
  (documented,
  [text_mobject.py](https://github.com/ManimCommunity/manim/blob/main/manim/mobject/text/text_mobject.py)).
  Open [#4061](https://github.com/ManimCommunity/manim/issues/4061): RTL text
  with `t2g` crashes, gradient fails silently.
  [#3932](https://github.com/ManimCommunity/manim/issues/3932): Arabic words of
  1 or 2 letters do not display, closed "not planned". This rules Manim out for
  Arabic narration on screen (inferred).
- **Motion Canvas and Revideo**: text draws through canvas 2D, so the browser
  shapes it (inferred); `textDirection` for RTL landed in Motion Canvas
  [#404](https://github.com/motion-canvas/motion-canvas/pull/404) (merged
  2023-02-26, measured). Revideo descends from Motion Canvas (documented, its
  [LICENSE](https://github.com/midrender/revideo/blob/main/LICENSE) reads
  "Copyright (c) 2022 motion-canvas").
- **Three.js**: `FontLoader.generateShapes` takes `Array.from(text)` and draws
  one glyph per code point; `direction: 'rtl'` only reverses the array
  (documented,
  [FontLoader.js](https://github.com/mrdoob/three.js/blob/dev/examples/jsm/loaders/FontLoader.js)).
  So `TextGeometry` cannot join Arabic letters (inferred). troika-three-text
  "handles proper kerning, ligature glyph substitution, right-to-left/bidirectional
  layout, joined scripts like Arabic" (documented,
  [README](https://github.com/protectwise/troika/tree/main/packages/troika-three-text)).
  Its layout runs in a web worker, so a renderer must wait for it before
  capture (inferred).

## 3D, shaders, diagrams and effects

- **HyperFrames** (documented, `skills/hyperframes-animation/adapters/three.md`):
  the `three` adapter sets `window.__hfThreeTime` and dispatches an `hf-seek`
  event per frame; the scene renders that exact time. Needs `data-duration` on
  the root, enforced by lint. The runtime seeks "GSAP, CSS, Anime.js, Lottie,
  Three.js, Web Animations, and TypeGPU" (documented,
  [frame adapters](https://hyperframes.heygen.com/concepts/frame-adapters)),
  and `data-vfx-chain` adds deterministic WebGL2 warps and noise (documented,
  `docs/guides/vfx-chain.mdx`). A registry of blocks and components (charts,
  captions, transitions) ships with it (documented,
  [catalog](https://hyperframes.heygen.com/catalog/blocks/data-chart)).
- **Three.js standalone with frame capture** (inferred): needs a fixed clock,
  a seek hook, Chrome capture and FFmpeg mux; that is the HyperFrames `three`
  adapter. Building our own adds a renderer to maintain with no capability
  gained.
- **Remotion** (documented, [docs/three](https://www.remotion.dev/docs/three)):
  `<ThreeCanvas>` lets `useCurrentFrame()` drive React Three Fiber; animations
  are rendered into the markup rather than in `useFrame()`. Ecosystem:
  `@remotion/google-fonts`, `@remotion/layout-utils`, `@remotion/media`, all in
  the lab's manifests (measured).
- **Manim**: strongest for maths and graph diagrams (inferred from its scope);
  weak for UI-style explainers.
- **Motion Canvas and Revideo**: 2D only; Revideo's README demo projects 3D by
  hand inside a custom `draw()` (documented).

## Audio sync

- **HyperFrames**: FFmpeg mixes `<audio>` and `<video>` sound at encode
  (documented, determinism page); `npx hyperframes transcribe` gives word
  timings via Parakeet or Whisper with `--language` (documented,
  `docs/guides/voice-and-audio.mdx`). The lab render logged automatic loudness
  limiting: "Audio lowered by 1.1 dB to stay under -1 dBTP" (measured,
  `hyperframes/out/render.log`).
- **Remotion**: audio placed by frame in the composition (documented,
  `@remotion/media`); the anything2explainer render had synced narration
  (measured, lab output).
- **Manim**: `manim-voiceover` (MIT) syncs animations to TTS with bookmarks
  (documented, [repo](https://github.com/ManimCommunity/manim-voiceover)); used
  in the lab's `pyproject.toml` (measured).
- **Revideo**: `<Audio/>` with "frame-accurate synchronization" (documented,
  README).

## Agent-friendliness and maintenance

- **HyperFrames**: "Write HTML. Render video. Built for agents." Ships 21
  skills, a Claude Code plugin, and `npx hyperframes lint` that catches traps
  such as the RTL one (documented,
  [README](https://github.com/heygen-com/hyperframes)). Pushed 2026-10-15,
  63.9k stars (measured, `gh api`). Frame-adapter API is "experimental v0",
  so the skill should use the documented authoring path, not the interface
  (documented).
- **Remotion**: official agent skills at
  [remotion-dev/skills](https://github.com/remotion-dev/skills) (pushed
  2026-10-12, measured) and the largest training corpus of the set (inferred).
  Two of the lab's strongest renders were Remotion (measured, lab).
- **Motion Canvas**: last release v3.17.2 on 2024-12-14, last code commit
  2025-02-16, headless rendering still open requests
  ([#415](https://github.com/motion-canvas/motion-canvas/issues/415),
  [#1055](https://github.com/motion-canvas/motion-canvas/issues/1055),
  [#1218](https://github.com/motion-canvas/motion-canvas/issues/1218))
  (measured, `gh api`). Unfit for an unattended pipeline (inferred).
- **Revideo**: moved to `midrender/revideo`; commits cluster in 2025-01 to
  2025-05 and 2026-07, release 0.11.0 on 2026-07-10, 4.1k stars (measured,
  `gh api`). Thin bus factor for a default (inferred).

## Recommendation

1. **Default engine: HyperFrames.** Apache-2.0 meets the commercial-safe rule;
   deterministic headless capture ran in the lab at 1800 frames in 94 s on the
   hardware GPU at 3 workers; Chromium shapes Arabic and bidi; its Three.js
   adapter covers the 3D case; it ships agent skills and a linter. Bake in two
   rules from day one: never set `dir` on `<html>` (scope it to text elements),
   and bundle Arabic fonts locally.
2. **Three.js**: use it inside HyperFrames via the `three` adapter, not a
   standalone rig. Arabic text in a 3D scene goes through troika-three-text or
   an HTML overlay layer, never `TextGeometry`.
3. **Remotion: opt-in backend only**, chosen explicitly, with a notice quoting
   the licence: free for individuals and teams of 3 or fewer (contractors
   counted), otherwise a $25 per month per person Creators seat. Worth keeping
   because it rendered fastest in the lab and has `@remotion/three`; plan the
   3D path on software GL or pre-rendering.
4. **Manim**: optional scene type for English-only maths diagrams, rendered
   to a clip and placed in the HyperFrames timeline. Not for Arabic text.
5. **Drop Motion Canvas** (no headless render, dormant) and **hold Revideo**
   as a fallback only (small, bursty maintenance, telemetry on by default).

## Thin

- The HyperFrames RTL root fix: #1934 closed "completed" but the lint rule and
  its "confirmed, silent failure" wording remain on `main`; I did not render an
  RTL page to check (rendering was out of scope).
- No candidate was tested here with a mixed Egyptian Arabic and English line;
  the Chromium shaping claims are inferred, not rendered.
- Lab throughput is not like for like: content and 3D load differ per project,
  and the manim render time was not logged.
- Peak VRAM per engine was not measured.
- Remotion 5.0 release date is unknown; its terms are from an open PR.
- Blender and other non-browser engines were not surveyed.
