# Video design references for explainer-video

Research for [#656](https://github.com/Gharib89/skills/issues/656) on the
[explainer-video map](https://github.com/Gharib89/skills/issues/651).

Labels: **measured** (a command was run, named inline), **documented** (a
primary source says so, linked), **inferred** (my reading, no direct proof).

## Answer

Excellent explainers share four habits, whatever their look: the narration sets
the timing and the picture follows it; one visual idea carries each spoken
idea; colour means something and keeps meaning it; and the look stays
consistent while the content changes. The five style prototypes should try
five directions that differ on the axes a technical viewer feels most
(background lightness, how much is drawn versus shown, and pace):

| # | Direction | Ground | Draws or shows | Pace | Lineage |
|---|---|---|---|---|---|
| 1 | **Claude Code dark** (house) | warm charcoal | diagrams, cards, terminals | calm, sentence-led | owner's ship explainer |
| 2 | **Chalkboard math** | near-black | computed diagrams that transform | slow, room to think | 3Blue1Brown, lab `manim` |
| 3 | **Flat vector world** | deep indigo, illustrated | visual metaphors | medium | Kurzgesagt |
| 4 | **Editorial paper** | warm paper | the real artefact as evidence, marked up | fast open, then steady | Vox, lab `hyperframes`, `remotion-markup` |
| 5 | **Kinetic dev poster** | near-black, hard colour | big words and code, beat-cut | fast | Fireship, lab `anything2explainer`, `hyperframes` |

Every proposed Latin and Arabic face below is OFL and ships as a module in
`@remotion/google-fonts` 4.0.535, so each direction is commercial-safe and
loadable without a font download step (measured, see [Type](#type-and-arabic-companions)).
Every text colour proposed below passes 4.5:1 on its ground (measured, see
[Contrast](#contrast-check)).

## What the references do

### Kurzgesagt

- The studio names its toolkit as "vector illustration, pixel-based
  illustration and infographics" and combines "classic 2D flat animation with
  3D elements"; the narrator's "voiceover provides the timing for the animation
  team", and each video gets "its own specifically composed soundtrack"
  (documented: [kurzgesagt.org/youtube](https://kurzgesagt.org/youtube/)).
- Script runs about "a dozen drafts", and visual metaphors are chosen in a
  sketching phase before illustration (documented: same page).
- Scale: "On average, 200 panels need to be illustrated", most "from scratch",
  by two to three illustrators over 8 to 12 weeks, and "at least 1,200 hours
  for a single Kurzgesagt video" (documented: the studio's own video *How to
  Make a Kurzgesagt Video in 1200 Hours*, quoted from its transcript on
  [LingQ](https://www.lingq.com/en/learn-english-online/courses/689474/how-to-make-a-kurzgesagt-video-in-120-4887128/)).
- Consequence for the skill: the look is bespoke illustration. An automated
  run can only approximate it with a parametric kit of flat shapes, so the
  prototype tests whether a kit reads as "illustrated" or as clip art
  (inferred).

### 3Blue1Brown

- Almost all animations are made with Manim, Grant Sanderson's own Python
  library (documented: [3blue1brown.com/faq](https://www.3blue1brown.com/faq/)).
  ManimGL is MIT-licensed (measured: `curl` of
  [LICENSE.md](https://github.com/3b1b/manim/blob/master/LICENSE.md)).
- The library's default palette is the channel's colour vocabulary:
  `blue_c #58C4DD`, `blue_e #1C758A`, `teal_c #5CD0B3`, `green_c #83C167`,
  `yellow_c #FFFF00`, `gold_c #F0AC5F`, `red_c #FC6255`, `grey_brown #736357`,
  default background `#333333`, default text font Consolas (measured: `curl`
  of [manimlib/default_config.yml](https://github.com/3b1b/manim/blob/master/manimlib/default_config.yml)).
- The defining move is continuity: an object transforms into the next idea
  instead of being replaced, and a colour stays bound to one quantity
  (inferred from the library's `Transform` family and the channel's videos;
  not stated in a writeup I could read).
- Lab evidence: `video-lab/manim` drove its `git merge-base` walk from a small
  simulation of git's algorithm rather than hand keyframes, on `#0B0D12` with
  teal, pink and gold in IBM Plex (measured: `merge_base.py` constants and the
  session's closing report).

### Vox

- Joss Fong on the black hole explainer: open fast ("so many options right
  next to your video"), withhold the result until the viewer understands why it
  is hard, keep music from competing with speech, and change the song "every 20
  seconds" because song starts and stops cue the viewer; motion graphics are
  After Effects (documented:
  [The Open Notebook, 2020](https://www.theopennotebook.com/2020/01/07/videogram-how-a-vox-video-explains-the-science-behind-the-first-photo-of-a-black-hole/)).
- Johnny Harris describes the Vox style as balancing "visual evidence and
  explanation", with first-hand visual anchors over long narration
  (documented, reported speech:
  [Press Gazette](https://pressgazette.co.uk/vox-youtube/)).
- Consequence: for a repo or document source, the evidence is the artefact
  itself (a file, a diff, an issue), shown and marked up rather than redrawn
  (inferred).

### Apple and Stripe product films

- Stripe's motion rules: custom cubic-bezier curves instead of built-in
  easings, transitions "under 500 milliseconds", animate only `transform` and
  `opacity`, and "Animations should never get in the way" (documented:
  [Stripe, De Cock 2017](https://stripe.com/blog/connect-front-end-experience)).
- Stripe's palette work: vibrant hues kept accessible by building in CIELAB,
  with any two colours "at least five levels apart" safe for small text
  (documented: [Stripe, Koopersmith and Miner 2019](https://stripe.com/blog/accessible-color-systems)).
- Apple's SF Pro licence limits the font to mock-ups of interfaces for Apple
  platforms (documented: [developer.apple.com/fonts](https://developer.apple.com/fonts/),
  wording reported by search; I did not read the licence file). So the Apple
  look cannot ship its own type.
- Not a sixth direction: a product film's hero is real UI footage, which a
  repo or topic source rarely has, and its light, quiet surface sits close to
  Editorial paper. Its motion rules (short, eased, transform-only) go into
  every direction instead (inferred).

### Fireship and developer channels

- Fireship's "100 Seconds of Code" format compresses one technology into 100
  seconds with dense on-screen code and quick cuts (documented only by
  third-party summaries, e.g.
  [Honeypot interview page](https://cult.honeypot.io/originals/meet-jeff-delaney-fireship);
  the channel itself is the primary source and I did not find a design
  writeup). Treat its pacing numbers as thin.
- Lab evidence of the same register: `anything2explainer` set amber, coral
  (failure) and mint (success) on near-black in Unbounded and JetBrains Mono,
  pinned every beat to word timings, and the session would use it again for
  narrated one-to-three-minute explainers; `hyperframes` cut six CSS posters on
  the downbeat of a 120 BPM bed (117 of 119 grid slots, 4 ms median error);
  `remotion-markup` locked kinetic type to 15-frame beats (measured: each
  session's closing report and `src/theme.ts` / `STORYBOARD.md`).
- `motioncraft`'s `tech-neon-soft` uses `glow` tokens (`rgba(124,240,200,0.18)`)
  and blur-in words (measured: `video/src/style.json`), which conflicts with
  the owner's no-glow rule; its usable ideas (word-timed headlines, one accent
  per sentence, at most 7 words a line) fold into direction 5 without the glow
  (inferred).

### Arabic-language explainers and right-to-left design

- AJ+ Arabic's short explainers lean on "modern graphic elements" and colour
  and iconography to simplify (documented, abstract only:
  [Palestine Polytechnic University study](https://scholar.ppu.edu/handle/123456789/9483)).
  Kurzgesagt lists Arabic among languages with localized versions (documented:
  [Wikipedia, Kurzgesagt](https://en.wikipedia.org/wiki/Kurzgesagt), secondary).
  I found no published design writeup from an Arabic explainer studio; the
  rules below come from the standards bodies and platform guidelines instead.
- Layout mirrors when Arabic is the main script, and Arabic lines right-align
  (documented: [W3C alreq](https://www.w3.org/TR/alreq/) 3.1, 7.2).
- Latin runs inside Arabic keep left-to-right order, and a line is never read
  bottom to top when an English term wraps (documented: alreq 3.2.1, 7.1). For
  the skill this means each English technical term is an isolated LTR run
  (`<bdi>` or `unicode-bidi: isolate`) in titles and captions (inferred).
- Digits keep their order inside RTL text; Arabic text may use Western or
  Eastern Arabic numerals, varying by country; reverse progress and ordered
  sequences, never the digits (documented:
  [Apple HIG, Right to left](https://developer.apple.com/design/human-interface-guidelines/right-to-left)).
  Western digits suit English-term technical narration (inferred).
- Flip progress, navigation and ordered rows; do not flip photographs,
  illustrations or controls that point to a real direction (documented: Apple
  HIG, same page). Media playback controls and the media progress bar are not
  mirrored (documented:
  [Material bidirectionality](https://m2.material.io/design/usability/bidirectionality.html)).
  So a scene's flow (a pipeline, a timeline, a phase rail) runs right to left
  in an Arabic run, while a terminal and a code block stay LTR (inferred).
- No letter-spacing on Arabic: moving joined letters apart "creates
  undesirable results"; stretching is kashida, not tracking (documented:
  alreq 4.3.7.1, 7.2.5). Arabic has no case, so an all-caps Latin kicker needs
  a weight or colour equivalent, and Arabic set next to uppercase Latin reads
  small: Apple suggests about 2 pt larger (documented: Apple HIG, same page).
- Arabic ascenders and descenders extend "much further" than Latin
  (documented: alreq 7.4), so Arabic captions need a taller line box than the
  Latin 1.15 to 1.35 used in the lab (inferred).

## The five directions

Common to all five (from the references above): narration drives timing,
one accent per sentence, colour bound to meaning, transform and opacity
motion under 500 ms for UI-like elements, and no glow (owner's rule).

### 1. Claude Code dark (house)

- **Palette**: bg `#1a1915`, panel `#262420`, line `#3d3a33`, text `#f5f3ec`,
  dim `#b8b3a6`, brand clay `#dc7a5a`, ok `#8fae6b`, warn `#e3c07a`, stop
  `#e47460`, plus one accent per phase (measured:
  `ship-explainer-video-v2/src/theme.ts`).
- **Type**: Source Serif 4 titles, Inter UI and captions, JetBrains Mono code
  (measured: same file). Arabic: **Noto Naskh Arabic** for titles (a Naskh
  matches the serif's book tone) and **IBM Plex Sans Arabic** for captions
  and UI; both OFL.
- **Grid**: header band, content box 1760 x 690 at (80, 178), caption band
  below; text at least 18 px effective at 1080p (measured: `theme.ts`
  `CONTENT`, `explainer-style` SKILL.md).
- **Motion**: an item reveals at the sentence that names it and keeps a flat
  highlight until the next; tables grow row by row; terminals type with a
  block cursor and tip up from rotateX 20deg; one neutral depth shadow only
  (documented: `explainer-style` SKILL.md).
- **Pacing**: calm, sentence-led; dense lists are paged rather than shrunk.
- **Why for technical explainers**: it is the only direction already proven
  end to end with layout, contrast and critic gates, and a quiet ground keeps
  code and diagrams the loudest thing on screen (inferred).

### 2. Chalkboard math

- **Palette**: bg `#0e1116`, ink `#ece8df`, muted `#8a93a3`, and the ManimGL
  semantic hues `#58c4dd` blue, `#f0ac5f` gold, `#fc6255` red, `#83c167`
  green, `#5cd0b3` teal (values measured from ManimGL's config; the darker
  ground follows the lab run, not the library default `#333333`).
- **Type**: IBM Plex Sans and IBM Plex Mono, math typeset with LaTeX
  (`MathTex` or KaTeX). Arabic: **IBM Plex Sans Arabic** (same superfamily,
  designed by Khajag Apelian and Wael Morcos with Bold Monday; OFL), so Latin
  and Arabic share metrics and stroke.
- **Grid**: one centred stage, no chrome; a diagram owns the frame and labels
  sit beside their object, never in a sidebar.
- **Motion**: continuous transformation (an object becomes the next idea);
  colour is a variable's identity across scenes; motion is computed from a
  simulation of the real algorithm, as the lab's merge-base walk was.
- **Pacing**: slow, with deliberate holds after each reveal so the viewer can
  predict the next step.
- **Why**: algorithms, data structures and graphs (git DAGs, queues, state
  machines) are best explained by watching the structure change; computing
  the animation keeps it correct (inferred, lab-backed).

### 3. Flat vector world

- **Palette**: night `#1d2142`, mid `#2b3168`, far `#3b4285`, text `#fff7e8`,
  soft text `#b9bde0`, sun `#ffc857`, coral `#ff6b6b`, teal `#4ecdc4`, violet
  `#a78bfa` (my own proposal in the Kurzgesagt register, not the studio's
  values).
- **Type**: **Rubik** for titles and labels; its OFL family carries Arabic in
  the same font (Arabic by Omaima Dajani per the family's designer list), so
  one face covers both scripts. Alternative Arabic display: **Baloo Bhaijaan 2**
  (OFL), rounder and friendlier.
- **Grid**: full-bleed illustrated scenes in three parallax layers, horizon
  near the lower third, one subject centred; text limited to short labels.
- **Motion**: idle motion everywhere (things breathe, orbit, blink), parallax
  camera drift, match cuts from one metaphor to the next; 2D flat with
  occasional 3D, as the studio describes.
- **Pacing**: medium; one metaphor per idea, held long enough to read its
  parts.
- **Why**: abstract systems (an agent loop, a network, a cache) become
  memorable as places and objects, and it is the most approachable look for a
  non-specialist audience; the risk is cost and clip-art drift, which the
  prototype must measure (inferred).

### 4. Editorial paper

- **Palette**: paper `#f2ede3`, ink `#141210`, muted `#5e574c`, highlighter
  `#ffe14d` (a fill under ink, never text), red `#c8321c`, ultramarine
  `#1f2bd9`, green `#2f6b3a`; grain overlay at 0.10 (paper, ink, lemon and
  ultramarine from the lab's `hyperframes` STORYBOARD.md; red darkened from its
  `#E2331B` to pass small-text contrast).
- **Type**: **Fraunces** display serif, **Inter** body, **JetBrains Mono** for
  quoted code. Arabic: **Markazi Text** for headlines (a text Naskh by Borna
  Izadpanah, Florian Runge and Fiona Ross; OFL) and **IBM Plex Sans Arabic**
  body.
- **Grid**: 12-column editorial grid; a narrow text column beside a wide
  evidence column holding the real file, diff, issue or doc page.
- **Motion**: the camera pans and zooms across documents; highlights sweep,
  lines are struck through and circled by hand (as in `remotion-markup`'s
  break scene); callouts draw on; transitions are paper cuts and slides.
- **Pacing**: a fast hook, then steady; withhold the answer until the problem
  is felt, and change the music at section turns (Fong).
- **Why**: for a repo or document source, showing the actual artefact is the
  strongest proof, and a light ground prints code screenshots without
  re-theming them; it is the only light direction, so it tests the axis
  (inferred).

### 5. Kinetic dev poster

- **Palette**: bg `#0a0b10`, text `#ffffff`, grey `#a0a0a1`, amber `#ffb020`
  (primary), coral `#ff4d6d` (failure), mint `#2ef0b0` (success); ink on amber
  fills, hard offset shadows instead of glow (measured: lab
  `anything2explainer/video/src` constants).
- **Type**: **Unbounded** display, **JetBrains Mono** code and captions.
  Arabic: **Alexandria** (OFL, by Egyptian designer Mohamed Gaber with Julieta
  Ulanovsky), a wide geometric that matches Unbounded's stance; **Lalezar**
  (OFL) as a heavier display alternative.
- **Grid**: poster cards: two to four words fill the frame; a code panel takes
  the full width when shown; constant chrome (top rail, scene number) keeps
  the series coherent, as `hyperframes` did.
- **Motion**: words slam in on the beat, typed code with a caret, staggered
  block wipes, cuts on downbeats of a 120 BPM bed (2 s bars).
- **Pacing**: fast, a new card every one to two seconds; best at 60 to 120 s.
- **Why**: developers skim at speed, and short "what is X" pieces win on
  information rate; the word-timed, beat-cut grammar was the lab's tightest
  result. The risk is fatigue at five minutes, which the prototype should
  test at the long end (inferred).

## Type and Arabic companions

Licence, designers and Arabic subset per face (measured: `curl` of each
`METADATA.pb` under [google/fonts](https://github.com/google/fonts/tree/main/ofl));
Remotion module presence (measured: `ls` of
`video-lab/remotion-markup/node_modules/@remotion/google-fonts/dist/esm`,
version 4.0.535).

| Face | Licence | Arabic subset | `@remotion/google-fonts` | Used in |
|---|---|---|---|---|
| IBM Plex Sans Arabic | OFL | yes | yes | 1, 2, 4 |
| Noto Naskh Arabic | OFL | yes | yes | 1 |
| Rubik | OFL | yes | yes | 3 |
| Baloo Bhaijaan 2 | OFL | yes | yes | 3 (alt) |
| Markazi Text | OFL | yes | yes | 4 |
| Alexandria | OFL | yes | yes | 5 |
| Lalezar | OFL | yes | yes | 5 (alt) |
| Source Serif 4, Inter, JetBrains Mono | OFL | no | yes | 1 |
| IBM Plex Sans, IBM Plex Mono | OFL | no | yes | 2 |
| Fraunces | OFL | no | yes | 4 |
| Unbounded | OFL | no | yes | 5 |

Also checked and OFL with Arabic: Noto Kufi Arabic, Noto Sans Arabic, Amiri,
Readex Pro, Cairo, Tajawal, Reem Kufi, Vazirmatn, El Messiri, Mada, Almarai,
Zain, Aref Ruqaa, Rakkas (measured, same command).

## Contrast check

WCAG ratio of every proposed text colour on its ground (measured: a Python
relative-luminance script over the hex values above). Lowest per direction:

| Direction | Ground | Lowest text colour | Ratio |
|---|---|---|---|
| 1 Claude Code dark | `#1a1915` | faint `#8f897c` | 5.1 |
| 2 Chalkboard math | `#0e1116` | muted `#8a93a3` | 6.1 |
| 3 Flat vector world | `#1d2142` | coral `#ff6b6b` | 5.6 |
| 4 Editorial paper | `#f2ede3` | red `#c8321c` | 4.6 |
| 5 Kinetic dev poster | `#0a0b10` | coral `#ff4d6d` | 6.1 |

Ink on the highlighter (`#141210` on `#ffe14d`) is 14.4 and ink on amber
(`#0a0b10` on `#ffb020`) is 10.7.

## Recommendation

Build the five prototypes as listed, each rendering the same three scenes (a
title, a diagram that changes, a code frame with a caption) in English and in
Egyptian Arabic, so the comparison isolates the look. Keep Claude Code dark as
the presumptive default: it is the only direction already proven with gates.
Watch two risks: Flat vector world may read as clip art without hand
illustration, and Kinetic dev poster may tire viewers past two minutes; if
either fails, its best parts become options inside a surviving profile.
Apply the RTL rules above to every direction, since they are layout rules,
not style choices.

## Thin

- No primary design writeup from Kurzgesagt, Vox, Apple or Fireship names
  their palettes or typefaces; their looks above are described from their
  process statements, not from their style guides.
- The 3Blue1Brown FAQ page timed out on `curl`; its Manim claim is from the
  search excerpt of that page. The "continuous transformation" reading is
  inferred, not quoted from Sanderson.
- Fireship's pacing figures come from third-party summaries only.
- No Arabic explainer studio's own design writeup was found; Kurzgesagt's
  Arabic channel was not confirmed.
- Apple's SF Pro licence wording is from search excerpts, not the licence file.
- Palettes for directions 3 and 4 are my proposals; their legibility at
  caption size, and Arabic rendering of each pairing, are untested until the
  prototypes render.
