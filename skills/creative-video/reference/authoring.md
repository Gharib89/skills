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
- `storyboard.json` and `directions/<id>.html` (attended runs): what the
  storyboard shows beyond the scenes, and a frame of each direction not picked
  ([storyboard.md](storyboard.md) step 1). The storyboard itself, `board/`, is
  rebuilt by `board.mjs`.
- `SPEC.md`: the stance's numbers, and one reason line per `hyperframes`
  banned default the concept uses.
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
read right to left in IBM Plex Sans Arabic, which it copies from the font
store, each run of Latin words kept in order on one line. It prints `timing: <n>
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

`at(scene, word, nth = 1)` is the scene-local start of the `nth` word of that
scene that reads as `word`, compared without case or punctuation. A word the
narration no longer holds throws, so a rewritten line breaks its anchors where
you see it, not as drift in the render. Never type a time a word already
gives; offsets from an anchor (`- 0.1`, an event 0.5 s after a word) are
yours. `window.TIMING.scenes[<id>].duration` is the scene's length, for an
event that lands on its end.

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
moves one.

Readable text stays out of the caption band, the bottom 220 px: paint behind
it, never write in it.

In an Arabic run, set the scene's text in a box marked `dir="rtl"`, each Latin
term or number among Arabic words in a `<bdi>` with `white-space: nowrap`, at a
line height no lower than the ink the face's letters span (the `layout` gate
measures it); mark a code frame or a terminal `dir="ltr"`. Keep each Arabic
word in one box: a letter in a box of its own (an `inline-block` span per
character, as letter-by-letter animation makes) is drawn unjoined, and the
`joins` gate fails it. Animate a word, a line or a clip mask, never its
letters.

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
30 s is tried once more, a failed download counts as no result), then the
Kenney packs setup installs (`sounds:kenney`) by their file names' words,
copies what it finds into `project/assets/sounds/` and writes the sound's
`file`, `source`, `licence`, `creator`, `url` and `attribution` into
`sound.json`. A sound its query found before, on any run, is copied again with
no search. It prints `sound <event>:
openverse <id> | kenney <pack>/<file> | cached | dropped: <why>` per sound. A
sound found nowhere moves to `sound.json`'s `dropped` list with its reason, and
prints `warn dropped sound: <event>: <why>`. To swap a found sound, change its
`query` and run again. To retry a dropped one, put it back under `bed` or
`palette` with its `query`, or a new one, and run again: this run's outcome
replaces its `dropped` entry. Or stage the moment without it. Never edit the
fields it writes.

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

```
node <skill>/scripts/gates/gates.mjs <run>
```

After the stills review. It judges what the project renders and what the
narration says, never the scene code (but for the `<audio>` starts a scene
file writes, which `sounds` reads), and writes `gates.json`. It samples each
scene 0.3 s in, at its middle and on its last frame, and prints one `gate
<name>: pass|fail: <measured> vs <floor>` line per gate, the findings of a
failing one indented under it. Each is a hard fail:

- `determinism`: the same frames in two separate launches. A clock or a random
  draw in a scene makes them differ.
- `layout`: no HyperFrames layout error, and no clipped or overlapping text in
  any one sample frame (HyperFrames grades those info, the gate fails them), no
  readable text under 18 px or outside a margin of 5% of each side. In an
  Arabic run, also the Arabic reading rules of
  [Scenes on word times](#scenes-on-word-times).
- `contrast`: WCAG AA, 4.5:1, 3:1 for large text.
- `reading`: each text stays fully visible for 0.8 s up to 3 words, else 0.3 s
  a word and at least 1.2 s.
- `caption band`: no readable text in the bottom 220 px, the captions' own.
- `anchors`: every `at(scene, word)` names a word the narration holds.
- `script errors`: no scene's script throws (an error HyperFrames reports from
  running it, other than an anchor), each named `<scene>: <message>`, and
  every scene registers its timeline (one missing means its script stopped).
- `sounds`: every `<audio>` plays at its live `data-start`, in its scene: one
  written in the HTML keeps the `data-start` written there (a script that
  moves it is refused, since the render reads the HTML's), and a created one
  starts inside its scene in seconds of the whole video. Every one needs an id
  (the render refuses a written one without, never plays a created one
  without), and a created one an id no other `<audio>` has (the render never
  plays it otherwise).
  See [Scenes on word times](#scenes-on-word-times).
- `licence`: every `<audio>` but the narration, in a scene, `over.html` or the
  root, plays a `file` that `sound.json` gives a licence ([Sound](#sound)).
- `bed level`: the bed at least 15 LU under the voice in each 3 s window that
  holds a word, by short-term loudness, its level and lane applied. It names
  each window under 15 LU, and passes as `no bed` without one.
- `joins` (an Arabic run): each Arabic word split across boxes, shaped piece
  by piece in the face Chrome draws it in, matches the word shaped whole.
- `must and avoid`: every `must` word of `brief.json` is said or shown, no
  `avoid` word is: said in the voiced narration (not `script.json`, which can
  change after the voice), shown fully drawn in a sample frame.
- `support`: the claims check (`source/claims.mjs`) passed on `script.json`'s
  sentences and cites and the excerpts they cite as they stand. Edit a
  sentence or a cite, or pack the sources again, and it fails until the
  support checker and the claims check run again. A sentence edited after
  voicing fails it too (`scene <id>'s narration is not what voice.json voiced`)
  until the voice stage runs again, since the render speaks the voiced words.
