# Authoring and render

## Contents

- [The run folder](#the-run-folder)
- [Timing](#timing)
- [Scenes on word times](#scenes-on-word-times)
- [The pinned CLI](#the-pinned-cli)
- [Gates](#gates)
- [Render](#render)

`<skill>` below is this skill's folder, `<run>` the run folder
`creative-videos/<slug>` in the current repo.

## The run folder

What you write, all committed as the video's recipe:

- `brief.json`: `{ "length": <minutes> }`, read by the voice stage's length
  check, and optionally `"must"` and `"avoid"`, lists of words the gates'
  `must and avoid` check reads.
- `DIRECTIONS.md`: the three directions, the recommended one and why, and the
  pick (the person's, or yours and why on an unattended run).
- `SPEC.md`: the stance's numbers, and one reason line per `hyperframes`
  banned default the concept uses.
- `script.json`: the narration, scene by scene ([voice.md](voice.md) holds its
  shape and the spoken-form rules). A scene is a stretch of narration that one
  composition stages; the picture changes inside it on words, so a scene runs
  as long as its idea, not a fixed length. Its `id` is a file name, an element
  id and a timeline key: lower-case letters, digits and hyphens, and none of
  `main`, `captions`, `over` or `narration`.
- `project/kit/`: the format kit, before the first scene: `*.css` (the palette
  as custom properties, the faces with their `@font-face` rules, sizes) and
  `*.js` (the recurring devices every scene shares). The root loads every file
  there, sorted by name, so a scene uses the kit without importing it.
- `project/compositions/<id>.html`: one scene file per `script.json` scene,
  by its `id`.
- `project/compositions/over.html` (optional): one composition across the
  whole video, over the scenes, for what crosses a cut: the bed, a score that
  stays on screen, a host who never leaves.
- `project/assets/`: your media (recorded sounds, images, fonts).
- `CREDITS.md` and `DELIVERY.md`, after the render.

What the stages write, rebuilt on every run: `voice.json` and `.cache/` (voice),
`timeline.json`, `project/index.html`, `project/timing.js`,
`project/compositions/captions.html`, `project/assets/narration.wav` and
`project/assets/gsap.min.js` (timing), `project/.hyperframes/` (the CLI's
snapshots), `gates.json` (gates), and `out/` (render). Never edit these by
hand: the next run of their stage overwrites them. `hf.mjs` and the render
write `index.html` again before they run, so an `over.html` or a kit file added
after timing is in the root they use.

## Timing

After the voice stage passes, and again after every re-voice:

```
node <skill>/scripts/render/timing.mjs <run>
```

It lays the scenes back to back on the 30 fps frame grid from their voiced
lengths, the last one held 1 s, and writes the root `index.html` (each scene's
host at its start and length, the narration, the captions on top),
`timing.js` and the caption track. It prints `timing: <n> scene(s), <total> s`
and one `timing: compositions/<id>.html to author` line per scene file not yet
written. On exit 1, `timing: <why>` names what to fix: a `voice.json` that no
longer matches `script.json` means voice again first.

## Scenes on word times

Every scene file is a HyperFrames scene (`<template>`, `#root`, one paused
timeline registered as `window.__timelines["<id>"]`, its id the scene's), with
the `hyperframes` skill's contract. Its clock starts at 0 at the scene's
start. Place every event that answers a word at that word's time from
`window.at`:

```js
const tl = gsap.timeline({ paused: true });
tl.fromTo("#kitchen-pass", { y: 40, opacity: 0 }, { y: 0, opacity: 1, duration: 0.3 }, at("kitchen", "ticket"));
tl.to("#kitchen-rookie", { x: 120, duration: 0.4 }, at("kitchen", "send", 2) - 0.1);
window.__timelines["kitchen"] = tl;
```

`at(scene, word, nth = 1)` is the scene-local start of the `nth` word of that
scene that reads as `word`, compared without case or punctuation. A word the
narration no longer holds throws, so a rewritten line breaks its anchors where
you see it, not as drift in the render. Never type a time a word already
gives; offsets from an anchor (`- 0.1`, an event 0.5 s after a word) are
yours. `window.TIMING.scenes[<id>].duration` is the scene's length, for an
event that lands on its end.

Readable text stays out of the caption band, the bottom 220 px: paint behind
it, never write in it.

## The pinned CLI

Run every HyperFrames command through this skill's pinned copy, never
`npx hyperframes`, which fetches whatever version npm has today:

```
node <skill>/scripts/hf.mjs <run> <command> [args]
```

It runs in `<run>/project` with the tool cache's Chrome. The commands you need:
`check --json` after your last edit (fix every error, weigh every warning),
`snapshot --review --json` for the contact sheets (its `review.sheets` lists
their paths), `snapshot --at <t>` or `--range <a>,<b>` to look at what you
changed, `timeline --json`. `--at` and `--range` take seconds of the whole
video, not a scene's: `timeline.json` holds each scene's `start` and the
absolute word times, or use `--composition <id>` for one scene. Exit codes and
output are HyperFrames' own.

## Gates

```
node <skill>/scripts/gates/gates.mjs <run>
```

After the stills review. It judges what the project renders and what the
narration says, never the scene code, and writes `gates.json`. It samples each
scene 0.3 s in, at its middle and on its last frame, and prints one `gate
<name>: pass|fail: <measured> vs <floor>` line per gate, the findings of a
failing one indented under it. Each is a hard fail:

- `determinism`: the same frames in two separate launches. A clock or a random
  draw in a scene makes them differ.
- `layout`: no HyperFrames layout error, and no clipped or overlapping text in
  any one sample frame (HyperFrames grades those info, the gate fails them), no
  readable text under 18 px or outside a margin of 5% of each side.
- `contrast`: WCAG AA, 4.5:1, 3:1 for large text.
- `reading`: each text stays fully visible for 0.8 s up to 3 words, else 0.3 s
  a word and at least 1.2 s.
- `caption band`: no readable text in the bottom 220 px, the captions' own.
- `anchors`: every `at(scene, word)` names a word the narration holds.
- `script errors`: no scene's script throws (an error HyperFrames reports from
  running it, other than an anchor), each named `<scene>: <message>`, and
  every scene registers its timeline (one missing means its script stopped).
- `must and avoid`: every `must` word of `brief.json` is said or shown, no
  `avoid` word is: said in the voiced narration (not `script.json`, which can
  change after the voice), shown fully drawn in a sample frame.

Warnings print as `warn <name>: <detail>`, are recorded in `gates.json` and
never change the exit: `effect rate` (over 24 sounds in a minute), `effect
onset` (a sound over 0.15 s from the nearest tween start), `scene length`
(over 30 s), `sentences` (over 25 words), `pacing` (always printed: the change
events a minute, and each dead stretch of 2 s or more with no tween running)
and `clock` (a scene or kit file naming `Math.random`, `Date.now`, `new Date`,
`performance.now`, `setTimeout`, `setInterval` or `requestAnimationFrame`).

The last line is `gates: <p> pass, <f> fail`. Each red run after a change to
the project is one fix attempt; a re-run with nothing changed counts none. The
first two red runs end `; next: fix attempt <n> of 2`, the third `; stop: red
after two fix attempts, no video`. Stop there and report the findings. A pass,
or a new voice (the narration voiced and timed again), starts the count again;
`script.json` edited without voicing again does not. Gates judge the project
as it is: change a scene, the kit or an asset after a pass and the render
refuses until they pass again.

Exit 1 with a `gates: <why>` line on stderr and no gate lines is a refusal (no
timeline, a timing older than the voice, a missing scene file, a `gates.json`
or `brief.json` that is malformed). Fix what it names and run again; it is not
a fix attempt and not a red gate.

## Render

```
node <skill>/scripts/render/render.mjs <run>
```

It refuses unless `gates.json` shows every gate passing for the project as it
stands. It renders the project, normalises the mix to -14 LUFS with a true peak
ceiling of -1.5 dBTP, and writes `out/<slug>.mp4` (captions drawn in),
`out/<slug>.srt` and `out/poster.png`. It prints one `delivery <check>: pass`
or `delivery <check>: fail: <measured> vs <wanted>` line per check
(`resolution`, `frame rate`, `aspect`, `duration`, `audio`,
`captions` (the video's caption cues against the timeline's words and the
SRT), `loudness` within 1 LU, `true peak` at most -1 dBTP), a `measured
loudness:` line with both values, `delivered: <path of out/<slug>.mp4>`, then
`render: <slug>.mp4 <seconds> s, <n> scene(s)`. On exit 1 nothing new is
delivered: a `render: <why>` refusal (a missing scene file, a timing older
than the voice: run timing again) leaves `out/` as it was, and a failed
render or `delivery` check empties it.
