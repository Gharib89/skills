# Recipes

## Contents

- [Motion rule](#motion-rule)
- [The five directions](#the-five-directions)
- [Writing a custom scene](#writing-a-custom-scene)
- [Seek-safe moves](#seek-safe-moves)
- [Moves to borrow](#moves-to-borrow)

Read this before you write a `custom` scene or reach for a rich component. A
component covers a picture the house already draws; a `custom` scene is for one
it does not, so check the component list in
[scene-file.md](scene-file.md) first.

## Motion rule

- A UI state change (a line checking, a badge flipping, a row closing) runs at
  most about 250 ms. To make a result land harder, hold it on screen longer;
  never slow the move.
- One element moves at a time. A second move starts when the first has
  settled, or sits on its own cue.
- Only an entrance or an emphasis takes 400 to 500 ms: a thing arriving for the
  first time, or the one thing the sentence points at.
- Every move starts on a cue, a sentence or a phrase of it, never on a guess
  at seconds.

## The five directions

A scene leans on one direction; name it in `intent`.

| Direction | What the viewer reads | Covered by |
| --- | --- | --- |
| Type | words arriving with the voice | `title`, `words` |
| Data | a number earned, compared or moved | `chart`, `stat`, `timeline`, `compare` |
| System | parts and what flows between them | `diagram`, `flow` |
| Interface | a tool at work: lines, cards, diffs | `terminal`, `cards`, `panels`, `list`, `code`, `codediff` |
| Camera | attention steered to one place | the push-in, `emphasis` |

Techniques, ranked by how often the house wants them (try the first before the
next):

1. **Rise and fade in**: 20 px up, 350 to 450 ms, `power2.out`. The default
   entrance.
2. **Hold, then replace**: the old thing leaves in 150 to 250 ms, the new one
   enters at once. Cheaper and clearer than a cross-fade.
3. **Count up**: 0.6 to 0.9 s, `power2.out`, ending on the text as written.
4. **Ring on one target**: an accent ring grows in 400 ms, `power2.out`, and
   stays.
5. **Stroke on**: an arrow or line draws over 400 to 500 ms, `power1.inOut`.
6. **Punch in**: scale the content 1.0 to 1.06 over 0.6 to 0.8 s, `power2.out`,
   ending on the cue's word.

## Writing a custom scene

The scene file names the fragment, `{ "component": "custom", "props": { "file":
"scenes/<id>.html", "intent": "<one line>", "cues": [ { "name": "land", "at": 1,
"on": "request" } ] } }`, and the file sits beside `script.md`. A fragment is
markup, one `<style>` of plain rules, and one `<script>`:

- **Colour and size come from tokens.** Colours: `var(--accent)`, `--text`,
  `--muted`, `--faint`, `--bg`, `--panel`, `--chip`, `--line`, `--rule`, `--ok`,
  `--warn`, `--stop`. Text sizes: `var(--size-display)`, `--size-title`,
  `--size-heading`, `--size-body`, `--size-code`, `--size-small`,
  `--size-label`. Faces: `var(--font-title)`, `--font-text`, `--font-code`.
  A hex, an `rgb()`, a colour name or a pixel `font-size` is refused at
  compile.
- **The script is `(tl, cue, $, duration)`.** `tl` is the scene's paused
  timeline; `cue("land")` is the named cue's time in seconds, and a name the
  scene does not declare is refused; `$(".a")` is a selector scoped to the
  scene; `duration` is the scene's length.
- **Rules are plain**: one selector list and one block each. No `@` rules, no
  nesting, no `@keyframes`.
- **Stand alone.** No `<script src>`. A catalog block that needs a library gets
  the library's local copy pasted into the fragment.
- **Show text.** A scene that shows none at any sample is a hard error, since
  captions do not count.
- **No camera key**, and moving `$()` (the whole content) counts as a camera: a
  profile that bans `camera` refuses it, as it refuses `blur`, `draw` and
  `kinetic` techniques it finds in the fragment.
- **Arabic**: no per-letter span or `.split("")` of Arabic text, which breaks
  the joined letters. Move a word or a line.
- **Edit, then compile again**: the fragment is read at compile, so a changed
  file plays only after the next compile.

## Seek-safe moves

A frame is a function of the timeline's time, so the renderer can seek to any
frame. Keep every move on `tl`.

- No `Date.now`, `Math.random`, `performance.now`, `setTimeout`,
  `setInterval`, `requestAnimationFrame` or `gsap.ticker`: each is refused.
- No CSS `animation`, `transition` or `@keyframes`, no `.animate()`, no SVG
  animate element.
- Set a start state with `tl.set(...)` or the `from` side of `tl.fromTo(...)`,
  never by script that runs once.
- A counter is a tween of a plain object whose `onUpdate` writes the text:
  `const o = { v: 0 }; tl.to(o, { v: 42, duration: 0.8, ease: "power2.out",
  onUpdate: () => { el.textContent = Math.round(o.v); } }, cue("count"));`.
- A repeat is a finite `repeat` count worked out from `duration`, never `-1`.
- Two moves on one element never overlap in time.

## Moves to borrow

Each move below is a shape worth reusing, described and timed here in the
house's own terms. Build each in a `custom` scene, with its parts on named
cues.

**Tool calls ticking by (interface).** A terminal task is typed on a cue. Each
tool call is one line that lands in 200 ms and checks in 150 ms; the next line
starts after the check. A summary line follows the last call, then one `done`
line in `var(--ok)`. Hold the done line for the rest of the sentence.

**A diff card that counts (interface).** A card with a file name, an added
count and a removed count. Both counts run up from 0 over 0.8 s together, the
added in `var(--ok)` and the removed in `var(--stop)`. When both have settled, a
`merged` badge lands in 250 ms. The badge is the only thing that moves then.

**A score jump (data).** The old number sits left, an arrow strokes on in
400 ms, the new number rises in on the right. The delta, with its sign, counts
up under the new number over 0.6 s. Keep the old number on screen: the jump
reads only against it.

**A checklist collapsing (interface).** Each item checks in 150 ms on its own
cue. When the last has checked, the rows close upward in 250 ms, one after the
other from the top, into a single line that reads the result (`6 of 6 pass`).

**A fan-out (system).** One row, then the parallel rows appear below it, each
entering in 350 ms with a gap of 100 ms. Each row streams a short status line
and ticks done on its own cue, in no fixed order. When the last has ticked, a
merged summary row lands in 450 ms, the emphasis of the scene.

**A punch-in with a ring (camera).** Scale the content to 1.06 over 0.7 s ending
on the phrase's first word, and grow an accent ring round one target in 400 ms
as the scale settles. Move one or the other at a time, never both from the
same start. Hold the ring to the scene's end.