- `critic`: no hard failure in any scene's sample stills, judged by one
  subagent per scene (`agents/critic.md`) that describes each still as a
  stranger would, then names what blocks: `unreadable` text, an `invented`
  fact on screen (one no narration sentence or cited excerpt states, or one
  they contradict; staging such as props, signs, scores and round numbers
  never is) and `rtl` (Arabic laid out the wrong way round). It gives no
  scores. It also checks what `joins` measures but cannot judge.
- `chapter titles` (a video in chapters): every word of each chapter's title
  is drawn on that chapter's first frame.
- `sound only` (a video in chapters): `over.html` holds `<audio>` and draws no
  element, since a chapter renders without it.

Warnings print as `warn <name>: <detail>`, are recorded in `gates.json` and
never change the exit: `effect rate` (over 24 sounds in a minute), `effect
onset` (a sound over 0.15 s from the nearest tween start), `scene length`
(over 30 s), `sentences` (over 25 words), `alike voices` (two roles with the
same voice in the script's language, counting only roles some sentence
speaks, the narrator role whether `cast.json` casts it or not, and on Gemini,
which acts the style line, the same style line too), `dropped sound` (a sound
`sounds.mjs` found nowhere), `pacing` (always printed: the change events a
minute, and each dead stretch of 2 s or more with no tween running) and
`clock` (a scene or kit file naming `Math.random`, `Date.now`, `new Date`,
`performance.now`, `setTimeout`, `setInterval` or `requestAnimationFrame`).

The critic runs on the stills of the gates' own render. While a scene has no
verdict, its line reads `gate critic: pending: round <r> of 2, <k> of <n>
scene(s) judged, stills in <dir>` and the exit is 1. Fix the failing gates
first; once none fails, the last line ends `; next: run the critic, round <r>
of 2`: dispatch the critics on `<dir>`, relative to the run folder (SKILL.md
step 12), then run the
gates again. A scene whose stills, and the narration and
excerpts every critic reads, are unchanged keeps its last verdict, so only a
changed scene is judged again. The critic has two rounds per voice: a red
second round is final, `; stop: the critic's second round is red, no video`,
and a later gates run past two rounds carries the second round's verdict
(`carried: no third round`).

The last line is `gates: <p> pass, <f> fail`, with `, 1 pending` while the
critic is. Each red run after a change to
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
