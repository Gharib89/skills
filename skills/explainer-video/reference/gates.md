# Gates

A **video gate** checks the rendered video against a floor and blocks: a red
gate means no video. The render stage runs them all after every render;
`node <skill>/scripts/gates/gates.mjs explainers/<slug>` re-judges the render
still in `out/`, which only a green render leaves (a red render empties
`out/`, so render again, which reuses the cached video), and deletes nothing.
Each prints `gate <name>: pass|fail: <measured> vs <floor>`:

- `layout`: HyperFrames' check, plus the layout probe (text at least 18 px,
  nothing clipped or overflowing its box, every text box inside the 5 percent
  safe margin, no text box overlapping another), on frames every 15 frames
  and on each scene's settled last frame. In an Arabic run, the probe also holds
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
- `loudness`: -14 LUFS plus or minus 1 and a true peak at most -1 dBTP,
  measured on the encoded MP4.
- `captions`: every word timed in order inside its scene, every cue non-empty,
  in order, at most 84 characters and inside the video, and the SRT equal to
  the burned-in cues.
- `sfx`: at most 24 sound effects in any minute of `score.json`.
- `critic`: the **critic**, Claude subagents reading one **contact sheet** per
  scene (four of its frames, cut from the MP4 by ffmpeg), fails on any hard
  failure: `unreadable` or `invented` content. Its scores (clarity,
  legibility, fit, 1 to 5) only advise: the line shows their means, and
  `gates.md` lists them per scene. Until the critic has judged this render the
  gate reads `gate critic: pending: round <r> of 2, ..., contact sheets in
  <sheets>`.

A summary line follows, `gates: <n> pass, <m> fail[, 1 pending]`, ending on a
red run with `next: fix attempt <a> of 2` or `stop: red after two fix
attempts, no video`, and when the critic alone holds the video with `next: run
the critic, round <r> of 2`. Layout and contrast results are cached per scene
by everything that draws it, so a fix re-gates only the scenes it touched;
loudness, captions and sfx run every time. The stage writes `gates.json`, the
machine record, and `gates.md`, the readable report with every red gate's
findings and the critic's scores.

## The critic round

Run it when the summary ends `next: run the critic`; a pending critic beside a
red gate waits for that gate's fix, so no round is spent on a render the fix
replaces.

1. Dispatch one subagent per scene whose `<run>/<sheets>/<scene>.png` has
   no `<scene>.json` beside it (`<sheets>` is relative to the run folder,
   `<run>`), all in one turn, each with
   `<skill>/agents/critic.md` as its prompt, `{run}` the run folder, `{scene}`
   the scene id and `{sheets}` the folder the pending line names. Each writes
   its verdict and replies with one `critic <scene>:` line. Never read a sheet
   or a verdict here.
2. Render again: the video is cached, so this only judges it.
3. On `gates: critic verdict <scene>.json: <why>`, send the line to that
   scene's critic to fix, then render again.

The critic judges two renders of one script at most, a render counting anew
when only its cites or a cited excerpt's text changed. A hard failure in the
second round is final, so the summary ends `stop: the critic's second round is
red, no video`. A third render carries the second round's verdict, its line
ending `carried: no third round`; new narration is a new script and starts at
round 1.

## On a red gate

Relay its line and fix what its findings name **inside the script**: the
visual's layout, its text size, colours within the profile, timing, or
re-voiced audio, never the narration, the scene order or the scene count. A
critic's `invented` finding is fixed in the visual: show what the narration
and its excerpts say. Compile, voice if the audio changed, and render again.
The attempt counts live in `gates.json`: each gate's count resets when that
gate passes, and the run's count, which `stop` reads, when every gate passes.
Both reset when the narration changes, so a red that moves from one gate to
another still stops. On `stop`, stop with no video and run Storyboard step 7.

## Floors

Floors are set in the skill. A profile's optional `gates` block may only
tighten them, and the tightened value is the one applied and printed:
`contrast` (`body`, `large`, raise), `layout` (`textPx`, `margin` as a
fraction, raise), `loudness` (`tolerance` in LU, above 0, and `peak` in
dBTP, no lower than -8.5, lower), `sfx` (`perMinute`, lower). The critic has
no floor to tighten.
