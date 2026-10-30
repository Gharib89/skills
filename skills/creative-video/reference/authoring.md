# Authoring and render

## Contents

- [The run folder](#the-run-folder)
- [Timing](#timing)
- [Chapters](#chapters)
- [Scenes on word times](#scenes-on-word-times)
- [Sound](#sound)
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
  pick (the person's on the storyboard, or yours and why on an unattended run).
- `unattended.json` (unattended runs): `{ "direction": "<id>" }`, the render's
  stand-in for the board's approval
  ([storyboard.md](storyboard.md#the-render-holds-to-the-approval)).
- `storyboard.json` and `directions/<id>.html` (attended runs): what the
  storyboard shows beyond the scenes, and a frame of each direction not picked
  ([storyboard.md](storyboard.md) step 1). The storyboard itself, `board/`, is
  rebuilt by `board.mjs`.
- `SPEC.md`: the stance's numbers, and one reason line per `hyperframes`
  banned default the concept uses.
- `brand.json` and `brand/` (with a brand): [brand.md](brand.md).
- `script.json`: the narration, scene by scene, each sentence's `cites`
  beside it ([voice.md](voice.md) holds its shape and the spoken-form rules).
  A scene is a stretch of narration that one
  composition stages; the picture changes inside it on words, so a scene runs
  as long as its idea, not a fixed length. Its `id` is a file name, an element
  id and a timeline key: lower-case letters, digits and hyphens, and none of
  `main`, `captions`, `over` or `narration`.
- `project/kit/`: the format kit, before the first scene: `*.css` (the palette
  as custom properties, the faces with their `@font-face` rules, sizes) and
  `*.js` (the recurring devices every scene shares). The root loads every file
  there, sorted by name, so a scene uses the kit without importing it.
- `project/kit/cast.json` (optional): the voice of each role the script
  names in `roles` ([voice.md](voice.md) holds its shape). Without it the
  video has one voice.
- `project/kit/sound.json`: the bed and the sound palette, each sound's
  licence filled in by the sound stage ([Sound](#sound)).
- `project/compositions/<id>.html`: one scene file per `script.json` scene,
  by its `id`.
- `project/compositions/over.html` (optional): one composition across the
  whole video, over the scenes, for what crosses a cut: a score that stays on
  screen, a host who never leaves, a sound that runs on. In a video in
  chapters it holds sound only: a chapter renders without it, and its sound
  plays in the one mix of the whole video.
- `project/assets/`: your media (recorded sounds, images, fonts).
- `CREDITS.md` and `DELIVERY.md`, after the render (`render/credits.mjs`
  writes `CREDITS.md`'s `## Voices` and `## Sound`).

`support.json` is the support checker's own to write and fix.
`claims.json` (the claims check) keeps the fix attempts and each sentence's
first verdict across runs: never delete it, or the fix count starts again.

What the stages write, rebuilt on every run: `voice.json` and `.cache/` (voice),
`timeline.json`, `project/index.html`, `project/timing.js`,
`project/compositions/captions.html`, `project/assets/narration.wav` and
`project/assets/gsap.min.js` (timing), `project/assets/sounds/` (sounds),
`project/.hyperframes/` (the CLI's
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
`timing.js` and the caption track. In a video of two or more roles, a cue
whose role differs from the last cue's opens with the role's name
(`Learner: `), in the video and the SRT alike. In an Arabic run the captions
read right to left in IBM Plex Sans Arabic, each run of Latin words kept in
order on one line. It prints `timing: <n>
scene(s), <total> s` and one `timing: compositions/<id>.html to author` line
per scene file not yet written. On exit 1, `timing: <why>` names what to fix:
a `voice.json` that no longer matches `script.json` means voice again first.

## Chapters

A video past about six minutes is in chapters of two to six minutes each. The
**chapter plan** is `script.json`'s `chapters`, written with the whole script
before any scene:

```json
"chapters": [
  {"title": "Why it stops", "focus": "the one line the chapter teaches",
   "scenes": ["hook", "stop-sign"]}
]
```

Every scene sits in one chapter, the chapters in scene order. Timing refuses a
brief longer than six minutes with no plan, a scene in no chapter or in two,
a chapter longer than about six minutes, as voiced (a lone chapter included),
and, with two chapters or more, one shorter than about two. It writes each
chapter's start and end into `timeline.json`.

A chapter opens on a hard cut into a scene you author freely, whose very first
frame draws the chapter's title in full: the delivered video's chapter mark
lands on that frame, and the `chapter titles` gate fails a title not drawn
there. Sound may cross a cut (the bed, a sound in `over.html`); no visual
transition does. The kit is loaded by every chapter, so a device that recurs
lives there, never copied into a scene.

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

`at(scene, word, nth)` is the scene-local start of the `nth` word of that
scene that reads as `word`, compared without case or punctuation. Give `nth`
whenever the scene says the word more than once, counted the same way (`You`
and `you.` are one word): `at()` with no `nth` on a repeated word throws each
occurrence's scene-local start, so you pick the one you mean
(`at("kitchen", "send", 2)`). A word the narration no longer holds throws,
so a rewritten line breaks its anchors where you see it, not as drift in the
render. Never type a time a word already gives; offsets from an anchor
(`- 0.1`, an event 0.5 s after a word) are yours.
`window.TIMING.scenes[<id>].duration` is the scene's length, for an event that
lands on its end.

A sound that answers a word is an `<audio>` the scene script creates, since a
`data-start` written in the HTML is a typed time, and only `at()` in the script
gives a word's time:

```js
const ding = document.createElement("audio");
ding.id = "kitchen-ding";
ding.src = "assets/sounds/bell-1.mp3"; // its sound.json `file`
ding.dataset.start = window.TIMING.scenes["kitchen"].start + at("kitchen", "ticket");
ding.dataset.duration = 0.4;
document.querySelector('[data-composition-id="kitchen"]').append(ding);
```

The render plays a created `<audio>` at its `data-start` in seconds of the
whole video, so add the scene's start (`TIMING.scenes[<id>].start`) to the
word's time; one outside its scene is refused. Give each sound an id no other
`<audio>` in the project has: the render never plays a created one with no id
or a taken id, and refuses a written one with no id. An `<audio>`
written in the HTML keeps the `data-start` written there, in scene seconds,
whatever the script sets later, so the `sounds` gate refuses a script that
moves one. Create an `<audio>` in the scene's own script or in a kit `*.js`
device the scene calls: the render mixes a sound either one creates.

Readable text stays out of the caption band, the bottom 220 px: paint behind
it, never write in it.

In an Arabic run, set the scene's text in a box marked `dir="rtl"`, each Latin
term or number among Arabic words in a `<bdi>` with `white-space: nowrap`, at a
line height no lower than the ink the face's letters span; the `layout` gate
measures each. Mark a code frame or a terminal `dir="ltr"`: the gate leaves
such a frame as written. Keep each Arabic word in one box: a letter in a box of
its own (an `inline-block` span per character, as letter-by-letter animation
makes) is drawn unjoined, and the `joins` gate fails it. Animate a word, a line
or a clip mask, never its letters.

## Sound

Write `project/kit/sound.json` with the kit, before any scene:

```json
{
  "bed": {"query": "kitchen ambience", "level": -28, "out": ["hardest-step"]},
  "palette": [{"event": "ticket", "query": "bell ding"}]
}
```

`bed` is the low sound under the whole video: `query` the words to search
for, `level` its gain in dB, `out` the ids of the scenes it drops out for. Each
`palette` entry is one sound and the story event it marks. Then:

```
node <skill>/scripts/sound/sounds.mjs <run>
```

For each sound it searches Openverse for CC0 audio (a search that fails after
30 s is tried once more, a failed download counts as no result) and takes the
first result that is not speech (a pronunciation, a podcast, an audiobook) and
whose title and tags hold every word of the query, then the Kenney packs setup
installs (`sounds:kenney`): it picks the file whose name and word-index words
hold the most of the query's words. Word each query as the sound's own name,
the two or three words a clip's title or tags carry (`bell ding`, `radio
squelch`): Openverse passes over every result that lacks any one word. The
packs hold UI, casino, RPG, sci-fi and synth effects and short music stings; a
bed comes only from the one stem whose loop seam measures clean, the sci-fi
large space engine, so a bed query needs engine, space or spaceship. It copies
what it finds into `project/assets/sounds/` and writes the sound's `file`,
`source`, `licence`, `creator`, `url` and `attribution` into `sound.json`. A
sound its query found before, on any run, is copied again with no search. It
prints `sound <event>: openverse <id> | kenney <pack>/<file> | cached |
dropped: <why>` per sound. A sound found nowhere moves to `sound.json`'s
`dropped` list with its reason, and prints `warn dropped sound: <event>:
<why>`. To swap a found sound, change its `query` and run again. To retry a
dropped one, put it back under `bed` or `palette` with its `query`, or a new
one, and run again: this run's outcome replaces its `dropped` entry. Or stage
the moment without it. Never edit the fields it writes.

The root plays the bed: every stage that writes `index.html` adds it after the
narration as `<audio id="bed">`, looped over the whole video at its `level`,
with a volume lane (`data-automation`) that ducks it to 0.35 while words play
and silences it across each `out` scene, each change a 0.2 s ramp. A palette
sound plays where a scene places it, by its `file`
([Scenes on word times](#scenes-on-word-times)).

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

The gates stage, what each gate judges and how a failure is fixed are in
[gates.md](gates.md).

## Render

```
node <skill>/scripts/render/render.mjs <run>
```

It refuses unless the storyboard approved the look
([storyboard.md](storyboard.md#the-render-holds-to-the-approval)), or
`unattended.json` records an unattended run's direction, and unless
`gates.json` shows every gate passing for the project as it stands. It prints
`render: unattended run, no approval: direction <id>` for an unattended run,
and `render: changed after board <n>'s approval: <what>` (its scenes, then
`the kit`, `over.html` and `assets/<file>`) when something the approved board
showed changed since. It renders the project, normalises the mix to -14 LUFS
with a true peak ceiling of -1.5 dBTP, and writes `out/<slug>.mp4` (captions
drawn in), `out/<slug>.srt` and `out/poster.png`.
It prints one `delivery <check>: pass` or
`delivery <check>: fail: <measured> vs <wanted>` line per check
(`resolution`, `frame rate`, `aspect`, `duration`, `audio`, `captions` (the
video's caption cues against the timeline's words and the SRT), `loudness`
within 1 LU, `true peak` at most -1 dBTP), a `measured loudness:` line with
both values, `delivered: <path of out/<slug>.mp4>`, then
`render: <slug>.mp4 <seconds> s, <n> scene(s)`.

A video in chapters renders each chapter on its own, one at a time, video
only, and keeps each chapter video under `.cache/render/` by everything that
chapter loads: its scenes, captions, the kit and the assets its files name by
path (`assets/<file>`). A later render renders only the chapters whose video
changed, so a fix to one scene costs one chapter, a new or changed asset the
chapters that name it, and a change to the kit costs them all. Name an asset by
its path in the file that uses it: one no file names (a name a script builds
at run time) counts for every chapter. `over.html` is no
chapter's input: a change to it changes only the mix. The narration and every
sound are mixed once over the whole video, the chapter videos joined by stream
copy at the hard cuts, and the audio encoded once with a chapter mark at each
chapter's first frame; a `delivery chapters` line checks the marks. Before it
renders it prints `render: <k> of <n> chapter(s) to render, estimate <m:ss>,
budget <m:ss>`, the estimate from `render-rates.json`, the budget 5 minutes a
video minute; `--estimate` prints that line and renders nothing.

On exit 1 nothing new is
delivered: a `render: <why>` refusal (a missing scene file, a timing older
than the voice: run timing again) leaves `out/` as it was, and a failed
render or `delivery` check empties it.
