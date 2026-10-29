# Voice

The shape of `script.json` in the run folder:

```json
{
  "language": "en",
  "narrator": "am_fenrir",
  "scenes": [
    {
      "id": "hook",
      "narration": ["First sentence.", "Second."],
      "cites": [["ex-1"], []],
      "roles": [null, "learner"]
    }
  ]
}
```

`cites` holds one list of excerpt ids per sentence, from `excerpts.json`: the
excerpts a sentence stating a fact stands on, `[]` for a sentence stating none.
The claims check and the gates read it; the voice stage does not, so a
`script.json` the user wrote, voiced alone (SKILL.md's Voice), may carry none.
A video's gates need them.

`narrator` is optional: without it the stage takes the language's first default
in `<skill>/narrators.json` (`af_heart` for `en`, `ar-eg-csagent-2` for `ar`).
Narration is the **spoken form**: write numbers, dates and symbols out as words
("forty two", not "42"), because QC compares the text against what the aligner
hears: a numeral's spoken words match nothing in the text and cost precision.
In Egyptian Arabic narration, keep English terms in Latin letters (`pull
request`); QC spells them in Arabic letters as a speaker says them. An acronym
of more than four capitals QC reads as a word: write it as its letters' names
in Arabic.

`roles` is optional: one role per sentence, like `cites`. `null`, or no `roles`
at all, means `narrator`. Any other role needs `project/kit/cast.json`: per
role a `narrators.json` id per language and the style line it speaks in:

```json
{ "narrator": { "voices": { "en": "af_heart" } },
  "learner": { "voices": { "en": "am_fenrir" }, "style": "a curious student" } }
```

Without `cast.json`, `script.json`'s `narrator` voices every sentence; a
`cast.json` with no `narrator` role keeps that voice for it. Cast only
narrators whose `narrators.json` `rate` is a number; voice refuses a null one.
A role speaks its voice in the script's language, `style` replacing that
narrator's own (Gemini acts it; Kokoro and ElevenLabs ignore it). Each run of
consecutive sentences of one role is voiced in its voice, the runs one after
another, never overlapping; `voice.json` records each sentence's role
(`roles`), and captions name a new one.

1. **Tools.** Voice needs the npm packages and its narrator's rows: English
   `model:kokoro-82m` and `model:wav2vec2-base-960h`, plus `onnx-cuda` where
   setup lists it; Egyptian Arabic
   `model:egyptian-arabic-wav2vec2` and `key:gemini`; an ElevenLabs narrator
   `key:elevenlabs` and `model:wav2vec2-base-960h`. First run the setup
   check with `--voice` set to the narrator this stage uses (`narrator`, else
   the language's default above), then once per other voice `cast.json`
   names; any row missing, run SKILL.md's Setup steps before voicing.
2. **Voice.** `node <skill>/scripts/voice/voice.mjs creative-videos/<slug>`.
   It prints one line per scene, `voice <id>: voiced|cached · recall ·
   precision · rate · pass|fail: <why>`, a failing one ending in `heard:
   <file>`, then a summary line. A scene whose narration, voices, styles and
   language are unchanged is a cache hit and is not voiced again. Once every
   scene passes, with a `brief.json` in the run folder, a `voice length:
   pass|fail` line follows the scene lines: the scenes' total voiced seconds,
   then each scene's, and whether they plus the one-second closing hold land
   within 10 percent of `brief.json`'s `length`, in minutes.
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
   whose voiced seconds on that line run furthest over or under their share of
   the length, and voice again. If the rewrite fails `voice length` again,
   stop and relay the latest `voice length` line.
   Exit 1 with no scene lines and no `voice: <vendor> quota reached` (step 5)
   is an input or tool error (an unknown narrator, a scene with no narration,
   a Gemini narrator with no `GEMINI_API_KEY`, an ElevenLabs narrator with no
   `ELEVENLABS_API_KEY`, a failed synthesis): relay the stderr message as
   printed. Only the user changes a narrator (`script.json`, `cast.json`).
5. **On `voice: Gemini quota reached`** (or `ElevenLabs`), the key has hit
   that vendor's limit: a rate or daily limit, or spent credits. The line
   quotes the vendor's own message, and the scenes it counts as kept are
   cached. Relay the line and ask the user to pick one: voice again once the
   quota resets (tomorrow, for a daily quota) or the credits are topped up,
   which voices only the missing scenes; set another key (a paid one, for a
   free-tier limit); or change the narrator (`script.json`, `cast.json`).
