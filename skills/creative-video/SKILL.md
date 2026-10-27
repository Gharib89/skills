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
  version: 0.1.0
---

# creative-video

A **creative video** is a narrated video that teaches a concept, its scenes
authored freely in HyperFrames rather than drawn from a fixed set of
components, a long one split into **chapters**. This version carries
**setup** and the plumbing later versions build on: the source pack, the
voice stage, the narration and chapter joins, captions and delivery.
Authoring arrives in later versions. Asked for a video now, say that
authoring is not in this version yet, offer `explainer-video` for a narrated
video today, and stop. Run setup only when asked (`/creative-video setup`).

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

Whenever the **Gemini data notice** prints under a table, relay it word for
word: setup prints it once per key, the first time Google accepts that key.

To remove the tools, the user deletes the `creative-video` folders that the
`writes to` paths sit in.

## Composed skills

Scenes are HyperFrames compositions, authored with the `hyperframes` skill;
media is found or made with `media-use`. Both are pinned to the HyperFrames
release this skill's `package.json` installs. Authoring, in a later version,
needs both; when the user asks for them, install them with:

```
npx skills add heygen-com/hyperframes#9ebc1f8a13fc2c6756f92394688e35f9891eb5c8 --skill hyperframes --agent claude-code -y
npx skills add heygen-com/hyperframes#9ebc1f8a13fc2c6756f92394688e35f9891eb5c8 --skill media-use --agent claude-code -y
```

## Voice

To voice a `script.json` the user wrote in a run folder
`creative-videos/<slug>`, read [reference/voice.md](reference/voice.md) and
run its steps.
