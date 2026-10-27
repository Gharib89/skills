# Measuring Arabic joins on the rendered output

Research for [#976](https://github.com/Gharib89/skills/issues/976) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-27.

Labels: **measured** (a command was run, named inline), **sourced** (a primary
source, cited), **inferred** (my reasoning from those).

Versions (measured): hyperframes 0.8.197 and its Chrome headless shell
152.0.7977.30, puppeteer-core 25.16.0, harfbuzzjs 1.6.4, GSAP 3.14.2, Node
24.20.0. Probe: `prototypes/creative-arabic-joins-probe/` (`build.mjs`,
`measure.js`, `probe.mjs`, `summarise.mjs`, `visual.mjs`).

## Answer

**Yes.** A scene gate can measure, at each sample frame, whether every Arabic
text box drew the same letter shapes as its words set unsplit, in about 2 ms a
box, with no false positive on correctly authored text. The measure that wins
is **shaped runs**, not widths or pixels.

The gate, as probed:

1. At a sample frame, copy each text box that holds Arabic, strip the motion
   from the copy and its descendants (`transform`, `translate`, `rotate`,
   `scale`, `filter`, `opacity`, `animation`), and keep every element's
   `display`. The display is what changes the shapes: the browser shapes each
   box that is not `inline` on its own. Transforms only move the letters.
2. Cut the copy's text into words at white space, or where two boxes stand
   apart by more than a tenth of the font size. A flex `gap` or a margin
   counts as a space; letters whose boxes touch are one word.
3. Split each word into runs at every box that is not `inline`. These are the
   runs the browser shaped. Shape each run with HarfBuzz in the box's face,
   then compare the glyph ids and offsets with the word shaped whole. ZWJ's own
   glyph is dropped.
4. Fail the box on any word that differs, naming the word.

## Measurements

Corpus (measured, `node probe.mjs`): 12 Egyptian Arabic sentences (harakat,
lam-alef, digits, a Latin file name, a sentence of only right-joining letters),
each set in 7 split styles. These are 8 faces: Noto Sans, Naskh, Kufi and
Nastaliq Urdu, IBM Plex Sans Arabic, Amiri, Cairo and Tajawal. Every unit was
animated by a paused GSAP timeline (y, rotation, scale, opacity, colour) and
measured at 0.3 s, 1.0 s and 3.0 s. That is 2,016 box-frames and 12,096
word-frames.

Truth is a rule oracle in `build.mjs`, independent of every measure. A word
breaks when the split separates two letters that join, takes a mark off its
base, makes a ZWJ force a join the letters do not make, splits lam-alef, or
splits a Latin or digit run into letters.

| Measure | Join defects caught | Failed on correct text (word-frames) | Failed on correct text (boxes) | Cost per box, median (max) |
| --- | --- | --- | --- | --- |
| **shaped runs** | 2,697 of 2,700 | **0 of 6,912** | **0 of 1,152** | 1.8 ms (25 ms) |
| advance width | 2,547 of 2,700 | 6 of 6,912 | 6 of 1,152 | 1.6 ms (25 ms) |
| pixels (ink IoU) | 2,619 of 2,700 | 123 of 6,912 | 90 of 1,152 | 113 ms (482 ms) |

"Correct text" covers the four styles that keep every word's letters in one
shaping run: unsplit text, whole words as `inline-block` spans, whole words in
a flex row with `gap`, and per-letter `inline` spans that animate only colour.

- **Shaped runs.** The 3 misses are Noto Kufi لا under the naive ZWJ split,
  which pixels also read as identical (inferred: Kufi draws the joined lam and
  alef like its ligature). The measure is the same at all three frames (the
  failure count per frame is equal), so the motion is out of the measurement.
- **Width** cannot see a mark taken off its base (57 missed), since a mark has
  no advance. It also misses a join that reshapes a letter at the same width
  (81) and some lam-alef splits (18). Its 6 false positives are Nastaliq
  per-letter colour spans.
- **Pixels** fail correct Nastaliq and Plex text because a word's crop catches
  its neighbours' ink (Nastaliq's tall cascades and marks). Pixels also take a
  screenshot per box, which costs 60 times the shaped measure. They are the
  only measure that sees a reversed Latin or digit run.

**Not a join defect, so no measure here owns it:** splitting `12`, `40` or
`CLAUDE.md` into one `inline-block` per character reverses them on an RTL line
(132 word-frames). Shaped runs compare glyphs, not order. That stays with the
critic's `rtl` kind.

## Remotion's ZWJ split is not shape-safe in every face

Remotion's `arabic-text.md` says that with its ZWJ split, "the letters join
exactly as in the unsplit word" (sourced,
`remotion-dev/remotion` `packages/skills/skills/remotion-markup/arabic-text.md`).
That holds for joining, but not for every face. Words the shaped measure
failed under that split, of 72 per face, at the rest frame (measured):

| Face | Words that differ | What differs (by eye, `snap/visual.png` from `node visual.mjs`) |
| --- | --- | --- |
| Noto Nastaliq Urdu | 52 | the diagonal cascade flattens |
| Amiri | 32 | stacked ligatures (بت, لم) come apart |
| Tajawal | 8 | mark offsets |
| IBM Plex Sans Arabic | 7 | the في ligature comes apart |
| Noto Sans Arabic | 6 | heh after dal takes another glyph (479 against 482, same advance); invisible at a glance |
| Cairo | 5 | على loses its contextual form |
| Noto Naskh, Noto Kufi | 0 | none |

A lint on the split cannot know any of this, because it depends on the face's
GSUB and GPOS tables. Measuring the output catches it in every face, with no
rule on how the author splits. This is the case for the gate the gate set
chose (inferred).

## What it costs the skill (inferred unless marked)

- **A dependency.** harfbuzzjs (WebAssembly, MIT-licensed HarfBuzz), loaded once
  per gate run.
- **The face file.** Each box's face must resolve to a file, and to the face the
  browser actually drew, not the one the CSS names. Measured: `hyperframes
  snapshot` of the Amiri composition did not serve the `../../fonts` face and
  drew a system sans instead. Shaping with the named file would then compare
  the wrong font. Chrome reports the face it used per node through CDP
  `CSS.getPlatformFontsForNode`. Map that name to the composition's
  `@font-face` source or to `fc-match`. A box whose face cannot be resolved
  goes to the critic's `rtl` kind.
- **A browser session** on the scene at its sample frames, with DOM access.
  `hyperframes check --at` (what `explainer-video`'s layout gate runs) cannot
  run a page script. The gate drives HyperFrames' Chrome itself (puppeteer-core,
  `hyperframes browser path`), which the layout and determinism gates may share.
- **Time.** About 2 ms per box per frame. A scene with 10 Arabic boxes at 5
  sample frames costs about 0.1 s.

## Render evidence

`hyperframes snapshot comp/amiri --at 3` (measured) draws the naive ZWJ split
and the per-letter split visibly broken in HyperFrames' own render. Correct
rows match the unsplit row. The frame comes from the same DOM the gate reads.
