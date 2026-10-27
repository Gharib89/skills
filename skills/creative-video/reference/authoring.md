# Authoring and render

## Contents

- [The run folder](#the-run-folder)
- [Timing](#timing)
- [Scenes on word times](#scenes-on-word-times)
- [The pinned CLI](#the-pinned-cli)
- [Render](#render)

`<skill>` below is this skill's folder, `<run>` the run folder
`creative-videos/<slug>` in the current repo.

## The run folder

What you write, all committed as the video's recipe:

- `brief.json`: `{ "length": <minutes> }`, read by the voice stage's length
  check.
- `DIRECTIONS.md`: the three directions, the recommended one and why, and the
  pick (the person's, or yours and why on an unattended run).
- `SPEC.md`: the stance's numbers, and one reason line per `hyperframes`
  banned default the concept uses.
- `script.json`: the narration, scene by scene ([voice.md](voice.md) holds its
  shape and the spoken-form rules). A scene is a stretch of narration that one
  composition stages; the picture changes inside it on words, so a scene runs
  as long as its idea, not a fixed length.
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
`project/assets/gsap.min.js` (timing), and `out/` (render). Never edit these by
hand: the next timing run overwrites them.

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
`snapshot --review` for the contact sheets, `snapshot --at <t>` or
`--range <a>,<b>` to look at what you changed, `timeline --json`. Exit codes
and output are HyperFrames' own.

## Render

```
node <skill>/scripts/render/render.mjs <run>
```

It renders the project, normalises the mix to -14 LUFS with a true peak
ceiling of -1.5 dBTP, and writes `out/<slug>.mp4` (captions drawn in),
`out/<slug>.srt` and `out/poster.png`. It prints one `delivery <check>: pass`
or `delivery <check>: fail: <measured> vs <wanted>` line per check
(`resolution`, `frame rate`, `aspect`, `duration`, `audio`, `srt`,
`true peak`), a `delivery loudness:` line with what it measured, then
`delivered: <path of out/<slug>.mp4>`. On exit 1 nothing is delivered and
`out/` is empty:
a `render: <why>` line names the cause (a missing scene file, a timing older
than the voice: run timing again), a failed `delivery` line the check.
