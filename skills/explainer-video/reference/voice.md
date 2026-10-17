# Voice

The shape of `script.json` in the run folder:

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
   `model:egyptian-arabic-wav2vec2` and `key:gemini`; an ElevenLabs narrator
   `key:elevenlabs` and `model:wav2vec2-base-960h`; an own voice
   (`own:<name>`) the Arabic rows plus `own-voice` and `uv`. Run the setup
   check with `--voice` set to the narrator this stage uses (`narrator`, else
   the language's default above) first; any row missing, run SKILL.md's Setup
   steps before voicing.
2. **Voice.** `node <skill>/scripts/voice/voice.mjs explainers/<slug>`. It
   prints one line per scene, `voice <id>: voiced|cached · recall · precision ·
   rate · pass|fail: <why>`, a failing one ending in `heard: <file>`, then a
   summary line. A scene whose narration,
   narrator and language (and, for an own voice, the enrolled clip) are
   unchanged is a cache hit and is not voiced again. Once every scene passes,
   with a `brief.json` in the run folder, a `voice length: pass|fail` line
   follows the scene lines: the scenes' total voiced seconds, then each
   scene's, and whether they and the render's closing hold land within 10
   percent of the brief's `length`. Before voicing an own voice on the CPU,
   tell the user the time setup's cost line gives for this narration's length.
3. **On a pass** (exit 0), the stage has written `voice.json` in the run
   folder: per scene its WAV under `.cache/voice/`, its duration and each
   word's start and end in seconds from the start of that scene's WAV. Report
   the summary line.
4. **On a fail** (exit 1) with a failing scene line, relay each failing
   scene's line as printed: it names the measure, its value and the floor or
   band it missed, then `heard: <file>`, a path in the run folder holding
   what the aligner heard: lowercase, unpunctuated, spelled by sound. Compare
   it with the narration for words missing, added or swapped (not
   misspelled). Rewrite those words of that scene's narration in spoken form
   and voice again; the scenes that passed are cached. The run folder holds no
   `voice.json`, not even an earlier pass's, until every scene passes and so
   does the length.
   **On `voice length: fail`**, every scene passed and is cached, but the
   narration runs long or short of the brief. Cut or add words in the scenes
   whose voiced seconds on that line sit furthest from their seconds in
   `script.md`, then compile, run the support check and the script gates, and
   voice again. If that rewrite fails the script's `budget` gate, or a
   rewrite that passes the `budget` gate fails `voice length` again, stop and
   relay the `script budget` line and the latest `voice length` line.
   Exit 1 with no scene lines and no `voice: <vendor> quota reached` (step 5)
   is an input or tool error (an unknown narrator, a scene with no narration,
   a Gemini narrator or own voice with no `GEMINI_API_KEY`, an ElevenLabs
   narrator with no `ELEVENLABS_API_KEY`, an own voice no longer enrolled, a
   failed synthesis): relay the stderr message as printed. Keep the brief's
   narrator: only the user moves `voice`.
5. **On `voice: Gemini quota reached`** (or `ElevenLabs`), the key has hit
   that vendor's limit: a rate or daily limit, or spent credits. The line
   quotes the vendor's own message, and the scenes it counts as kept are
   cached. Relay the line and ask the user to pick one: voice again once the
   quota resets (tomorrow, for a daily quota) or the credits are topped up,
   which voices only the missing scenes; set another key (a paid one, for a
   free-tier limit); or move the brief's `voice` to another narrator.
