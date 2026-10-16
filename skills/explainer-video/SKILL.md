---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic, or voice a narration the user writes. Use when the user asks for an
  explainer video or narration audio, or for its tools to be checked or
  installed (`/explainer-video setup`).
metadata:
  version: 0.7.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries eight stages: **setup**,
which every run starts with; the **brief**, the user's words laid over the
defaults; **source**, each source read into a source pack; **script**, a cited
scene file written from the pack and held to the script gates; **voice**,
English narration; the **storyboard**, where the user approves or revises each
scene; **render**, the scene file turned into a captioned MP4; and **gates**,
which the render runs and which block a video below the floors.
Asked for a video from sources, run the stages in order (brief, source,
script, voice, storyboard, render), stopping for the user only at the
storyboard and where a stage says to stop or ask. Asked for a video of a topic
alone, say that topic research is not in this version and ask for a source.
Asked for narration the user writes, skip to Voice or Render.

## Setup

`/explainer-video setup` runs the check and the install with no video, so the
tools are in place before a deadline. Setup writes to two per-user folders: the
**tool cache**, holding the npm packages and Chrome under the hash of this
skill's lockfile and each model under its pinned revision, and the **font
store**, holding fonts by family and version. An install in the tool cache for
another lockfile hash that no run has used for 30 days is **stale**. Run the
script by the skill's own path, `<skill>` below being the folder this file is
in:

1. **Check.** `node <skill>/scripts/setup.mjs check`, adding `--all` when the
   user asked for every opt-in row too. Exit 0 means every row is present and
   nothing is stale: say so and stop.
2. **One yes.** Show the table as printed, then ask once for the whole table,
   naming the total it prints: one yes installs every missing row and removes
   every stale install. Run install only after the yes. When every missing row
   is a system package and nothing is stale, skip the question and go to step
   4.
3. **Install.** `node <skill>/scripts/setup.mjs install`, with the same
   `--all`. It installs into the tool cache and the font store, removes the
   stale installs, then prints the table again.
4. **Report.** Show the latest table. A `missing` system package (ffmpeg, or
   `uv` beside an opt-in Python row) is one the skill never installs: relay its
   install lines from the output, ask the user to run the one for their OS,
   then check again. A `refused` or `failed` row: relay the reason as printed.

To remove the tools, the user deletes the `explainer-video` folders that the
`writes to` paths sit in. Setup deletes only after the yes: the stale installs,
and what an earlier install of a missing row left half done.

## Brief

The **brief** is the run's settings, one value per knob, plus what the video
must include and must avoid. The user's request beside the sources, the
**steering prompt**, moves knobs off their defaults:

| Knob | Default | Takes |
| --- | --- | --- |
| `focus` | the source's main ideas | what the video should say |
| `length` | 2 | minutes, 1 to 5 |
| `audience` | a developer new to the source | who watches |
| `language` | `en` | `en` in this version |
| `style` | the store default (see Render) | a style profile name |
| `voice` | `bf_emma` | a narrator id in `<skill>/narrators.json` |
| `aspect` | `16:9` | `16:9` in this version |
| `score` | `on` | `on` (music and sound effects under the narration) or `off` |
| `must` | none | a topic or term the video says or shows |
| `avoid` | none | a topic or term the video never touches |

1. **Write.** Choose a short kebab-case `<slug>` for the video
   (`ship-overview`), then run `node <skill>/scripts/brief/brief.mjs
   explainers/<slug> [<knob>=<value>]...`, one argument per knob the steering
   prompt moves, and `must=<item>` or `avoid=<item>` per list item. A male or
   female voice asked for is that language's default narrator of that gender.
   It prints one `brief <knob>: <value>` line per knob, then `brief: written
   -> brief.json`: show the knob lines to the user as the brief and go on
   without waiting for their approval.
2. **On exit 1**, `brief <knob> <value>: <why>` names a value this version
   cannot make: tell the user in one line, run again without it, and go on.
3. **A later change**, from the user or a fix, is the same command with just
   the knobs that change; the others keep their values, but a language
   change without a voice takes that language's default narrator, and a list
   given replaces that list. It prints `brief: unchanged`, nothing to redo, or
   `brief: <knobs> changed: redo <stages>`: redo those stages, in order,
   each reusing its cached work for whatever did not change. A language, voice
   or style change deletes the compiled `script.json`, so compile before the
   first stage it names.

