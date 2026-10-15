# Egyptian Arabic narrates through Gemini by key

`explainer-video` runs locally by default, but its default Egyptian Arabic narrators are Gemini 3.8 TTS voices (`ar-eg-csagent-2` female, `ar-eg-commercial-11` male), reached with the user's `GEMINI_API_KEY`. In the owner's blind listening test (2026-10-15) no commercial-safe local voice passed for Egyptian Arabic with English terms: Supertonic 3, the one local stock voice, failed, and so did Azure `ar-EG`; the local Egyptian models that are commercial-safe (Habibi-TTS EGY, Chatterbox fine-tunes) only clone a consenting speaker's clip; OmniVoice failed and its weights are CC-BY-NC; ElevenLabs' Egyptian voices are library voices its API refuses on the free tier. English keeps local Kokoro narrators.

## Consequences

- An Arabic run with no key stops at the first-run setup check, which names the key and where to get a free one; the user can instead ask in the brief for another narrator, local ones included. No silent fallback.
- The script leaves the machine: setup warns once that free-tier keys let Google use and human-review it, and the storyboard's brief shows the narrator as sent to Google.
- A key never switches a narrator by itself: Gemini English and ElevenLabs are used only when the brief names them.
- Gemini returns no timestamps, so Arabic word timing comes from a local aligner run on the audio.
