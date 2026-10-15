# Narration is voiced per scene and timed by one aligner per language

`explainer-video` caches narration per scene, not per sentence as the house pipeline did: a run's first synthesis sends the whole narration to the narrator in one call and splits the audio into scene cache entries at the aligner's sentence times, and every later re-voicing (a revised scene, a voice-QC retry) is one call per changed scene. A narrator adapter returns audio only; word timings always come from one CTC aligner per language, run in Node, whose greedy transcript also feeds voice QC. Gemini's free tier allows 10 TTS requests a day (measured on #684), so a per-sentence call (about 50 for a five-minute video) could never finish a run on a free key, and Gemini returns no timings (measured on #663), so an aligner exists anyway.

## Considered Options

- One call and one cache entry per sentence (the house shape): finest re-voicing, but no free key finishes a run.
- One call per scene from the start: about 8 calls for a fresh run, leaving little room for revisions under the daily cap.
- Adapters return their own timings where the backend has them (Kokoro, ElevenLabs): two timing paths per language, so captions and the caption gate would behave differently by narrator.

## Consequences

- Editing one sentence on the storyboard re-voices its whole scene; prosody stays even across the scene, and a Kokoro scene costs seconds on CPU.
- The voice cache key is (scene narration, narrator, language), plus the clip's hash for own voice. This replaces the per-sentence voice key set on #682.
- A quota stop (HTTP 429) keeps every finished scene; a resumed run voices only the missing ones.
- The house LEAD, GAP and TAIL spacing still applies, since sentence times come from the aligner.
