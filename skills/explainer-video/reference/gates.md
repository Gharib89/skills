# Gates

## Contents

- [The critic round](#the-critic-round)
- [On a red gate](#on-a-red-gate)
- [Floors](#floors)

A **video gate** checks the rendered video against a floor and blocks: a red
gate means no video. The render stage runs them all after every render;
`node <skill>/scripts/gates/gates.mjs explainers/<slug>` re-judges the render
still in `out/`, which only a green render leaves (a red render empties
`out/`, so render again, which reuses the cached video), and deletes nothing.
Each prints `gate <name>: pass|fail: <measured> vs <floor>`:

- `layout`: HyperFrames' check, plus the layout probe (text at least 18 px,
  nothing clipped or overflowing its box, every text box inside the 5 percent
  safe margin, no text box overlapping another), judging a box only while it
  is **readable**: fully shown, outside any scene's seam (the outgoing scene's
  exit and the next scene's entry both count) and not carried by its own
  camera. A finding of HyperFrames' check on a box that is not readable is
  held back too. The frames are the 0.5 s grid, each scene's settled last
  frame and every **timeline event**
  (the end of a tween, the start and end of a seam or camera move, read off the
  scene's GSAP timeline, the seam and camera as the label pairs
  `seam:start`/`seam:end` (numbered `seam:start2` for a scene's second seam)
  and `camera:start`/`camera:end`), one sample per
  whole frame. A scene with no text in any sample is a hard error.
  In an Arabic run, the probe also holds
  the reading rules: `dir` on the text boxes and never on a page root
  (`dir on the page root <el>`), Arabic text reading right to left with no
  Latin run left in it (`Arabic reads <dir>`, `Latin run not isolated in`), each
  English term isolated on one line (`Latin run not isolated`, `Latin run
  wraps`), and a line height no less than the ink Arabic's letters span in
  the text's face and weight, measured once per face and weight in the browser
  (`line height <h> under the ink <i> of <face>`). Code frames and terminals
  read left to right as written, so their text is exempt.
- `contrast`: 4.5:1 for body text and 3:1 for large text (24 px, or 18.66 px
  bold), on the same frames. The palette check when the profile loads holds
  the faint, accent and status colours to 3:1 only, since the scenes draw them
  large; text drawn small in one of them is held to 4.5:1.
- `reading`: every text box **readable** in one unbroken stretch long enough
  for its words, judged on the same frames: its longest single stretch against
  0.8 s for three words or fewer, else 0.3 s a word and at least 1.2 s. Two
  short stretches never add up. A kinetic line of the `words` component whose
  words each rise on their own spoken words is **read along** with the voice:
  one box, judged whole and exempt from words per second. It must stay
  readable whole (every word up, outside any seam or camera move) for 0.8 s.
  A `words` line cued off its own spoken words is judged like any box. A red
  line names the scene, the box's text and its longest stretch.
- `loudness`: -14 LUFS plus or minus 1 and a true peak at most -1 dBTP,
  measured on the encoded MP4.
- `captions`: every word timed in order inside its scene, every cue non-empty,
  in order, at most 84 characters and inside the video, and the SRT equal to
  the burned-in cues.
- `sfx`: at most 24 sound effects in any minute of `score.json`.
- `determinism`: each scene's **peak-motion frame**, outside every seam window
  (its middle frame when nothing in the scene moves), rendered twice, in two
  separate browser launches of the pinned Chrome and the HyperFrames runtime
  seek, and the SHA-256 of the decoded pixels compared, never the PNG files'. A
  frame mid-move catches what a settled one hides, such as a time source other
  than the seek. It has no floor but equal pixels, and a profile's
  `gates.determinism` block is refused with `no such floor`. A red line names
  the scene, the frame and its time, and both renders' PNGs under
  `.cache/gates/frames/` as evidence.
- `critic`: the **critic**, Claude subagents reading one **contact sheet** per
  scene (four of its frames, cut from the MP4 by ffmpeg: its three quarter
  marks, then its **fullest moment**, the sample with the most readable words
  at once, the latest on a tie) and its **motion strip**, fails on any hard
  failure: `unreadable` or `invented` content. Its scores (clarity,
  legibility, fit, motion, 1 to 5) and its `worst` list (at most 3 defects per
  scene, each with the one change that would fix it) only
  advise: the line shows the score means, and `gates.md` lists the scores and
  the worst defects per scene. Until the critic has judged this render the gate
  reads `gate critic: pending: round <r> of 2, ..., contact sheets in
  <sheets>`.

The **peak-motion frame** is the scene's frame with the largest mean absolute
pixel difference from the frame before it, measured on the encoded MP4
downscaled and over the content band alone (the caption words recolour at every
word, so the whole frame would always peak on a caption); a tie goes to the
earliest frame, frames inside a seam window are not candidates, and a scene
whose largest difference is under the encode's noise floor is still and takes
the frame nearest its middle outside every seam (a scene wholly inside a seam
falls back to its unfiltered peak). One helper (`scripts/lib/motion.mjs`)
picks it for the determinism gate and the strip. The **motion strip** is 12
consecutive frames of the scene from 5 before the peak-motion frame (clamped
inside the scene), 320x180 a tile on a 6x2 grid in reading order, cut beside
the scene's contact sheet as `<scene>.motion.png`; a still scene has none.
`<scene>.motion.json` beside it holds the peak frame and its time, the strip's
first and last tile times and each still stretch of the content band lasting
1.5 s or more.

A summary line follows, `gates: <n> pass, <m> fail[, 1 pending]`, ending on a
red run with `next: fix attempt <a> of 2` or `stop: red after two fix
attempts, no video`, and when the critic alone holds the video with `next: run
the critic, round <r> of 2`. A red determinism gate ends it `stop: determinism
is red, a skill defect to report, no fix attempt, no video`. Layout, contrast,
reading and determinism results are cached per scene by everything that
draws it, so a fix re-gates only the scenes it touched; loudness, captions
and sfx run every time. The stage writes `gates.json`, the machine record,
and `gates.md`, the readable report with every red gate's findings and the
critic's scores.

## The critic round

Run it when the summary ends `next: run the critic`; a pending critic beside a
red gate waits for that gate's fix, so no round is spent on a render the fix
replaces.

1. Dispatch one subagent per scene whose `<run>/<sheets>/<scene>.png` has
   no `<scene>.json` beside it (`<sheets>` is relative to the run folder,
   `<run>`), at most 20 at once, each with
   `<skill>/agents/critic.md` as its prompt, `{run}` the run folder, `{scene}`
   the scene id and `{sheets}` the folder the pending line names. Each writes
   its verdict and replies with one `critic <scene>:` line. Claude Code
   refuses a subagent past 20 running, so send the next batch once every
   critic in this one has replied. Never read a sheet or a verdict here.
2. Render again: the video is cached, so this only judges it.
3. On `gates: critic verdict <scene>.json: <why>`, send the line to that
   scene's critic to fix, then render again.

The critic judges two renders of one script at most, a render counting anew when
only its cites or a cited excerpt's text changed. Each scene's verdict stands
for its sheet, motion strip and record, its span in the video, its visual, the
title, every cite in the script and its excerpt's text (each critic reads them
all) and the verdict format: a new render copies the verdict of every unchanged
scene beside its new sheet, so step 1 dispatches only changed scenes, and the
render still counts as the next round. A hard failure in the second round is
final, so the summary ends `stop: the critic's second round is red, no video`. A
third render reuses the second round's verdict, its line ending `carried: no
third round`; new narration is a new script and starts at round 1.

## On a red gate

Relay its line and fix what its findings name **inside the script**: the
visual's layout, its text size, colours within the profile, timing, or
re-voiced audio, never the narration, the scene order or the scene count. A
critic's `invented` finding is fixed in the visual: show what the narration
and its excerpts say. Compile, voice if the audio changed, and render again.
A red `determinism` gate is a skill defect, not a script fault: the same script
rendered twice differs, so no fix to the script could clear it, and the run
stops at once with no fix attempt. Report the component and the frame its line
names, and never patch the script.

The attempt counts live in `gates.json`: each gate's count resets when that
gate passes, and the run's count, which `stop` reads, when every gate passes.
Both reset when the narration changes, so a red that moves from one gate to
another still stops. On `stop`, stop with no video and run Storyboard step 7.

## Floors

Floors are set in the skill. A profile's optional `gates` block may only
tighten them, and the tightened value is the one applied and printed:
`contrast` (`body`, `large`, raise), `layout` (`textPx`, `margin` as a
fraction, raise), `loudness` (`tolerance` in LU, above 0, and `peak` in
dBTP, no lower than -8.5, lower), `sfx` (`perMinute`, lower). The reading
gate's floors (0.8 s up to three words, else 0.3 s a word and 1.2 s at least;
0.8 s for a line read along) are fixed. The critic and the determinism gate
have no floor to tighten.