## Source

The source stage reads each source into the **source pack**, in the **run
folder** `explainers/<slug>/` (see Voice): a verbatim **snapshot** per source,
the **excerpts** a script may cite, each the source's own words at a
**locator** (`page 4`, `slide 2 notes`, `§ Install`, `lines 12-14`,
`src/app.js:12-14`), and the **outline**. A source is a git repo folder (`.`
for this repo), a web page URL, or a `.pdf`, `.md`, `.txt`, `.html`, `.docx` or
`.pptx` file. Subagents read the snapshots; only the outline enters this
conversation, so a large repo does not crowd out the work.

1. **Snapshot.** `node <skill>/scripts/source/snapshot.mjs explainers/<slug>
   [--minutes <n>] <source>...`, `--minutes` the brief's length.
   It replaces `snapshots/` whole, drafts included, so every reader runs again
   after it. It prints `source <id>: <kind> · <n> <unit> · <source>` per
   source, a repo's followed by `withheld <id>/<path>: <why>` for each file
   withheld for a secret (a `.env` file, a secret file name, a secret pattern
   in its text: relay these), then `budget: <b> excerpts (...); shares <id>
   <n>, ...`, the budget being 8 per minute, at least 12. A repo snapshot
   holds only the text files git tracks or would track, never an ignored one,
   a binary file, a symlink or anything under the `explainers/` folder
   holding this run. A page's URL is kept without its credentials, query or
   fragment, since the pack is committed.
2. **On exit 1**, there is no `sources.json`: relay each `source <source>:
   <why>` line. On `source: <row> is not installed`, run the setup steps
   above, then snapshot again. A scanned PDF has no text to read, and a folder
   outside git cannot say which of its files are ignored: ask the user for the
   source in another form, or to drop it, then snapshot again.
3. **Read.** Dispatch one subagent per source, all in one turn, each with
   `<skill>/agents/source-reader.md` as its prompt, its placeholders filled
   from that source's entry in `explainers/<slug>/snapshots/sources.json`
   (`{id}`, `{kind}`, `{source}`, `{snapshot}`, `{share}`), `{run}` the run
   folder, `{skill}` this skill's folder, and `{focus}` the brief's focus.
   Each writes its draft and
   replies with its check's pass line. Never read a snapshot or a draft here.
4. **Pack.** `node <skill>/scripts/source/pack.mjs explainers/<slug>` checks
   every draft again, numbers the excerpts `ex-1`, `ex-2`, ... across the
   pack, and writes `excerpts.json` and `outline.md`. On exit 1, send each
   `pack <id>: ...` line to that source's reader to fix, then pack again.
5. **Outline.** Read `outline.md`: each source with its summary, each excerpt
   by id, locator and note. A scene file cites an excerpt by id, `[ex-3]`.

## Script

The script stage writes the **scene file**, `explainers/<slug>/script.md` (its
format is under Render), from the pack's outline and the brief, then holds it
to the **script gates**.

1. **Write.** Five roles in order, one scene each but `point`, which takes one
   or more: `hook` (why watch), `context` (what the thing is), `point` (one
   idea each), `recap` (the points again in brief), `end` (one closing line).
   Under each scene heading, `role: <role> · <n> s`: 12 to 30 seconds, adding
   up to the brief's length. A scene's spoken words are its seconds times the
   narrator's `rate` in `<skill>/narrators.json`, within 10 percent. Write for
   the brief's audience, about its focus; say or show each `must` item and none
   of the `avoid` items. Every sentence that states a fact cites the excerpts
   that state it; a transition or framing question is `[no-claim]`. No em or
   en dashes anywhere, and at most 25 words a sentence. Leave the header's
   `language`, `narrator` and `style` out: the brief supplies them.
2. **Compile.** As under Render, step 3.
3. **Support check.** Dispatch one subagent with
   `<skill>/agents/support-checker.md` as its prompt, `{run}` the run folder
   and `{skill}` this skill's folder. It writes `support.json`, its verdict on
   every sentence, and replies with its `script support:` line.
