---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic. Use when the user asks for an explainer video, or for its tools to
  be checked or installed (`/explainer-video setup`).
metadata:
  version: 0.1.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries two stages: **setup**,
which every run starts with, and **voice**, English narration for a script the
user supplies. The stages that write the script and render the video are not
in this version. Asked for a video, say so in one line and offer `setup`, or
voicing a narration the user writes.

## Setup

`/explainer-video setup` runs the check and the install with no video, so the
tools are in place before a deadline. Setup writes to two per-user folders: the
**tool cache**, holding the npm packages and Chrome under the hash of this
skill's lockfile, and the **font store**, holding fonts by family and version.
An install in the tool cache for another lockfile hash that no run has used for
30 days is **stale**. Run the script by the skill's own path, `<skill>` below
being the folder this file is in:

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
`explainers/<slug>/` by default, holding `script.json`:

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
compares the text against what the aligner hears and a numeral fails it.

1. **Tools.** Voice needs the npm packages, `model:kokoro-82m` and
   `model:wav2vec2-base-960h`. Run the setup check first; any of them missing,
   run the setup steps above before voicing.
2. **Voice.** `node <skill>/scripts/voice/voice.mjs explainers/<slug>`. It
   prints one line per scene, `voiced` or `cached` with its recall, precision
   and rate, then a summary line. A scene whose narration, narrator and
   language are unchanged is a cache hit and is not voiced again.
3. **On a pass** (exit 0), the stage has written `voice.json` in the run
   folder: per scene its WAV under `.cache/voice/`, its duration and each
   word's start and end in seconds. Report the summary line.
4. **On a fail** (exit 1), relay each failing scene's line as printed: it names
   the measure and value that missed (content-word recall under 0.8, precision
   under 0.85, or a rate outside 9 to 22 characters per second). Rewrite that
   scene's narration in spoken form and voice again; the scenes that passed
   are cached. No `voice.json` is written until every scene passes.
