---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic, or voice a narration the user writes. Use when the user asks for an
  explainer video or narration audio, for a style profile drawn from
  screenshots, a website, a deck or a video, or for its tools to be checked or
  installed (`/explainer-video setup`).
metadata:
  version: 0.14.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries eight stages: **setup**,
which every run starts with; the **brief**, the user's words laid over the
defaults; **source**, each source read into a source pack; **script**, a cited
scene file written from the pack and held to the script gates; **voice**, the
narration in English or Egyptian Arabic; the **storyboard**, where the user
approves or revises each scene; **render**, the scene file turned into a
captioned MP4; and **gates**, which the render runs and which block a video
below the floors or one the critic fails.
Asked for a video from sources, run the stages in order (brief, source,
script, voice, storyboard, render), stopping for the user only at the
storyboard and where a stage says to stop or ask. Asked for a video of a topic
alone, the source stage researches it first. Asked for narration the user
writes, skip to Voice or Render. With `language: ar`, the run ends after Voice:
report the voice summary line and that this version renders English only.

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
   user asked for every opt-in row too, or the brief's `score` is `ace-step`,
   and `--voice <id>` with the narrator the voice stage will use (the brief's
   `voice`, or `script.json`'s `narrator`): the voice rows listed are that
   narrator's (without it, the English default's). Exit 0 means every row
   is present and nothing is stale: say so, with any line under the table, and
   stop.
2. **One yes.** Show the table as printed, with any line under it (the
   `ace-step` row's: GPU or CPU here, and on the CPU its cost per 30 s of
   score), then ask once for the whole table, naming the total it prints: one
   yes installs every missing row and removes every stale install. Run install
   only after the yes. When every missing row is a system package or a key and
   nothing is stale, skip the question and go to step 4.
3. **Install.** `node <skill>/scripts/setup.mjs install`, with the same
   `--all` and `--voice`. It installs into the tool cache and the font store,
   removes the stale installs, then prints the table again.