4. **Script gates.** `node <skill>/scripts/script/check.mjs explainers/<slug>`
   prints one line per gate, `script <gate>: pass` or `fail: <findings>`
   (`sentences` warns instead of failing), then `script: <p> pass, <f> fail,
   <w> warn`. `arc`, `budget`, `dashes` and `sentences` hold step 1's rules;
   the others:
   - `cites`: every cite in `excerpts.json`, still word for word in its
     snapshot.
   - `support`: every sentence judged `supported` or `connective` on its
     present wording.
   - `coverage`: the `must` and `avoid` items, each matched as whole words in
     any case (`must=merge` is not met by "merges").
   - `reading`: each visual item on screen, from the sentence it rises at to
     the scene's end, long enough to read: 0.8 s for three words or fewer,
     else 0.3 s a word and at least 1.2 s; a card's texts add up.
5. **On exit 1** with `script: no <input>: <why>` on stderr and no gate lines,
   run what `<why>` names, then the script gates again. Otherwise fix what each
   `fail` line names in the scene file, compile, then run the support check
   again whenever the narration changed, and the script gates again. A red
   `support` line ends the summary in `next: fix attempt <a> of 2`: rewrite each
   failing sentence to say only what its excerpts say, cite the excerpt that
   does say it, and give an `unmarked` sentence the cites for its claim or turn
   it into a transition. On `stop: unsupported claims after two fix attempts`,
   stop: report each failing sentence and ask the user what the video may say.
   The stop holds, whatever the next rewrite, until the support gate passes
   or a brief change redoes the script.
6. **On exit 0**, report the summary line and go on to Voice, then the
   Storyboard.

## Voice

The voice stage turns each scene's narration into audio with every word timed,
then runs **voice QC**, which blocks. It reads a **run folder**,
`explainers/<slug>/` by default, `<slug>` a short kebab-case name for the video
that you choose (`ship-overview`), holding `script.json`, which the compile
stage writes from the scene file (see Render) or you write by hand for voice
alone (render needs the compiled one):

```json
{
  "language": "en",
  "narrator": "am_fenrir",
  "scenes": [{ "id": "hook", "narration": ["First sentence.", "Second."] }]
}
```

`narrator` is optional: without it the stage takes the language's first default
in `<skill>/narrators.json` (`bf_emma`). Narration is the **spoken form**: write
numbers, dates and symbols out as words ("forty two", not "42"), because QC
compares the text against what the aligner hears: a numeral's spoken words
match nothing in the text and cost precision.

1. **Tools.** Voice needs the npm packages, `model:kokoro-82m` and
   `model:wav2vec2-base-960h`. Run the setup check first; any of them missing,
   run the setup steps above before voicing.
2. **Voice.** `node <skill>/scripts/voice/voice.mjs explainers/<slug>`. It
   prints one line per scene, `voice <id>: voiced|cached · recall · precision ·
   rate · pass|fail: <why>`, then a summary line. A scene whose narration,
   narrator and language are unchanged is a cache hit and is not voiced again.
3. **On a pass** (exit 0), the stage has written `voice.json` in the run
   folder: per scene its WAV under `.cache/voice/`, its duration and each
   word's start and end in seconds from the start of that scene's WAV. Report
   the summary line.
4. **On a fail** (exit 1) with scene lines, relay each failing scene's line as
   printed: it names the measure, its value and the floor or band it missed.
   Rewrite that scene's narration in spoken form and voice again; the scenes
   that passed are cached. The run folder holds no `voice.json`, not even an
   earlier pass's, until every scene passes.
   Exit 1 with no scene lines is an input or tool error (an unknown narrator,
   a scene with no narration, a failed synthesis): relay the stderr message as
   printed.

## Storyboard

Read [reference/storyboard.md](reference/storyboard.md) now and run its steps.

## Render

The render stage turns a **scene file**, the script's Markdown form at
`explainers/<slug>/script.md`, into a captioned MP4 with an SRT and a poster.
Its shape:

````markdown
# How Ship lands a pull request
language: en
narrator: am_fenrir

## Scene hook · The promise

### Narration
1. Ship opens {42|forty two} pull requests, each one `merged`. [ex-3]
2. Here is how. [no-claim]

