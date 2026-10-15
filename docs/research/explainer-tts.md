# TTS for explainer-video: English and Egyptian Arabic voices

Research for [#654](https://github.com/Gharib89/skills/issues/654) on the
[explainer-video map](https://github.com/Gharib89/skills/issues/651).
Each claim carries its basis: **measured** (a command run here, named),
**documented** (a primary source, linked) or **inferred**.

## Answer

- **English is solved locally and commercial-safe.** Kokoro-82M (Apache-2.0
  code and weights, 54 stock voices, runs on CPU) and Supertonic 3 (MIT code,
  OpenRAIL-M weights, 5 female and 5 male presets, CPU) give stock female and
  male voices with no GPU. Word timing comes from the house aligner
  (Qwen3-ForcedAligner-0.6B, Apache-2.0), which covers English.
- **Egyptian Arabic has no local default that is commercial-safe, has stock
  voices and documents Egyptian dialect, all at once.** The local models that
  name Egyptian either carry non-commercial weights (OmniVoice, the model
  VoiceStudio runs: CC-BY-NC), or need a reference clip to clone (Habibi-TTS EGY,
  Apache-2.0; Chatterbox fine-tunes, MIT), and cloning is opt-in on the map.
  Supertonic 3 has stock voices and Arabic but does not say which variety.
- **The Egyptian route with stock voices, code-switching and timing is an
  API:** ElevenLabs (Egyptian-accent community voices, character-level
  timestamps from `/with-timestamps`), Azure Speech `ar-EG-SalmaNeural` /
  `ar-EG-ShakirNeural` (the supported product behind edge-tts, with word
  boundary events), or Gemini TTS `ar-EG` (GA, 30 voices, no timestamps
  documented).
- **Alignment for Egyptian Arabic with English terms is the gap.** The house
  aligner (Qwen3-ForcedAligner-0.6B) does not support Arabic. The
  commercial-safe local fallback is faster-whisper word timestamps (MIT code,
  Whisper weights MIT / Apache-2.0) mapped back onto the known script; the
  mixed-script forced aligners (MMS_FA, ctc-forced-aligner's default model)
  have CC-BY-NC weights.
- **Code-switching is documented almost nowhere.** No source below publishes a
  measure for an Egyptian Arabic sentence with an English technical term,
  except one community Higgs fine-tune, which calls its own score an artifact.
  The blind listening page must test it with a code-switched sentence.

## The machine and the lab baselines

| Fact | Basis |
|---|---|
| VoiceStudio is AGPL-3.0 (commercial licence on request), wraps `k2-fsa/OmniVoice` as its one required TTS model, 2.4 GB | measured: `~/.config/VoiceStudio/runtime/project/{LICENSE,pyproject.toml,backend/config/models.yaml}` |
| OmniVoice: code Apache-2.0, **weights CC-BY-NC** "due to constraints from its training data (e.g., Emilia)"; language list includes `arb` and `arz` (Egyptian) among 646; base model Qwen3-0.6B | measured: local model card, `~/.cache/huggingface/hub/models--k2-fsa--OmniVoice/.../README.md` (License section, lines 781 to 783); [HF card](https://huggingface.co/k2-fsa/OmniVoice) |
| VoiceStudio's `pyproject.toml` says the bundled model "remains Apache-2.0 upstream": that is the code; the weights are CC-BY-NC | measured, both files above |
| OmniVoice voice design "is trained on Chinese and English data only" and may be unstable elsewhere; cloning is the stable mode; RTF as low as 0.025 (H100) | documented: [OmniVoice README](https://github.com/k2-fsa/OmniVoice) |
| VoiceStudio also ships optional engines: VoxCPM2, CosyVoice 3, MOSS-TTS-Nano, KittenTTS, GPT-SoVITS, audio.cpp (Breeze-TTS-2, research/non-commercial) | measured: `models.yaml` |
| House pipeline narrates with OmniVoice cloning a designed reference clip, fixed seed, through VoiceStudio's `/generate` | measured: `ship-explainer-video-v2/scripts/tts.sh` |
| House pipeline aligns words with `qwen-asr==0.0.6` and Qwen3-ForcedAligner-0.6B, fp16, peak near 2.3 GB, first-word onset corrected from the waveform | measured: `ship-explainer-video-v2/scripts/align-words.py` header |
| The 8 GB card needs `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` for VoiceStudio | lab fact from the map |
| anything2explainer: English default kokoro-82m `am_liam`, Chinese default edge-tts `zh-CN-YunxiNeural` (a Microsoft online endpoint, pinned at 7.2.8 because it "breaks across upgrades") | measured: `video-lab/anything2explainer/skill-src/README.md` |
| motioncraft: word timings from faster-whisper, pauses as fallback when Whisper is absent | measured: `video-lab/motioncraft/motioncraft-repo/README.md` |
| edge-tts uses "Microsoft Edge's online text-to-speech service"; custom SSML removed because Microsoft blocks it | documented: [edge-tts README](https://github.com/rany2/edge-tts) |

## Local models

Licence columns: code and weights separately. "Safe" means a permissive
licence with no non-commercial clause. VRAM is for the 8 GB card.

| Model | Code | Weights | Arabic / Egyptian | Stock voices | VRAM, speed | Sources |
|---|---|---|---|---|---|---|
| **OmniVoice** (VoiceStudio) | Apache-2.0 (VoiceStudio wrapper AGPL-3.0) | **CC-BY-NC** | `arb`, `arz` listed | none: clone or design (design untrained for Arabic) | runs on this card (measured: house pipeline); RTF 0.025 on H100 | above |
| **Chatterbox Multilingual V3** | MIT | MIT | `ar` (one of 23); no Egyptian pack (packs: zh, es, pt, hi) | one built-in conditioning; otherwise clone | 0.5B, fits (inferred); PerTh watermark on every output | [card](https://huggingface.co/ResembleAI/chatterbox) |
| Chatterbox Turbo | MIT | MIT | English only | as above | cached locally, 3.8 GB on disk (measured: `du`) | [HF API](https://huggingface.co/api/models/ResembleAI/chatterbox-turbo) |
| **Kokoro-82M** | Apache-2.0 | Apache-2.0 | none | 54 voices, 8 languages; English grades: `af_bella` A-, `af_nicole` B-, `bf_emma` B-, `am_michael`/`am_fenrir`/`am_puck` C+, `am_liam` (lab default) D | CPU | [card](https://huggingface.co/hexgrad/Kokoro-82M), [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) |
| **Supertonic 3** | MIT (sample code) | **OpenRAIL-M** (commercial allowed, use-based restrictions) | `ar` (one of 31); variety not stated | **F1 to F5, M1 to M5** presets | ~99M params, ONNX, CPU | [card](https://huggingface.co/Supertone/supertonic-3), its LICENSE |
| **Habibi-TTS** (F5-TTS architecture) | MIT | **EGY, MSA, ALG, IRQ, MAR: Apache-2.0**; Unified, SAU, UAE: CC-BY-NC-SA-4.0 | dedicated **Egyptian** specialised model; "highly competitive with ElevenLabs' Eleven v3 (alpha)" | none: needs a reference clip; its own EGY example prompt is an ElevenLabs library voice, so it cannot ship as a stock voice | F5 class, fits (inferred) | [card](https://huggingface.co/SWivid/Habibi-TTS), [repo](https://github.com/SWivid/Habibi-TTS), [assets README](https://github.com/SWivid/Habibi-TTS/blob/main/src/habibi_tts/assets/README.md), [arXiv 2601.13802](https://arxiv.org/abs/2601.13802) |
| F5-TTS base | MIT | CC-BY-NC-4.0 | none | clone only | fits (inferred) | [HF](https://huggingface.co/SWivid/F5-TTS) |
| XTTS-v2 | MPL-2.0 (idiap fork maintained) | Coqui Public Model License (non-commercial) | `ar` | clone | fits (inferred) | [card](https://huggingface.co/coqui/XTTS-v2) |
| Piper | GPL-3.0 (`piper1-gpl`; old `rhasspy/piper` MIT, archived) | voices MIT repo tag, per-voice dataset licence | one Arabic voice, `ar_JO-kareem` (Jordanian, male) | 1 Arabic male | CPU | [voices](https://huggingface.co/rhasspy/piper-voices), kareem MODEL_CARD |
| Fish Audio S2 Pro | not asserted on GitHub | Fish Audio Research License (non-commercial) | `ar` tier 2 | clone | 4B + 0.4B, too big for 8 GB (inferred) | [card](https://huggingface.co/fishaudio/s2-pro) |
| Orpheus 3B | Apache-2.0 | Apache-2.0 (gated) | English | 8 named | 3B, tight (inferred) | [HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft) |
| Dia / Dia2 | Apache-2.0 | Apache-2.0 | English | none | | [HF](https://huggingface.co/nari-labs/Dia2-2B) |
| Higgs TTS 3 (4B) | Apache-2.0 (v2 repo) | Boson research and non-commercial licence plus a **Creator Use Grant**: monetised videos allowed if "Boson AI's Higgs Audio" is credited; products and hosted APIs need a licence | Arabic listed with the Egyptian flag | clone | 4B, over 8 GB in bf16 (inferred) | [card](https://huggingface.co/bosonai/higgs-tts-3-4b) |
| VoxCPM2 | Apache-2.0 | Apache-2.0 | `ar` (one of 30) | voice design, clone | "~8 GB" VRAM: no headroom on this card | [card](https://huggingface.co/openbmb/VoxCPM2) |
| MOSS-TTS-Nano 100M | Apache-2.0 | Apache-2.0 tag (card says the repo LICENSE governs) | `ar` | clone | CPU | [card](https://huggingface.co/OpenMOSS-Team/MOSS-TTS-Nano-100M) |
| OuteTTS 1.0 1B | | CC-BY-NC-SA-4.0 | `ar` | | | [HF](https://huggingface.co/OuteAI/Llama-OuteTTS-1.0-1B) |
| Qwen3-TTS, CosyVoice 3, IndexTTS-2, VibeVoice, Kitten, Pocket TTS | various permissive | various | **no Arabic** | | | HF API language lists |

Egyptian community fine-tunes (all inferred quality, none code-switch tested
except the Higgs one):

| Model | Base | Licence | Note |
|---|---|---|---|
| [NAMAA-Space/NAMAA-Egyptian-TTS](https://huggingface.co/NAMAA-Space/NAMAA-Egyptian-TTS) | Chatterbox Multilingual | MIT ("research and commercial") | training data not stated; known misses on ق and numbers |
| [oddadmix/chatterbox-egyptian-v0](https://huggingface.co/oddadmix/chatterbox-egyptian-v0) | Chatterbox | MIT | "no speaker identity guarantees" |
| [AliAbdallah/egyptian-arabic-tts-chatterbox](https://huggingface.co/AliAbdallah/egyptian-arabic-tts-chatterbox) | Chatterbox Multilingual | Apache-2.0 | single speaker, 120 h, partial epoch |
| [itshamdi404/Egy_Arabic_Qwen3-TTS-12Hz-1.7B-Base](https://huggingface.co/itshamdi404/Egy_Arabic_Qwen3-TTS-12Hz-1.7B-Base) | Qwen3-TTS 1.7B | Apache-2.0 | one built-in `egyptian_speaker` (a stock voice), 25 h, data source not stated |
| [ehabnegm/lahgtna-omnivoice-egyptian-v3](https://huggingface.co/ehabnegm/lahgtna-omnivoice-egyptian-v3) | OmniVoice | Apache-2.0 tag, but inherits CC-BY-NC base; YouTube data, "get permission before commercial use" | "Code-switched English is not trained (strip/transliterate it)" |
| [ehabnegm/masri-higgs-v3-egyptian-tts](https://huggingface.co/ehabnegm/masri-higgs-v3-egyptian-tts) | Higgs TTS 3 | Higgs licence | 98 h; reports a code-switch score of 0.558 and calls it an ASR artifact |
| [MAdel121/f5-tts-egyptian-arabic](https://huggingface.co/MAdel121/f5-tts-egyptian-arabic) | Habibi EGY | CC-BY-NC-4.0 (its own claim; Habibi EGY itself is Apache-2.0) | 16 h |

## APIs

| API | Egyptian Arabic | English terms inline | Timing | Commercial terms | Sources |
|---|---|---|---|---|---|
| **ElevenLabs** | Models list "Arabic (ar)" only (v2: "Saudi Arabia, UAE"); Egyptian comes from **community voices tagged accent `egyptian`**, filterable by `language`, `accent`, `gender` on `GET /v1/shared-voices`; ElevenLabs advertises "multiple Egyptian-accented options" | not documented for Arabic; voices are "verified" per language | **`POST /v1/text-to-speech/{voice_id}/with-timestamps`**: `alignment` and `normalized_alignment`, each `characters` with start and end seconds: **character level, not word level** (words rebuilt by splitting on spaces, inferred) | paid plans include a commercial licence; free plan is non-commercial and must credit "elevenlabs.io"; Beta services excluded | [models](https://elevenlabs.io/docs/overview/models), [with-timestamps](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps), [shared voices](https://elevenlabs.io/docs/api-reference/voices/voice-library/get-shared), [Egyptian accent](https://elevenlabs.io/blog/egyptian-accent-text-to-speech), [publishing terms](https://elevenlabs.io/docs/help-center/legal/can-i-publish-the-content-i-generate-on-the-platform) |
| **Azure Speech** | `ar-EG-SalmaNeural` (F), `ar-EG-ShakirNeural` (M), visemes for `ar-EG` | not documented for `ar-EG` voices; multilingual voices switch language per `<lang>` | SDK `WordBoundary` events | paid Azure service | [language support](https://learn.microsoft.com/azure/ai-services/speech-service/language-support?tabs=tts), [synthesizer events](https://learn.microsoft.com/azure/ai-services/speech-service/how-to-speech-synthesis#subscribe-to-synthesizer-events) |
| **Google Gemini TTS** (Cloud TTS) | **`ar-EG` GA** (`ar-001` preview); 30 voices, 14 F and 16 M | prompt-steerable (inferred) | none documented: needs the local aligner | paid Google Cloud | [Gemini-TTS](https://docs.cloud.google.com/text-to-speech/docs/gemini-tts) |
| edge-tts | same Azure `ar-EG` voices | | word boundaries | unofficial endpoint, not a supported API | [edge-tts](https://github.com/rany2/edge-tts) |

ElevenLabs Egyptian voice IDs (from third-party listings; the shared-voices
filter answered `"You must be logged in to use filters."` without a key, so
these need a keyed `GET /v1/shared-voices?language=ar&accent=egyptian` to
confirm; measured with `curl`): female **Fatima, Expressive Egyptian**
`I3u6waC588j43py1kDN2`, **Heba** `JHdGl5PsEzushIzzVSd1`, also Hoda, Salma
(IDs unconfirmed); male **Masry** `LXrTqFIgiubkrMkwvOUr`, **Mamdoh**
`68MRVrnQAt8vLbu0FCzw`, **Haytham, the storyteller** `wxweiHvoC2r2jFM7mS8b`,
**Abdullah** `ocqVw6LVSdCxCra4XhMH`, **Hammam** `VxSsN5NGusWQZXue7VE9`
([json2video Arabic listing](https://json2video.com/ai-voices/elevenlabs/languages/arabic/),
[Masry](https://json2video.com/ai-voices/elevenlabs/voices/LXrTqFIgiubkrMkwvOUr/)).

## Word timing for Egyptian Arabic with English terms

| Route | Arabic | Mixed script | Licence | Note |
|---|---|---|---|---|
| Qwen3-ForcedAligner-0.6B (house) | **no**: 11 languages, no Arabic | no | Apache-2.0 | [card](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B); Qwen3-ASR does transcribe `ar`, but its timestamps come from this aligner |
| faster-whisper `word_timestamps=True` + map to the known script (the house `marks()` approach) | yes (Whisper large-v3, or the code-switched Egyptian whisper-small) | yes, Whisper writes both scripts | code MIT; Whisper weights MIT / Apache-2.0; [code-switched Egyptian whisper-small](https://huggingface.co/IbrahimAmin/code-switched-egyptian-arabic-whisper-small) Apache-2.0, already cached here (925 MB, measured: `du`) | **commercial-safe default** (inferred: accuracy for short English terms untested); [faster-whisper](https://github.com/SYSTRAN/faster-whisper) |
| WhisperX wav2vec2 alignment | yes: default `ar` model `jonatasgrosman/wav2vec2-large-xlsr-53-arabic` (Apache-2.0) | no: an Arabic-letter CTC vocabulary cannot place Latin words (inferred) | BSD-2-Clause | [alignment.py](https://github.com/m-bain/whisperX/blob/main/whisperx/alignment.py) |
| ctc-forced-aligner / torchaudio `MMS_FA` | yes, 1,130 languages, `--romanize` | yes, via romanisation | code BSD-2-Clause; **weights CC-BY-NC-4.0** | opt-in only; [ctc-forced-aligner](https://github.com/MahmoudAshraf97/ctc-forced-aligner), [MMS_FA](https://docs.pytorch.org/audio/stable/generated/torchaudio.pipelines.MMS_FA.html) |
| API-native | ElevenLabs character timing, Azure word boundaries | yes | API terms | no aligner needed |

## Recommendation

1. **English default:** Kokoro-82M (best graded stock voices, Apache-2.0,
   CPU), Supertonic 3 as the second local family; Qwen3-ForcedAligner for
   timing as today.
2. **Egyptian Arabic:** treat a local default as unsettled until the blind
   page rules. Shortlisted local options, all commercial-safe:
   Supertonic 3 (stock, variety unknown) and Habibi-TTS EGY or a Chatterbox
   Egyptian fine-tune with a **consenting speaker's clip** (clone, so
   opt-in). When local fails the page, suggest **ElevenLabs** (Egyptian
   voices, character timing) or **Azure `ar-EG`** (supported, word
   boundaries). OmniVoice stays opt-in (CC-BY-NC).
3. **Alignment adapter:** one interface, three sources: API timing when the
   provider returns it, Qwen3-ForcedAligner for English, faster-whisper word
   timestamps mapped to the script for Arabic. MMS-based alignment only
   opt-in.
4. **Blind page test text:** one Egyptian sentence with inline English terms
   (for example "لما تعمل `git rebase` على الـ`branch` بتاعك، الـ`pull request`
   بيتحدث لوحده") plus one English sentence, so code-switching is judged by ear.

### Shortlist for the blind listening page

Safe = commercial-safe default candidate; Opt-in = non-commercial or
licence-conditioned; API = needs a key and a paid plan for commercial use.

**English, female**
1. Kokoro `af_bella` (Safe)
2. Kokoro `bf_emma` (Safe)
3. Supertonic 3 `F1` to `F5`, best one picked first (Safe, OpenRAIL-M)
4. OmniVoice house "teacher" voice, `voice/teacher-ref-v2.wav` (Opt-in, CC-BY-NC)

**English, male**
1. Kokoro `am_michael` (Safe)
2. Kokoro `am_fenrir` (Safe)
3. Supertonic 3 `M1` to `M5`, best one picked first (Safe, OpenRAIL-M)
4. ElevenLabs premade male voice (API)

**Egyptian Arabic, female**
1. Supertonic 3 best `F` preset, `lang=ar` (Safe, stock)
2. Azure `ar-EG-SalmaNeural` (API)
3. ElevenLabs Fatima, Expressive Egyptian `I3u6waC588j43py1kDN2` (API)
4. OmniVoice `arz` cloning a consenting female clip (Opt-in, CC-BY-NC)

**Egyptian Arabic, male**
1. Habibi-TTS EGY (Apache-2.0) cloning a consenting male clip (Safe weights, clone opt-in)
2. Azure `ar-EG-ShakirNeural` (API)
3. ElevenLabs Masry `LXrTqFIgiubkrMkwvOUr` (API)
4. Supertonic 3 best `M` preset, `lang=ar` (Safe, stock)

Gemini TTS `ar-EG` is the reserve API pair if Azure or ElevenLabs fail the
page; it needs the local aligner.

## Thin

- No Egyptian or code-switching quality was heard or measured: every quality
  statement above is the vendor's or inferred. The blind page is the test.
- Supertonic 3 does not say whether its Arabic is MSA or a dialect.
- ElevenLabs Egyptian voice IDs come from third-party listings; the filtered
  shared-voices API needs a key (measured). Their `free_users_allowed` and
  `notice_period` are unchecked.
- VRAM for Chatterbox Multilingual, Habibi, Higgs TTS 3 and Fish S2 Pro is
  inferred from parameter counts; nothing ran on the GPU.
- Azure `ar-EG` handling of inline English words is undocumented.
- Faster-whisper word-timestamp accuracy on short English terms inside
  Egyptian speech is untested.
- Training-data provenance of the Egyptian community fine-tunes (NAMAA, the
  Qwen3-TTS one) is not stated, which weakens their commercial safety despite
  permissive tags.