4. **Report.** Show the latest table. A `missing` system package (ffmpeg, or
   `uv` beside an opt-in Python row) is one the skill never installs: relay its
   install lines from the output, ask the user to run the one for their OS,
   then check again. A `missing` or `refused` key (`key:gemini`, the Egyptian
   Arabic narrators' `GEMINI_API_KEY`) is one the user sets: relay the line
   under the table with its link to a free key, then check again; Voice waits
   until `key:gemini` reads `present`. Any other `refused` or `failed` row:
   relay the reason as printed.

Whenever the **Gemini data notice** prints under a table, relay it word for
word: setup prints it once per key, the first time it checks that key.

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
| `language` | `en` | `en`, or `ar` (Egyptian Arabic: this version voices it but does not render it) |
| `style` | the store default (see Render) | a style profile name |
| `voice` | the language's default narrator (`bf_emma`, `ar-eg-csagent-2`) | a narrator id in `<skill>/narrators.json` |
| `aspect` | `16:9` | `16:9` in this version |
| `score` | `on` | `on`, `off`, or `ace-step` (music made by the ACE-Step model) |
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

0. **Topic.** Given a topic and no source, dispatch one subagent with
   `<skill>/agents/researcher.md` as its prompt, `{topic}` the topic, `{focus}`
   and `{audience}` the brief's, `{avoid}` none. Its reply, 3 to 8 page URLs,
   is the sources: snapshot them with `--topic "<topic>"`, which refuses any
   other source or count. A page snapshot cannot read: dispatch it once more
   with `{avoid}` every page refused so far, and snapshot its new list. On
   `too few`, or a second refusal, relay it and ask the user for a source.
1. **Snapshot.** `node <skill>/scripts/source/snapshot.mjs explainers/<slug>
   [--minutes <n>] [--topic "<topic>"] <source>...`, `--minutes` the brief's
   length.
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
in `<skill>/narrators.json` (`bf_emma` for `en`, `ar-eg-csagent-2` for `ar`).
Narration is the **spoken form**: write numbers, dates and symbols out as words
("forty two", not "42"), because QC compares the text against what the aligner
hears: a numeral's spoken words match nothing in the text and cost precision.
In Egyptian Arabic narration, keep English terms in Latin letters (`pull
request`); QC spells them in Arabic letters as a speaker says them. An acronym
of more than four capitals QC reads as a word: write it as its letters' names
in Arabic.

1. **Tools.** Voice needs the npm packages and its narrator's rows: English
   `model:kokoro-82m` and `model:wav2vec2-base-960h`; Egyptian Arabic
   `model:egyptian-arabic-wav2vec2` and `key:gemini`. Run the setup check with
   `--voice` set to the narrator this stage uses (`narrator`, else the
   language's default above) first; any row missing, run the setup steps above
   before voicing.
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
   Exit 1 with no scene lines and no `voice: Gemini quota reached` (step 5)
   is an input or tool error (an unknown narrator, a scene with no narration,
   a Gemini narrator with no `GEMINI_API_KEY`, a failed synthesis): relay the
   stderr message as printed. Keep the brief's narrator: only the user moves
   `voice`.
5. **On `voice: Gemini quota reached`**, the key has hit a Gemini limit, whose
   own message the line quotes. The scenes it counts as kept are cached. Relay
   the line and ask the user to pick one: voice again once the quota resets,
   which voices only the missing scenes; set a paid key and voice again; or
   move the brief's `voice` to another narrator.

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
  `*`. `at` is a sentence number: that item rises in, or that change plays, as
  the sentence starts.
  - `title` (`kicker`, `title*`, `subtitle`).
  - `cards` (`items*`, each `at*`, `label*`, `value*`, `note`).
  - `terminal` (`title`, `lines*`, each `at*`, `text*`).
  - `flow`: a chain of 2 to 5 steps joined by arrows (`steps*`, each `at*`,
    `label*`, `note`).
  - `panels`: 2 or 3 side by side (`items*`, each `at*`, `title*`, `body*`).
  - `list`: 1 to 6 points (`title`, `items*`, each `at*`, `text*`).
  - `code`: a highlighted code frame (`lang*`, a Shiki language id; `code*`,
    one string with `\n` between lines, at most 12 lines; `file`;
    `highlights`, each `at*` and `lines*`, `[first, last]` counted from 1).
    The highlights draw only when the style profile's `effects` lists
    `highlight`; otherwise they are dropped with no error.
  - `codediff`: a code frame that turns `before*` into `after*` at `at*`, the
    removed lines closing and the added ones opening (`lang*`, `file`; each
    side one string like `code`, at most 12 lines).

1. **Draft.** From sources, the Script stage above wrote and checked the scene
   file, and the user approved it on the Storyboard. With none, write it with
   the user from what they want the video to say, done when they approve the
   draft.
2. **Tools.** Rendering needs `npm-packages`, `chrome`, `ffmpeg` and the fonts
   its style profile names (for `claude-code`: `font:source-serif-4`,
   `font:inter`, `font:jetbrains-mono`), beside the voice stage's rows, and
   `ace-step` and `uv` when the brief's `score` is `ace-step`. Run the setup
   check first; any of them missing, run the setup steps above.
3. **Compile.** `node <skill>/scripts/script/compile.mjs explainers/<slug>`
   prints `compile: <n> scene(s) -> script.json`. Exit 1 prints
   `compile: [<scene>: ]<what>` on stderr: fix what it names and compile again.
4. **Voice.** Run the voice stage above on the same run folder, again after
   any narration edit.
5. **Render.** `node <skill>/scripts/render/render.mjs explainers/<slug>`. It
   mixes in the **score**, synthesised music (or ACE-Step's, by the brief)
   ducked under speech with sound effects at the cuts and the end, unless the
   brief turns it off, masters to
   -14 LUFS, renders, then runs the gates (see Gates) and prints
   their lines. With `score` `ace-step` on the CPU, render takes minutes: run
   it in the background and wait for its exit. A first render always ends with
   the critic pending (see Gates). Only when every gate passes does it print one
   `delivery <check>: pass|fail` line per delivery check (`resolution`,
   `frame rate`, `aspect`, `duration`, `audio`, `srt`), then `delivered:
   <path>` and `render: <slug>.mp4 <seconds> s, <n> scene(s), stills <hit>/<n>
   cached, video cached|rendered`. A scene still, the score and the video are
   cached by content, so an unchanged run renders nothing again.
6. **On a pass** (exit 0), the run folder's `out/` holds `<slug>.mp4`,
   `<slug>.srt` and `poster.png`, and the same three are copied to the printed
   path, `explainer-video/<repo>/<slug>/` in the user's videos folder (the XDG
   videos folder on Linux, `~/Movies` on macOS, `%USERPROFILE%\Videos` on
   Windows), so the video outlives the run folder. Then run Storyboard step 8.
7. **On a fail** (exit 1), relay what was printed. A `gate` line not `pass`
   means nothing was delivered and `out/` was emptied: follow Gates below. A
   `delivery <check>: fail:
   <measured> vs <wanted>` line means nothing was copied to the videos folder
   and `out/` was emptied, an earlier render's files too. A `style profile
   <name>` line names a colour pair, `gates`, `look` or `effects` value the
   skill refuses: fix it or choose another profile. `<row> is not installed`:
   run setup. `no script.json`, `no voice.json`, `voice.json does not match` or
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
copy to take up the edit, or name another profile in `style:`. Two of a
profile's keys choose how diagrams and code frames draw: `look`, `clean` (the
default) or `sketch`, which outlines flow steps and panels by hand with a seed
taken from the scene and the element, so a render repeats exactly; and
`effects`, the motion effects a video may use, from `draw` (flow arrows stroke
on) and `highlight` (code lines a sentence names). A profile with no `effects`
allows none, and a motion effect it leaves out never reaches the video. The
score's sound effects are separate: `effects` never mutes them.

Asked for a style profile from a look (screenshots, a website, a PDF or PPTX
deck, a video), read [reference/style.md](reference/style.md) and run its
steps, which end on the style card where the user saves the profile or uses
it once.

## Gates

Read [reference/gates.md](reference/gates.md) when a render prints a `gate`
line that is not `pass`, and follow it.

## Recipe

The run folder's **recipe**, `brief.json`, `excerpts.json`, `outline.md`,
`script.md`, `style.json`, `gates.md` and `manifest.json` (the storyboard
page's URL, skill version, lock hash, profile, narrator, delivered path), is
committed. `explainers/.gitignore` ignores the rest: the snapshots and
drafts, the compiled script, the voice and timeline files, `check.json`,
`support.json`, `gates.json`, `score.json`, `stills.json`, the caches, the
composition, `board/`, `storyboard.html` and `out/`. Every stage writes those
lines between its `# explainer-video: begin` and `end` markers and leaves the
file's other lines alone.