### Visual
```json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request" } }
```
````

- **Header.** Only `language`, `narrator` and `style`. `language` defaults to
  `en`, the only language render draws; `narrator` and `style` are optional.
  With a brief in the run folder, compile takes all three from it and refuses
  a header key that names another value.
- **Scenes.** `## Scene <id> · <title>`, the id kebab-case and not `main`,
  then optionally `role: <role> · <n> s` (see Script), which the script gates
  need.
- **Narration.** Numbered sentences in spoken form; an indented line continues
  the sentence above, so its cites go on the last line. `{written|spoken}`
  shows the written form in the captions and voices the spoken one; backticks
  are dropped. A caption breaks only between written tokens, so each holds at
  most 84 characters. Every sentence ends in `[a, b]`, its cites, or in
  `[no-claim]` when it makes no claim.
- **Visual.** One JSON block per scene, one component, required props marked
  `*`: `title` (`kicker`, `title*`, `subtitle`), `cards` (`items*`, each
  `at*`, `label*`, `value*`, `note`), or `terminal` (`title`, `lines*`, each
  `at*`, `text*`). `at` is a sentence number: that item rises in as the
  sentence starts.

1. **Draft.** From sources, the Script stage above wrote and checked the scene
   file, and the user approved it on the Storyboard. With none, write it with
   the user from what they want the video to say, done when they approve the
   draft.
2. **Tools.** Rendering needs `npm-packages`, `chrome`, `ffmpeg` and the fonts
   its style profile names (for `claude-code`: `font:source-serif-4`,
   `font:inter`, `font:jetbrains-mono`), beside the voice stage's rows. Run the
   setup check first; any of them missing, run the setup steps above.
3. **Compile.** `node <skill>/scripts/script/compile.mjs explainers/<slug>`
   prints `compile: <n> scene(s) -> script.json`. Exit 1 prints
   `compile: [<scene>: ]<what>` on stderr: fix what it names and compile again.
4. **Voice.** Run the voice stage above on the same run folder, again after
   any narration edit.
5. **Render.** `node <skill>/scripts/render/render.mjs explainers/<slug>`.
   Unless the brief's `score` is `off`, it synthesises a **score** arranged to
   the scenes (one section per scene, ducked under the words, a whoosh on each
   cut and a sting after the last word) and mixes it under the narration,
   writing `score.json` (its preset, seed and cues). It masters the mix to -14
   LUFS, renders, then runs the gates (see Gates) and prints their lines.
   Only when every gate passes does it print one `delivery <check>:
   pass|fail` line per delivery check (`resolution`, `frame rate`, `aspect`,
   `duration`, `audio`, `srt`), then `delivered:
   <path>` and `render: <slug>.mp4 <seconds> s, <n> scene(s), stills <hit>/<n>
   cached, video cached|rendered`. A scene still, the score and the video are
   cached by content, so an unchanged run renders nothing again.
6. **On a pass** (exit 0), the run folder's `out/` holds `<slug>.mp4`,
   `<slug>.srt` and `poster.png`, and the same three are copied to the printed
   path, `explainer-video/<repo>/<slug>/` in the user's videos folder (the XDG
   videos folder on Linux, `~/Movies` on macOS, `%USERPROFILE%\Videos` on
   Windows), so the video outlives the run folder. Then run Storyboard step 8.
