---
name: creative-video
description: >-
  Make a creative, engaging, animated narrated video that teaches a concept,
  its scenes authored freely in HyperFrames, long ones in chapters. Use when
  the user asks for a creative, engaging or animated video, a video that
  teaches a concept, or a long video in chapters, or for its tools to be
  checked or installed (`/creative-video setup`). A request for an "explainer
  video" goes to `explainer-video`.
metadata:
  version: 0.14.0
---

# creative-video

A **creative video** is a narrated video that teaches a concept, its scenes
authored freely in HyperFrames rather than drawn from a fixed set of
components, a long one split into **chapters**. Given a concept, a topic, a
repo or a document (and optionally a language and a length), make one under
[The stance](#the-stance), by the steps of [Make a video](#make-a-video). A
video runs from about one minute to about 30 minutes, in chapters past about
six minutes, so a fix re-renders one chapter, not the whole video: one video,
never offered in parts. Run setup alone only when asked (`/creative-video
setup`).

## The stance

Read this before anything else and work by it through every step. A run with
nobody to answer (the request says to go ahead without questions, or a
scheduled run) is **unattended**: wherever the stance says the person picks,
take your recommendation and write down why.

You are making a film someone chooses to watch to the end, and it is the best
explainer on this subject they will see this year. Treat it as the reel you
would show to get your next job. The expected version is not the goal: a
narrator over tidy slides is the failure this stance exists to prevent. Go all
out, and aim everything you have at the explanation.

### What has to be true

**The spectacle is the explanation.** Every striking thing on screen carries
the idea: a metaphor that is the mechanism, a picture that changes the moment
the narration names the change. Decoration around the idea costs the viewer
learning (removing interesting but irrelevant material raised transfer by
d = 0.80; removing background music, by d = 0.95). If a shot would survive
with the narration muted and still teach nothing, it is decoration.

**One format concept owns the film, chosen before any scene.** A concept is
a world (a kitchen at service, a heist), a format (a game show where the
viewer is the contestant, a courtroom), or the subject itself drawn directly,
when the thing already teaches better than any metaphor would (an algorithm
running, a proof building). Write three directions that differ in kind, not in
palette: make one the bold one you would not pick first, and let one be the
subject drawn directly when it fits. Recommend one and say why. The person
picks; with nobody there to pick, take your recommendation and write down
why. The chosen concept owns the arc, the cast, the audience device, what each
sound means and what each colour means. A film with no concept falls back to
hook, points, recap: that is the expected version.

**The viewer's wrong idea is on screen.** Name what a smart newcomer believes
that is false, give that belief a voice (a learner character, a rival, the
viewer's own guess), and break it on screen. Feeling clear is not learning;
staging the misconception is (d of about 0.8).

**The viewer is asked, not told twice.** Before the answer, pose the question
and hold a beat for a guess. A prediction or a "will it run?" frame beats a
recap; a recap that replays content teaches nothing.

**Each metaphor says where it breaks.** One line, in the narration or on
screen, where the comparison stops being true.

**The picture moves with the words, not the sentences.** Time events to the
word that names them, several per sentence where the narration names several
things: the best bar video changed the picture about 15 times a minute without
cutting. Build, don't cut.

**The voice has energy.** Conversational, about 155 words a minute, a person
talking to one viewer, never a lecture read aloud. Slow down only at the hard
step.

**Facts are traced; pictures are free.** Every factual sentence comes from a
source you can name that still stands: check whether its authors have since
updated or withdrawn it. Metaphors, characters and staging are yours.

### Decide, then build

Before any scene, write `SPEC.md`: the concept and why, and a number wherever
you would have written an adjective. At least:

- **Colour**: the palette as hex values with a role each, drawn from the
  concept's own world (a game show's stage, a kitchen, a courtroom), and what
  each colour means in the story. Colour carries meaning or stays out.
- **Sound**: the sound palette as a short list, each sound with the story event
  it marks and nothing else; where the bed plays, where it drops out, and the
  one moment it changes. A low bed plays by default, well under the voice and
  drawn from the concept's world (room tone, a track), and drops out for the
  hardest step of the explanation. Effects are recorded CC0 sounds that
  `sounds.mjs` finds, never tones or beeps generated in code: nobody can hear
  whether they are good, and they sound like it.
- **Motion**: the event rate, the easing family, what moves on which word.
- **Type**: faces and sizes.

The `hyperframes` skill is your engine and its craft; `hyperframes-cli` is its
command line, run through this skill's pinned copy (`hf.mjs`,
[reference/authoring.md](reference/authoring.md#the-pinned-cli)). Read the
`hyperframes` `SKILL.md` and the references you need. Its BANNED list (the
dark navy void with a glow, neon, floating particles, purple and blue
gradients, everything centred and fading in) stays banned, with one more way
out: the format concept needs it, and `SPEC.md` says why in one line. "It
looks techy" is not a reason.
Where the `hyperframes` loop and [Make a video](#make-a-video) differ, these
steps win: `DIRECTIONS.md` is its storylines, the stills review of step 10 is
its review (no `REVIEW.md`, nothing but the sheets to the reviewer), the
storyboard of step 11 is its one stop, the gates and the render follow it with
no stop at a Studio preview,
every command but the gates and the render (`gates.mjs`, `render.mjs`) runs
through `hf.mjs`, and a registry block is raw material you edit into the
concept's look, never a look to pick.

### Look at what you made

You cannot watch video, so look at stills. Before the full render, render a
contact sheet of every scene's key frames and describe each frame as a
stranger would: what is the eye drawn to, what does it say without the
narration. Hand the sheet to a fresh-eyes subagent that has not read your
plan. Name every default that crept in, from the BANNED list or not, and fix
it. Measure the sound you cannot hear: loudness, peaks, and that each effect
lands on its picture. Say in your delivery note what was measured, not heard.

## Make a video

`<skill>` is the folder this file is in, `<run>` the run folder
`creative-videos/<slug>` in the current repo, `<slug>` a short kebab-case name
for the video. [reference/authoring.md](reference/authoring.md) holds the run
folder's files, timing, the word anchors, the pinned CLI and the render;
[reference/gates.md](reference/gates.md) the gates.

1. **Brief.** Write `<run>/brief.json`, `{ "length": <minutes> }`: the length
   asked for, about two minutes when none is. It may carry `"must"` and
   `"avoid"` word lists, for what the video has to say or show and what it must
   not. The language is the one asked for, English when none is; the narrator
   the one asked for, else the language's default in `<skill>/narrators.json`.
   Name the audience (the one asked for, else a smart newcomer): it is the
   researcher's `{audience}` and heads `DIRECTIONS.md`.
2. **Tools.** Run setup's check (below) with that narrator. A missing row:
   run setup's steps first. The `hyperframes` and `media-use`
   skills must be installed (Composed skills, below). A brand named or
   material given (a logo, a site, a deck): run
   [reference/brand.md](reference/brand.md)'s steps.
3. **Sources.** Read [reference/sources.md](reference/sources.md) and run its
   steps, to the outline and the still-standing check.
4. **Directions.** Write `<run>/DIRECTIONS.md`: three directions that differ
   in kind, each a paragraph (the concept, its arc, its cast and audience
   device, its sound and colour), one bold, one the subject drawn directly
   when that fits, and one marked recommended with why; with a brand, all
   three wear it ([brand.md](reference/brand.md#wear-the-brand)). Make the
   recommended one without asking: attended, the person meets all three on the
   storyboard (step 11) and picks there; unattended, it stands: write
   `<run>/unattended.json`, `{ "direction": "<id>" }`. Write the pick and its
   reason into `DIRECTIONS.md`.
5. **Spec and kit.** Read the `hyperframes` skill's `SKILL.md`, its
   `references/spec.md` and the references the concept needs, and this
   skill's [craft-teaching.md](reference/craft-teaching.md) and
   [craft-motion.md](reference/craft-motion.md). Write `<run>/SPEC.md` by the
   stance, then the format kit in `<run>/project/kit/`, both before any scene.
   Write the bed and the sound palette into `<run>/project/kit/sound.json` and
   run `node <skill>/scripts/sound/sounds.mjs <run>`
   ([Sound](reference/authoring.md#sound)); the root places the bed. A bed
   that is music carries one reason line on `SPEC.md`'s Sound line, as a
   banned default does.
6. **Script.** Write `<run>/script.json`
   ([reference/voice.md](reference/voice.md) holds its shape), one scene per
   idea of the arc: the misconception given a voice and broken, the question
   posed before its answer, each metaphor's limit said. Every factual
   sentence comes from an excerpt in the outline and cites it: each scene's
   `cites` holds one list of excerpt ids per sentence, `[]` for a sentence
   stating no fact. Past about six minutes, the video is in chapters of two to
   six minutes, and the script carries the **chapter plan**, `chapters`
   ([authoring.md](reference/authoring.md#chapters)): write the plan and the
   whole script, every chapter's, before any scene, so the video keeps one
   arc. A cast speaks: each scene's `roles` names who says each sentence, and
   `<run>/project/kit/cast.json` gives each role its own voice and style
   line, so a learner, a rival or a guest sounds like no one else. Run the
   claims check, `node <skill>/scripts/source/claims.mjs <run>`, and fix the
   cites until its `claims cites:` line passes. Then dispatch one subagent with
   `<skill>/agents/support-checker.md` as its prompt, `{run}` the run folder
   and `{skill}` this skill's folder; it judges each sentence against its
   excerpts and replies with the claims check's `claims support:` line. Run
   the claims check yourself before voicing: on exit 1 fix what its
   `claims <check>: fail` lines name (a cite, or a sentence's words or
   cites) and dispatch the checker again. On `; stop:
   unsupported claims after two fix attempts`, stop: report each failing
   sentence and ask what the video may say.
7. **Voice.** Run [reference/voice.md](reference/voice.md)'s steps until the
   voice stage passes.
8. **Timing.** `node <skill>/scripts/render/timing.mjs <run>`, again after
   every re-voice.
9. **Scenes.** Author `<run>/project/compositions/<id>.html` for every
   `to author` line timing printed, each event that answers a word placed at
   `at(scene, word, nth)`, each effect's clip at the `at()` of the event it
   marks.
   In chapters, author chapter 1's scenes only, its first frame drawing the
   chapter's title; the other chapters wait for step 11's approval.
10. **Look: the stills review.** `node <skill>/scripts/hf.mjs <run> check
    --json` until it reports no errors, then `node <skill>/scripts/hf.mjs
    <run> snapshot --review --json`, and describe each frame as a stranger
    would; with a brand, hold each logo against `brand.json`'s file, its
    colours unchanged. Dispatch one subagent with
    `<skill>/agents/stills-reviewer.md` as its prompt, `{sheets}` every path
    in the output's `review.sheets`, `{notes}`
    `<run>/.cache/review/stills-notes.md`, and nothing else from the run. Fix
    every P0 and every default it or you named, fix each P1 or write in
    `DELIVERY.md` why it stays, then snapshot what changed.
11. **Storyboard.** Attended: read
    [reference/storyboard.md](reference/storyboard.md) and run its steps until
    `board apply` prints `board: approved`. That one look approval covers the
    whole video (the render refuses without it): the gates and the render
    follow with no further stop. Unattended, skip the storyboard.
    **In chapters**, attended or not, once chapter 1 is approved (unattended:
    once step 10 is done), dispatch one subagent per remaining chapter, all in
    one turn, with `<skill>/agents/chapter-author.md` as its prompt, `{run}`,
    `{skill}`, `{chapter}` its number and `{scenes}` its scene ids, then end
    the turn. As each replies, run step 10 on its scenes: `hf.mjs <run> check
    --json`, then `hf.mjs <run> snapshot --review --composition <id> --json`
    once per scene, each `review.sheets` path going to the reviewer as
    `{sheets}` (`--review` refuses `--range`, and without `--composition` it
    reviews the whole film again). Attended, also write its scenes' `title` and
    `notes` into `storyboard.json` (storyboard.md step 1), then build and post
    the board again (storyboard.md steps 3 and 4) without waiting for an
    answer: a comment that comes back is acted on as step 11 says. A change one
    asks for outside its files is yours to make: nothing has rendered yet, so
    one to the kit or an asset costs no extra render (step 13 estimates such a
    change once chapters have rendered), and one to `over.html` changes only
    the mix.
12. **Gates.** `node <skill>/scripts/gates/gates.mjs <run>`
    ([the gates](reference/gates.md)); on exit 1 fix what each `gate
    <name>: fail` line and its indented findings name, then run it again, at
    most two fix attempts
    ([`--check`](reference/gates.md#fix-attempts-and-refusals) spends none;
    [fixing a critic finding](reference/gates.md#the-critic)). On a
    `; stop:` line do not render or deliver: report the red gates and their
    findings, and stop.
    On `; next: run the critic`, the `gate critic: pending` line names the
    stills folder: dispatch one subagent per scene that has no verdict there,
    with `<skill>/agents/critic.md` as its prompt, `{run}` the run folder,
    `{scene}` the scene's id and `{stills}` that folder as the line prints it,
    relative to the run folder (`.cache/critic/<key>`), at most 20 at once,
    the next batch once all have replied; then run the gates again ([which
    scene has none](reference/gates.md#the-critic)). Never read the stills or
    the verdicts in this thread: the gates read them. A `gates: critic
    verdict <scene>.json: <why>` refusal goes, word for word, to that scene's
    critic by SendMessage to fix its verdict; once it replies, run the gates
    again.
13. **Render.** `node <skill>/scripts/render/render.mjs <run>`; it refuses
    until the board approved the look (or `unattended.json` exists) and the
    gates pass on the current project. On exit 1 fix what it names and render
    again. A change since the approval still renders; step 14 quotes its
    `changed after` line. In chapters it re-renders only the chapters that
    changed ([authoring.md](reference/authoring.md#render)). Before a render
    that follows a change to the kit or an asset, run it with `--estimate`
    first and tell the person the `render: <k> of <n> chapter(s) to render`
    line it prints, in full.
14. **Deliver.** Run `node <skill>/scripts/render/credits.mjs <run>` first:
    it writes `<run>/CREDITS.md`'s voices, sound and brand. Then add to it
    each source cited with its locators, and the faces outside the brand and
    their licences. Write `<run>/DELIVERY.md` (the concept and why it was
    picked; any brand, with what was fetched and from where, as `CREDITS.md`'s
    `## Brand` lists it; what was measured, quoting the render's
    `changed after`, `delivery` and `measured loudness` lines
    and the gates' `warn` lines, and what was only
    looked at; that the sound was measured, not heard, and each effect placed
    on its event's word; any source updated or withdrawn; the weakest shot and
    what you would change).
    Reply with the `out/` path, the concept, the delivery lines and the
    weakest shot.

## Setup

`/creative-video setup` runs the check and the install with no video. Setup
writes to this skill's own per-user folders, never `explainer-video`'s: the
**tool cache**, holding the npm packages and Chrome under the hash of this
skill's lockfile and each model under its pinned revision, and the **font
store**, holding fonts by family and version. A tool cache install no row
needs on this machine, unused for 30 days, is **stale**. Run the script by the
skill's own path, `<skill>` below being the folder this file is in:

1. **Check.** `node <skill>/scripts/setup.mjs check`, adding `--voice <id>`
   with the narrator the voice stage will use (`script.json`'s `narrator`):
   the voice rows listed are that narrator's (without it, the English
   default's). Exit 0 means every row is present and nothing is stale: say
   so, with any line under the table, and stop.
2. **One yes.** Show the table as printed, with any line under it, then ask
   once for the whole table, naming the total it prints: one yes installs
   every missing row and removes every stale install. Run install only after
   the yes. When every missing row is a system package or a key and nothing is
   stale, skip the question and go to step 4.
3. **Install.** `node <skill>/scripts/setup.mjs install`, with the same
   `--voice`. It installs into the tool cache and the font store, removes the
   stale installs, then prints the table again.
4. **Report.** Show the latest table. A `missing` system package (ffmpeg) is
   one the skill never installs: relay its install lines from the output, ask
   the user to run the one for their OS, then check again. A `missing` or
   `refused` key (`key:gemini`, the `GEMINI_API_KEY` of the Egyptian Arabic
   narrators; `key:elevenlabs`, an ElevenLabs narrator's
   `ELEVENLABS_API_KEY`) is one the user sets: relay the line under the table
   with its link to a key, then check again. Any other `refused` or `failed`
   row: relay the reason as printed.

`onnx-cuda` (Kokoro on the GPU) is listed on Linux x64 with an NVIDIA card of
compute capability 7.5 or higher, beside an English Kokoro narrator. CUDA 13
and cuDNN 9 are host prerequisites: the line under the table says whether
Kokoro runs on the GPU here or names the missing library.

`sounds:kenney`, Kenney's CC0 sound packs (12 MB), is what `sounds.mjs`
searches when Openverse finds nothing.

Whenever the **Gemini data notice** prints under a table, relay it word for
word: setup prints it once per key, the first time Google accepts that key.

To remove the tools, the user deletes the `creative-video` folders that the
`writes to` paths sit in.

## Composed skills

Scenes are HyperFrames compositions, authored with the `hyperframes` skill;
media is found or made with `media-use`. Both are pinned to the HyperFrames
release this skill's `package.json` installs. Authoring needs both; when
either is missing, ask once, then install it with:

```
npx skills add heygen-com/hyperframes#6df754fbf3289ee0dc19e123e0628cc69218e518 --skill hyperframes --agent claude-code -y
npx skills add heygen-com/hyperframes#6df754fbf3289ee0dc19e123e0628cc69218e518 --skill media-use --agent claude-code -y
```

## Voice

To voice a `script.json` the user wrote in a run folder
`creative-videos/<slug>`, read [reference/voice.md](reference/voice.md) and
run its steps.
