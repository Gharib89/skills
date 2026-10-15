# Diagramming in video

Research for [#658](https://github.com/Gharib89/skills/issues/658) on the `explainer-video` map ([#651](https://github.com/Gharib89/skills/issues/651)). Researched 2026-10-15.

## Answer

Keep the house pipeline's shape: the agent writes only a YAML `### Visual` spec per scene, and a registry of Remotion components draws it, revealing each item at the narration sentence that names it. Every other option fails at least one criterion out of the box. Mermaid and D2 render text the wrong way round in mixed Arabic and English labels until CSS is injected, and their built-in animation is CSS keyframes that Remotion cannot seek. Manim drops Arabic words in mixed lines, and each scene is bespoke Python. Excalidraw's font has no Arabic. Add three things to the registry: an `rtl` path, an optional sketch look drawn with rough.js at a fixed seed, and syntax highlighting in the `code` component from Shiki tokens, with animated code diffs from Code Hike's token transitions as Remotion's own template uses them.

Labels: **measured** (a command or render run on this machine, named), **documented** (the cited source says so), **inferred** (reasoned from the evidence, not run).

## Criteria

From the ticket: animatable step by step, styleable from a style profile, right-to-left labels, legible at 1080p, and how reliably an agent produces it. The map adds: commercial-safe defaults, local on an 8 GB GPU and 30 GB RAM machine, English and Egyptian Arabic with English technical terms kept in English.

## Baseline: the house component registry

- **Shape.** `src/Visual.tsx` maps a spec's `component` name to one of 14 React components (`title`, `kinetic`, `filetree`, `flow`, `sequence`, `terminal`, `code`, `cards`, `table`, `timeline`, `quiz`, `openq`, `phase`, `split`), each called with its props and the box it must fit (measured: read `ship-explainer-video-v2/src/Visual.tsx`). The vocabulary and props are fixed in `STYLE.md` "Visual component vocabulary" (documented, `ship-explainer-video-v2/STYLE.md`).
- **Step by step.** An item with `at: n` enters when narration sentence n starts; `useReveal(at)` gives a 0.6 s eased progress plus a 1.5 s flat "fresh" highlight, driven by `useCurrentFrame()` from word-aligned sentence times (measured: read `src/ctx.tsx`). Items render from frame 0 at zero opacity so layout never jumps (documented, `COMPONENTS.md` "Layout stability").
- **Paging, not shrinking.** Text stays at least 18 px effective at 1080p; a list too tall for its box splits into pages that cross-fade (`PagedList` in `src/components/Phase.tsx`) rather than shrinking (documented, `.claude/skills/explainer-style/SKILL.md` "Text size"; measured: read `Phase.tsx` lines 76 to 120).
- **Gates.** `scripts/qa.mjs` renders every nth frame at quarter scale and exits 1 on overflow, off-frame, clipped or small text; `scripts/contrast.mjs` exits 1 on text under 4.5:1 (documented, explainer-style `SKILL.md` pipeline table; measured: read `qa.mjs`).
- **Layout.** `flow` lays out with dagre and measures every word with `@remotion/layout-utils` `measureText`, so node sizes are known before render, and edges draw on with `evolvePath` (measured: read `src/components/Flow.tsx`).
- **Track record.** The pipeline built a 33-minute explainer (documented, `COMPONENTS.md` line 4); its narration holds 90 `component:` specs, 17 of them `flow` (measured: `grep -h "component:" narration/*.md | sort | uniq -c`).
- **Gaps.** No right-to-left support anywhere in `src/` (measured: `grep -rn -E "direction|rtl" src` finds only graph direction), and `flow` accepts only `TB` or `LR` (measured: `Flow.tsx` line 297). The `code` component has line numbers, a `file:line` chip and narration-timed highlight ranges, but no syntax colouring: every token is `C.text` (measured: read `src/components/Code.tsx`). Styling is one hard-coded `src/theme.ts`, not a profile (measured: read).

## Options compared

| Option | Step by step under narration | Styleable from a profile | RTL with English terms | Legible at 1080p | Agent reliability | Licence |
|---|---|---|---|---|---|---|
| House registry (Remotion components) | Native: `at:` per item, frame-driven | Tokens in `theme.ts`; needs a profile loader | Not yet: no `rtl` path, `flow` has no RL | Gated by `qa.mjs` (18 px floor) | Highest: agent writes a fixed YAML vocabulary | Remotion licence (company licence for some entities) |
| Mermaid 12.2.0 | Built-in edge animation is infinite CSS dash; steps need DOM id targeting after render | `base` theme + `themeVariables`, hex colours only; `look: handDrawn` | Wrong order by default; correct with injected CSS and `flowchart RL` | Default `fontSize` 16px; scale unknown until rendered | High for syntax; animation and RTL need post-processing | MIT |
| D2 0.9.0 | Steps and scenarios as boards; animated SVG via CSS keyframes, each board laid out on its own | `theme-overrides`, custom TTF fonts, `--sketch` | Wrong order by default; correct with injected CSS | 16px default text | High for syntax; fast deterministic compile | MPL-2.0 (TALA layout engine is separate and proprietary) |
| Excalidraw / rough.js | rough.js: any frame-driven reveal; excalidraw-animate uses SMIL | rough.js options (roughness, bowing, stroke, fill, seed) | rough.js shapes + SVG text: correct with `direction="rtl"`; Excalifont lacks Arabic | Depends on host | rough.js inside components: high; Excalidraw JSON: low (absolute coordinates) | MIT both |
| Manim CE 0.22.0 | Native and strong (`play`, bookmarks via manim-voiceover) | Any code; nothing shared with the Remotion theme | Arabic alone fine; mixed lines drop Arabic words | Fine, CPU Cairo renderer | Low: bespoke Python per scene, hand-placed coordinates | MIT |
| Hand-built SVG per scene in Remotion | Native | Whatever the code reads | Browser bidi, if the code sets it | Gated by `qa.mjs` | Medium: free-form TSX per scene | n/a |

### Mermaid

- Theming: only the `base` theme is modifiable, through `themeVariables`, and "the theming engine will only recognize hex colors" (documented, [theming.md](https://github.com/mermaid-js/mermaid/blob/develop/packages/mermaid/src/docs/config/theming.md) lines 29, 136, 182). Default `fontSize` is 16px and `fontFamily` trebuchet (documented, same file lines 190 to 191). A `look: handDrawn` option exists alongside `layout: elk` (documented, [syntax-reference.md](https://github.com/mermaid-js/mermaid/blob/develop/packages/mermaid/src/docs/intro/syntax-reference.md)).
- Animation: edges take an id (`e1@-->`) and `{ animate: true }` or a `classDef` with `animation: dash 25s linear infinite` (documented, [flowchart.md](https://github.com/mermaid-js/mermaid/blob/develop/packages/mermaid/src/docs/syntax/flowchart.md) "Attaching an ID to Edges"). That is a CSS animation, and Remotion says CSS animations and transitions "do not track Remotion frame numbers, resulting in flickering, blank frames, or incorrect animation progress" (documented, [Remotion troubleshooting/css-animations](https://github.com/remotion-dev/remotion/blob/main/packages/docs/docs/troubleshooting/css-animations.mdx)). Step reveal therefore means rendering once, then driving each node and edge's opacity by id per frame (inferred).
- RTL: by default a mixed label `نقطة الـ merge base هنا` renders in left-to-right base order, so an Arabic reader meets the words out of order (measured: Mermaid 12.2.0 from jsDelivr in Playwright Chromium, label direction computed `ltr`). With `flowchart RL` and `themeCSS: ".nodeLabel, .edgeLabel, .label { direction: rtl; unicode-bidi: plaintext; }"` the order is right, but the default wrap width split `merge base` across two lines (measured, same page). Open upstream reports with Arabic input exist (documented, [mermaid#4151](https://github.com/mermaid-js/mermaid/issues/4151)).
- Hand-drawn conversion to Excalidraw supports flowcharts only; other diagram types become an image (documented, [mermaid-to-excalidraw api.mdx](https://github.com/excalidraw/excalidraw/blob/master/dev-docs/docs/@excalidraw/mermaid-to-excalidraw/api.mdx) line 29).

### D2

- Compiles a three-node diagram in about 5 ms with the 18 MB release binary (measured: `d2 --layout=dagre rtl.d2`, d2 v0.9.0 linux-amd64 tarball 18,020,287 bytes from the GitHub release).
- Steps: `steps` boards export as one animated SVG with `--animate-interval` (documented, [composition-formats](https://d2lang.com/tour/composition-formats), [blog/animation](https://d2lang.com/blog/animation)). The output switches boards with `animation: d2Transition-... 3000ms infinite` CSS keyframes, and each board has its own viewBox (434, 600, 766 px tall for three steps), so the frame resizes per step (measured: grep of `steps-d2.svg`). For Remotion, export boards separately or inline one SVG and drive elements by frame (inferred).
- Style: `theme-overrides` and `dark-theme-overrides` replace colour codes (documented, [themes](https://d2lang.com/tour/themes)); `--font-regular` and siblings take TTF files, and sketch mode respects a custom font since 0.7.1 (documented, [fonts](https://d2lang.com/tour/fonts), [0.7.1 release](https://d2lang.com/releases/0.7.1)); `--sketch` gives a hand-drawn look (documented, [hand-drawn-diagrams](https://d2lang.com/blog/hand-drawn-diagrams)).
- RTL: same left-to-right order fault as Mermaid in plain and sketch output; injecting `text{direction:rtl;unicode-bidi:plaintext}` into the SVG's style fixes the order (measured: Playwright Chromium). The SVG embeds only Latin font subsets (`d2-...-font-bold`, `-italic`), so Arabic falls back to whatever the browser has (measured: grep of `rtl-d2.svg`). No RTL option found in the docs or an issue search (inferred, thin).
- Licence MPL-2.0 (measured: `gh api repos/d2lang/d2/license`). TALA, needed for `near` and per-container direction, is a separate engine (documented, [layouts](https://d2lang.com/tour/layouts)).

### Excalidraw and rough.js

- rough.js draws sketchy shapes into SVG or canvas; without a seed each call is random, and `seed` makes it identical across runs (documented, [rough autodocs README](https://github.com/rough-stuff/rough/blob/master/_autodocs/README.md)). In Remotion every frame re-renders, so an unseeded shape would boil; a seed per element keeps it still (inferred). Text is the host's: rough.js boxes with SVG `<text direction="rtl">` rendered the mixed label in the right order (measured: Playwright Chromium, roughjs 4.6.6). MIT, last push July 2024 (measured: `gh api repos/rough-stuff/rough`).
- Excalidraw scenes are element JSON with absolute `x`, `y` (documented, [element skeleton](https://github.com/excalidraw/excalidraw/blob/master/dev-docs/docs/@excalidraw/excalidraw/api/excalidraw-element-skeleton.mdx)); `exportToSvg` returns a static SVG (documented, [export.mdx](https://github.com/excalidraw/excalidraw/blob/master/dev-docs/docs/@excalidraw/excalidraw/api/utils/export.mdx)). Its hand-drawn font has no Arabic: adding a Persian or Arabic font is still an open request (documented, [excalidraw#9984](https://github.com/excalidraw/excalidraw/issues/9984), [#11725](https://github.com/excalidraw/excalidraw/pull/11725)).
- excalidraw-animate animates the exported SVG with SMIL `<animate begin= dur=>` elements (measured: read `src/animate.ts` in dai-shi/excalidraw-animate). SMIL could be seeked per frame with `pauseAnimations()` and `setCurrentTime()` (inferred, not tried).

### Manim

- `merge_base.py` hand-places every commit in a `POS` dict, draws nodes and arrows itself rather than using `Graph`, and syncs to narration with manim-voiceover bookmarks (`<bookmark mark='q'/>`, `wait_until`); the scene is 436 lines (measured: read `video-lab/manim/merge_base.py`, `wc -l`). Composition is a separate render then an ffmpeg mix (measured: read `finish.sh`).
- `Graph` offers networkx layouts (`circular`, `kamada_kawai`, `partite`, `planar`, `random`, `shell`, `spectral`, `spiral`, `spring`, `tree`), no layered layout like dagre (measured: `manim/mobject/graph.py` lines 418 to 427, Manim 0.22.0). `Code` highlights with Pygments (measured: `code_mobject.py` imports).
- RTL: Manim's own docstring warns "don't mix RTL and LTR languages nothing shows up then" (documented, `text_mobject.py` line 416). A still with IBM Plex Sans Arabic rendered `نقطة الـ merge base هنا` whole (19 glyphs), but `الـ merge base هنا` and `كلمة merge base هنا` lost their leading Arabic word (12 glyphs each, 15 and 16 expected), silently (measured: `manim -s -ql` on a probe scene with the lab's venv, Manim 0.22.0, CPU).
- MIT (measured: wheel `License-Expression`).

### Code frames

- **Shiki** 4.5.0, MIT: `codeToTokens` returns themed tokens to render as spans (documented, [install.md](https://github.com/shikijs/shiki/blob/main/docs/guide/install.md)); themes can be a custom object or `createCssVariablesTheme`, whose colours are CSS variables (documented, [theme-colors.md](https://github.com/shikijs/shiki/blob/main/docs/guide/theme-colors.md)), so a style profile can set syntax colours without a theme file per profile (inferred). Tokens slot into the house `code` component, which already does frame-driven highlight ranges (inferred from `Code.tsx`).
- **Code Hike** 1.x, MIT: Remotion's official `template-code-hike` highlights with `codehike/code` `highlight()` and animates between snapshots with `calculateTransitions` from `codehike/utils/token-transitions`, mapping each transition's delay and duration onto `useCurrentFrame()` (measured: read `packages/template-code-hike/src/CodeTransition.tsx` in remotion-dev/remotion; template pins `codehike` 1.0.4). This is the frame-safe animated diff.
- **shiki magic move** (`@shikijs/magic-move` 4.5.0, MIT, now in the shiki monorepo): its renderer animates with CSS `transitionDuration` and `transitionDelay` (measured: grep of `dist/renderer.mjs` from `npm pack`), which Remotion cannot capture (documented, Remotion css-animations page above). Its core `codeToKeyedTokens` could feed a frame-driven renderer of our own (documented, README; inferred fit).
- **Motion Canvas**: `Code` node tweens between code strings with a patience diff and animates `selection` ranges (documented, [code/index.mdx](https://github.com/motion-canvas/motion-canvas/blob/main/packages/docs/docs/components/code/index.mdx)); `textDirection` exists for RTL text (documented, [motion-canvas#404](https://github.com/motion-canvas/motion-canvas/pull/404)). Rendering runs in the editor's browser, triggered by a `?render` URL (documented, `packages/ui/src/main.tsx` via Context7). Last stable release 3.17.2 on 2024-12-14, one alpha since (measured: `npm view @motion-canvas/core time`). A second engine for code alone is not worth it (inferred).
- **Manim `Code`**: Pygments styles, same separate-render cost as above (measured: imports).

## Agent reliability, ranked

1. **Registry spec** (inferred from the track record above): the agent fills a fixed vocabulary; layout, sizing, timing and paging are code; `qa.mjs` and `contrast.mjs` catch what slips. One known failure: a paging bug emptied a list and the gate read it as an improvement (documented, explainer-style `SKILL.md` critic loop step 4).
2. **Mermaid or D2 text** (inferred): familiar syntax with catchable parse errors, but each needs RTL CSS injection, font control, and per-element reveal added after render, so the agent's output is the easy part.
3. **Hand-built SVG per scene** (inferred): free-form TSX; works, but each scene is new code with new failure modes.
4. **Manim and Excalidraw JSON** (inferred from `merge_base.py`'s hand-placed coordinates and Excalidraw's absolute positions): the agent places geometry itself.

## Recommendation

1. **Diagrams stay registry components** drawn in Remotion. The agent writes `### Visual` YAML only; the vocabulary grows from the house's 14 components rather than adding a diagram engine.
2. **Add an `rtl` path to every component** for Arabic runs: `dir="rtl"` on text containers, English terms in isolated spans (`unicode-bidi: isolate`), and a `RL` direction in `flow` (dagre supports `rankdir: RL`). Keep a non-breaking space inside multi-word English terms so a wrap cannot split them, the fault the Mermaid probe showed.
3. **Style profile feeds `theme.ts` tokens** (palette, fonts, radius, stroke) plus one `look` switch: `clean` (today) or `sketch`, where node and edge outlines are drawn by rough.js with a seed per element id. Do not adopt Excalidraw itself.
4. **Code frames**: colour the `code` component from Shiki `codeToTokens` with a profile-driven CSS-variables theme; add a `codediff` component on Code Hike token transitions as in Remotion's template. Code stays left to right in Arabic runs.
5. **Mermaid, D2, Manim are not defaults.** Manim stays an opt-in for a bespoke algorithm scene like the merge-base walk, rendered to a clip, with Arabic labels kept on their own lines or in the Remotion overlay. Mermaid or D2 only as a later fallback for diagram kinds the registry lacks, with the RTL CSS and frame-driven reveal from the probes.

## Thin

- Code Hike token transitions, Shiki tokens and rough.js were read in source or docs, not rendered in a Remotion composition here; Arabic in a Code Hike frame (comments, strings) untested.
- The Manim word drop was seen on two short mixed strings with one font; the cause (Pango run split, Manim's glyph mapping) is not isolated.
- D2 RTL: no option found, but the issue search was keyword-only.
- Seeking excalidraw-animate's SMIL per frame is untried.
- Mermaid step reveal by element id across Mermaid versions (id stability) is untested.
- Remotion's licence terms for this skill's users belong to the engine tickets (#653, #660), not here.