7. **On a fail** (exit 1), relay what was printed. A `gate <name>: fail` line
   means nothing was delivered and `out/` was emptied: follow Gates below. A
   `delivery <check>: fail:
   <measured> vs <wanted>` line means nothing was copied to the videos folder
   and `out/` was emptied, an earlier render's files too. `style profile <name>
   fails contrast: <token> on <surface> ...` names each pair under its floor,
   and `gates.contrast.<role>: not a number` a floor that is no number;
   `style profile <name>: gates.<group>.<key> <v> lowers the skill's floor
   <f>` or `no such floor` names a gates block the skill refuses: fix those
   values or choose another profile. `<row> is not installed`: run
   setup. `no script.json`, `no voice.json`, `voice.json does not match` or
   `voice.json holds narrator` names the stage to run first. `no render fonts
   for language <x>`: this
   version renders English only. A profile's layout, motion or font this
   version cannot draw: choose another profile. Any other `render: <why>`
   line, a HyperFrames or ffprobe failure among them: relay it with the
   output printed above it. A `gates: <why>` line with no `gate` line above
   it means the gates could not run: `no Chrome under`: run setup; any other,
   relay it with the output above it.

**Style profiles** are looked up in three stores, first match winning: the
project's `explainers/.styles/`, the user config store's `styles/`, and the
skill's bundled `<skill>/styles/`. The header's `style:` names one; without it,
the first store holding a `default` file (one profile name) decides, else
`claude-code`. A run copies its profile to `<run>/style.json` and keeps using
that copy, so a later edit to a store never changes this video; delete the
copy to take up the edit, or name another profile in `style:`.

## Gates

A **video gate** checks the rendered video against a floor and blocks: a red
gate means no video. The render stage runs them all after every render;
`node <skill>/scripts/gates/gates.mjs explainers/<slug>` re-judges the render
still in `out/`, which only a green render leaves (a red render empties
`out/`, so render again, which reuses the cached video), and deletes nothing.
Each prints `gate <name>: pass|fail: <measured> vs <floor>`:

- `layout`: HyperFrames' check, plus the layout probe (text at least 18 px,
  nothing clipped or overflowing its box, every text box inside the 5 percent
  safe margin, no text box overlapping another), on frames every 15 frames
  and on each scene's settled last frame.
- `contrast`: 4.5:1 for body text and 3:1 for large text (24 px, or 18.66 px
  bold), on the same frames. The palette check when the profile loads holds
  the faint, accent and status colours to 3:1 only, since the scenes draw them
  large; text drawn small in one of them is held to 4.5:1.
- `loudness`: -14 LUFS plus or minus 1 and a true peak at most -1 dBTP,
  measured on the encoded MP4.
- `captions`: every word timed in order inside its scene, every cue non-empty,
  in order, at most 84 characters and inside the video, and the SRT equal to
  the burned-in cues.
- `sfx`: at most 24 sound effects in any minute, counted from `score.json`'s
  cues. The score drops a cue that would break the floor, so a red `sfx` is a
  skill defect (see On a red gate).

A summary line follows, `gates: <n> pass, <m> fail`, ending on a red run with
`next: fix attempt <a> of 2` or `stop: red after two fix attempts, no video`.
Layout and contrast results are cached per scene by everything that draws it,
so a fix re-gates only the scenes it touched; loudness, captions and sfx run
every time. The stage writes `gates.json`, the machine record, and `gates.md`,
the readable report with every red gate's findings.

**On a red gate**, relay its line and fix what its findings name **inside the
script**: the visual's layout, its text size, colours within the
profile, timing, or re-voiced audio, never the narration, the scene order or
the scene count. Compile, voice if the audio changed, and render again. The
attempt counts live in `gates.json`: each gate's count resets when that gate
passes, and the run's count, which `stop` reads, when every gate passes. Both
reset when the narration changes, so a red that moves from one gate to another
still stops.
On `stop`, stop with no video and run Storyboard step 7. A red `sfx` gets no
fix attempt, whatever `next:` says: no script change can fix it, so relay its
line, stop as on `stop`, and say it is a skill defect.

**Floors** are set in the skill. A profile's optional `gates` block may only
tighten them, and the tightened value is the one applied and printed:
`contrast` (`body`, `large`, raise), `layout` (`textPx`, `margin` as a
fraction, raise), `loudness` (`tolerance` in LU, above 0, and `peak` in
dBTP, no lower than -8.5, lower), `sfx` (`perMinute`, 0 or more, lower).

## Recipe

The run folder's **recipe**, `brief.json`, `excerpts.json`, `outline.md`,
`script.md`, `style.json`, `gates.md` and `manifest.json` (the storyboard
page's URL, skill version, lock hash, profile, narrator, delivered path), is
committed. `explainers/.gitignore` ignores the rest: the snapshots and
drafts, the compiled script, the voice and timeline files, `check.json`,
`support.json`, `gates.json`, `stills.json`, the caches, the composition,
`board/`, `storyboard.html` and `out/`. Every stage writes those lines
between its `# explainer-video: begin` and `end` markers and leaves the file's
other lines alone.
