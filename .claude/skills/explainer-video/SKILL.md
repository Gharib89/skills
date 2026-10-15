---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic, or voice a narration the user writes. Use when the user asks for an
  explainer video or narration audio, or for its tools to be checked or
  installed (`/explainer-video setup`).
metadata:
  version: 0.2.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries **setup**, which every run
starts with, **voice**, English narration, and **render**, which turns a scene
file written with the user into a captioned MP4. Reading sources, the brief,
the storyboard and writing the script from sources are not in this version.
Asked for a video, say so in one line and offer to write the scene file with
the user, then voice and render it.

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

## Voice

The voice stage turns each scene's narration into audio with every word timed,
then runs **voice QC**, which blocks. It reads a **run folder**,
`explainers/<slug>/` by default, `<slug>` a short kebab-case name for the video
that you choose (`ship-overview`), holding `script.json`, which the compile
stage writes from the scene file (see Render) or you write by hand:

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

## Render

The render stage turns a **scene file**, `explainers/<slug>/script.md`, into
a captioned MP4 with an SRT and a poster. Write the scene file with the user:

````markdown
# How Ship lands a pull request
language: en
narrator: am_fenrir

## Scene hook · The promise

### Narration
1. Ship drives {#626|issue six two six} to a `merged` pull request. [ex-3]
2. Here is how. [no-claim]

### Visual
```json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request" } }
```
````

- **Header.** `language` defaults to `en`; `narrator` and `style` are
  optional.
- **Scenes.** `## Scene <id> · <title>`, the id kebab-case and not `main`.
- **Narration.** Numbered sentences in spoken form. `{written|spoken}` shows
  the written form in the captions and voices the spoken one; backticks are
  dropped. A trailing `[a, b]` lists the sentence's cites, `[no-claim]` none.
- **Visual.** One JSON block per scene, one component: `title` (`kicker`,
  `title`, `subtitle`), `cards` (`items`, each `at`, `label`, `value`,
  `note`), or `terminal` (`title`, `lines`, each `at`, `text`). `at` is a
  sentence number: that item rises in as the sentence starts.

1. **Tools.** Rendering needs `npm-packages`, `chrome`, `ffmpeg` and the three
   fonts (`font:source-serif-4`, `font:inter`, `font:jetbrains-mono`), beside
   the voice stage's rows. Run the setup check first; any of them missing, run
   the setup steps above.
2. **Compile.** `node <skill>/scripts/script/compile.mjs explainers/<slug>`
   prints `compile: <n> scene(s) -> script.json`. Exit 1 prints
   `compile: <scene>: <what>`: fix that scene and compile again.
3. **Voice.** Run the voice stage above on the same run folder.
4. **Render.** `node <skill>/scripts/render/render.mjs explainers/<slug>`. It
   prints one `delivery <check>: pass|fail` line per ffprobe check
   (resolution, frame rate, aspect, duration, audio, SRT), then
   `delivered: <path>` and `render: <slug>.mp4 <seconds> s, <n> scene(s),
   stills <hit>/<n> cached, video cached|rendered`. A scene still and the
   video are cached by content, so an unchanged run renders nothing again.
5. **On a pass** (exit 0), the run folder's `out/` holds `<slug>.mp4`,
   `<slug>.srt` and `poster.png`, and the same three are copied to the printed
   path, `explainer-video/<repo>/<slug>/` in the user's videos folder (the XDG
   videos folder on Linux, `~/Movies` on macOS, `%USERPROFILE%\Videos` on
   Windows), so the video outlives the run folder. Report the last line and
   that path.
6. **On a fail** (exit 1), relay what was printed. A `delivery <check>: fail:
   <measured> vs <wanted>` line means nothing was copied. `style profile <name>
   fails contrast: <token> on <surface> ...` names each pair under its floor:
   fix those colours or choose another profile. `<row> is not installed`: run
   setup. `no script.json` or `no voice.json` names the stage to run first.

**Style profiles** are looked up in three stores, first match winning: the
project's `explainers/.styles/`, the user config store's `styles/`, and the
skill's bundled `<skill>/styles/`. The header's `style:` names one; without it,
the first store holding a `default` file (one profile name) decides, else
`claude-code`. A run copies its profile to `<run>/style.json` and keeps using
that copy, so a later edit to a store never changes this video; delete the
copy to take up the edit.

The run folder's **recipe**, `script.md`, `style.json` and `manifest.json`
(skill version, lock hash, profile, narrator, delivered path), is committed.
`explainers/.gitignore`, which every stage writes, ignores the rest: the
compiled script, the voice and timeline files, the caches, the composition and
`out/`.
