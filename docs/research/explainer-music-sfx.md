# Music and sound effects for explainer-video

Research for [#655](https://github.com/Gharib89/skills/issues/655) on the
[explainer-video map](https://github.com/Gharib89/skills/issues/651).

## Answer

Make the default score and every default sound effect **in code**: a
synthesised, instrumental bed built on a beat grid from the storyboard's scene
timings, with hits placed on cue frames, plus a synthesised SFX set. It is the
only route that is commercial-safe for every user with no condition, needs no
GPU and no download, and hits a cue on the exact frame. All three local
baselines did this (motioncraft, anything2explainer, the house pipeline), and
both lab videos shipped with it.

Offer **ACE-Step 1.5** (MIT weights and code, under 4 GB VRAM for its 2B turbo
model, duration, BPM, key and an instrumental flag) as the opt-in "richer
score". Keep the **Stability AI Community License** models (Stable Audio Open,
Stable Audio 3, which has a dedicated SFX model) opt-in only: free commercial
use stops at USD 1M annual revenue and needs registration and a "Powered by
Stability AI" notice. **MusicGen, AudioGen, MAGNeT, AudioLDM2, Tango, TangoFlux
and MMAudio are non-commercial** and stay out of the defaults.

Mix with ducking keyed to the narration's word timings, master to -14 LUFS
integrated and at most -1 dBTP, and **measure the encoded MP4, not the WAV**:
in the lab the AAC encode raised the true peak by 0.7 dB.

## Baselines (the lab)

| | motioncraft | anything2explainer | house pipeline (`ship-explainer-video-v2`) |
|---|---|---|---|
| Music | Pure Node synth, 7 presets (BPM 84 to 112), sections built around a `--drop` second, variety guard across videos | One-off numpy script written for the video: pads, bass pulse at 112 BPM, hits and pings on cue frames | numpy/scipy synth loop `bed.wav`, looped in Remotion |
| SFX | 16 synthesised types in 5 packs, cues from storyboard and timeline events, optional beat snap | Hits, ticks and pings inside the music script | Synthesised whoosh, riser, chime, success, only in silences |
| Ducking | Envelope follower on the VO: bed at -6 dB, a further -7 dB plus a 2.5 kHz dip while speaking | Smoothed voice envelope, about -8 dB while speaking | Per-frame gain curve from sentence timings: 0.06 under voice, 0.14 in gaps, 0.42 on cards |
| Master | Own BS.1770 meter, target -14 LUFS, -1.5 dBTP, soft clip | None (music peak-normalised to -12 dBFS) | Not measured here |
| Review | `mix review` cuts a clip per cue, approval bound to the mix's SHA-256; render refuses audio without it | None | None |
| Licence of the code | MIT | PolyForm Noncommercial 1.0.0 | Owner's own |

Sources: motioncraft `references/music.md`, `references/sfx.md`,
`references/phase2-timeline-audio.md`, `scripts/lib/commands.mjs` (`cmdMix`),
`scripts/lib/dsp.mjs` (`master`), `scripts/lib/phase2.mjs` (`mixReview`, cue
cap); anything2explainer `video/scripts/music.py` and `skill-src/LICENSE`; house
`scripts/gen-music.py`, `src/Mix.tsx` (all documented: read in
`~/wip/projects/video-lab/` and `~/wip/projects/ship-explainer-video-v2`).

Measured with `ffmpeg -af ebur128=peak=true` (ffmpeg 8.0.1):

| File | Integrated | True peak |
|---|---|---|
| motioncraft `out/motioncraft.mp4` (final) | -14.1 LUFS | -2.1 dBTP |
| motioncraft `audio/final.wav` (engine master) | -14.0 LUFS | -1.6 dBTP |
| motioncraft `audio/final_tp.wav` (after the added limiter) | -14.1 LUFS | -2.8 dBTP |
| anything2explainer `out/anything2explainer.mp4` | -15.7 LUFS | -0.9 dBTP |
| anything2explainer voice `audio.wav` / music `music.wav` | -15.6 / -34.2 LUFS | -1.0 / -12.0 dBFS |

What the numbers say:

- The AAC encode moved motioncraft's true peak from -2.8 to -2.1 dBTP (measured,
  rows 1 and 3). A gate on the WAV can pass a file that fails after encoding.
- anything2explainer's final file misses a -1 dBTP ceiling at -0.9 and sits
  1.7 LU under -14 (measured), because it has no master stage (documented:
  `music.py` only peak-normalises the bed).
- anything2explainer's bed is 18.6 LU under the voice on integrated loudness
  (measured; the brief's "about 17 dB" is close). The house pipeline's gain
  0.06 under voice is -24 dB of the bed's own level (inferred from `Mix.tsx`).
  motioncraft's bed lands roughly 11 to 13 dB under the voice during speech
  (inferred from `cmdMix`: a -14 LUFS stem, -6 dB, -7 dB duck, against a
  -15.6 LUFS voice).
- motioncraft's SFX cap: `sfx auto` defaults to 24 cues per minute, a 120 ms gap
  and 550 ms between loud cues, and keeps reveals and transitions over clicks
  when the cap binds (documented: `phase2.mjs`). The lab run's
  `audio/auto-cues.json` holds 30 cues in 57 s, 31.6 per minute (measured), above
  the default's 22 for that length, so the run raised or bypassed it (inferred).
  Its style tokens also carry `sfxPerMinute: [120, 180]` (documented:
  `styles/pi-v2/tokens.json`), which contradicts the 24 cap: pick one number.

## Local music models

Licences read from the Hugging Face API (`curl https://huggingface.co/api/models/<id>`,
field `cardData.license`, measured 2026-10-15) unless noted.

| Model | Weights licence | Commercial-safe default? | VRAM / size | Length, tempo, cues |
|---|---|---|---|---|
| [ACE-Step 1.5](https://huggingface.co/ACE-Step/Ace-Step1.5) (2B turbo DiT + 0.6B LM) | MIT (weights and [code](https://github.com/ace-step/ACE-Step-1.5)) | Yes by licence; data sources unnamed | "less than 4GB"; README tier "6-8GB: 2B turbo + lm-0.6B, pt backend"; "≤6GB: DiT only, INT8 + CPU offload" | 10 s to 600 s; `bpm`, `keyscale`, `timesignature`, `duration`, `instrumental`, `seed`; repaint a section; no frame cues |
| ACE-Step 1.5 XL (4B DiT) | MIT | Same | ≥12 GB with offload and INT8, ≥20 GB recommended | Same |
| [Stable Audio 3](https://github.com/Stability-AI/stable-audio-3) small-music, small-sfx (433M) | Stability AI Community License | Conditional (below) | Peak 1.69 to 2.40 GB (5 s to 120 s); runs on CPU | Up to about 2 min; `duration` conditioning; BPM only as prompt text; inpaint and continue |
| Stable Audio 3 medium (1.4B) | Stability AI Community License | Conditional | Peak 5.07 to 6.52 GB, about 5.14 GB at 120 s with chunked decode | Up to about 4.75 min |
| [Stable Audio Open 1.0](https://huggingface.co/stabilityai/stable-audio-open-1.0) (1B) / [Open Small](https://huggingface.co/stabilityai/stable-audio-open-small) (0.5B) | Stability AI Community License | Conditional | Not stated on card | 47 s / 11 s; card says it is better at SFX than music |
| [Magenta RealTime](https://huggingface.co/google/magenta-realtime) | CC-BY 4.0 weights, Apache 2.0 code | Licence yes | Not stated; runs on free Colab TPUs | 10 s context, 2 s chunks, "doesn't create longer song structures", no BPM control |
| YuE, HeartMuLa 3B, DiffRhythm 1.2 | Apache 2.0 | Licence yes | YuE stage 1 is 7B (from model id) | Song and vocal generators, not beds; DiffRhythm base is tagged `stable-audio-community` too |
| MusicGen small/medium/large, AudioGen, MAGNeT | CC-BY-NC 4.0 | **No** | | |
| AudioLDM2-music, Tango 2 | CC-BY-NC-SA 4.0 | **No** | | |
| [TangoFlux](https://huggingface.co/declare-lab/TangoFlux) | "for non-commercial research use only" (card) | **No** | | |
| MMAudio | CC-BY-NC 4.0 | **No** | | |

Details by source:

- **ACE-Step 1.5** (documented: model card and GitHub README): "You can strictly
  use the generated music for commercial purposes"; trained on "Professionally
  licensed music tracks", "public domain and royalty-free music" and "MIDI-to-Audio"
  synthetic data; "under 10 seconds on an RTX 3090" per song. The `LICENSE` file
  is MIT, "Copyright (c) 2026 ACEStep". The LM models are fine-tunes of Qwen3
  (card table). The GitHub repo had 13,576 stars and a push on 2026-10-11
  (measured: `gh api`). Weights for the 2B DiT are about 4.7 GB (README: "~9GB
  ... vs ~4.7GB for 2B"), which is over this ticket's 1 GB download limit, so
  nothing was run.
- **Stability AI Community License** (documented: `LICENSE.md` in
  `stabilityai/stable-audio-open-1.0`, dated July 5, 2024, and
  [stability.ai/license](https://stability.ai/license)): commercial use is free
  only while "You or Your Affiliate(s) ... generate more than USD $1,000,000 in
  annual revenue" has not happened, counted on the whole organisation's revenue
  "regardless of whether that revenue is generated directly or indirectly" from
  the model; commercial users "must register"; distributing the model or "a
  product or service that uses any portion of them" requires a Notice file and a
  prominent "Powered by Stability AI". Outputs belong to the user "to the extent
  permitted by applicable law". Outputs may not be used to train another
  foundation model. Stable Audio 3 points to the same licence (README
  "License" section, HF tag `stable-audio-community`) and its text encoder is
  T5Gemma, which carries Gemma terms (documented: HF model page,
  `docs/guides/model-overview.md`). Stable Audio 3 training data: 806,284
  AudioSparx files and 472,618 Freesound files under CC0, CC-BY or CC
  Sampling+ (documented: HF model page).
- **Why conditional fails the bar** (inferred): the map says "every shipped
  default is commercial-safe"; a default that terminates for any company over
  USD 1M, and adds a registration and a notice duty to whoever ships a tool
  using it, is not safe for an arbitrary user of a public skill.
- **MusicGen and friends** (documented: HF API): the AudioCraft weights are
  CC-BY-NC 4.0 even though the code is MIT; opt-in only, as the map already
  decides for non-commercial models.

Fit to an explainer (inferred): no model hits a cue on a frame. A model track
needs post-alignment: generate at a BPM whose bar lines land on scene
boundaries, cut or crossfade at bar lines, and overlay code-made hits for the
cues. A model run also contends with the TTS for the one GPU (map: "One GPU job
at a time"), and its output differs per seed, so it needs a listening pass the
synth score does not.

## Sound effects

| Source | Licence | Commercial | Can the skill bundle the files? | Fit |
|---|---|---|---|---|
| Synthesised in code (motioncraft `sfx make`, house `gen-music.py`) | None needed (own code; motioncraft is MIT) | Yes | Yes, it ships code, not audio | Default |
| [Kenney](https://kenney.nl/assets/interface-sounds) audio packs (e.g. Interface Sounds, 100 files) | CC0 | Yes | Yes (CC0) | Good opt-in for UI clicks |
| [Freesound](https://freesound.org/docs/api/resources_apiv2.html) via API | Per sound: CC0, CC-BY, CC-BY-NC | Only with `filter=license:"Creative Commons 0"` (or CC-BY with credits) | No: fetch per run; originals need OAuth2, previews are MP3/OGG | Opt-in search |
| [Sonniss GDC bundle](https://sonniss.com/gdc-bundle-license/) | Royalty-free, no attribution | Yes, "Games, films, videos ... all count" | **No**: may not "distribute ... the sound effects as sound effects", including in a "project template, software development kit" | User-supplied folder only |
| [Pixabay](https://pixabay.com/service/license-summary/) | Pixabay Content License | Yes, no attribution | **No** "Standalone" redistribution | User-supplied only |
| BBC Sound Effects (RemArc) | Personal, educational, research | **No** (secondary sources only) | No | Exclude |
| [Stable Audio 3 small-sfx](https://github.com/Stability-AI/stable-audio-3) | Stability AI Community License | Conditional | Generated per run | Opt-in, CPU-capable |
| [ElevenLabs sound effects](https://elevenlabs.io/docs/overview/capabilities/sound-effects) | Paid API, terms by plan | Not stated on the docs page | Generated per run | Opt-in with a key; 0.1 to 30 s, WAV 48 kHz for non-looping |

Sources: each linked page (documented); Freesound filter values and OAuth rule
from the API v2 resources page; BBC terms from press coverage only (see Thin).

## Loudness and ducking

- Targets: -14 LUFS integrated (±1) and at most -1 dBTP, as motioncraft gates
  them (documented: `references/qa.md`, `qa.mjs`). Measure the final encoded MP4
  with `ebur128=peak=true` (measured above: the AAC encode adds up to 0.7 dB of
  true peak).
- ffmpeg covers every stage with no extra install (documented: `ffmpeg -h
  filter=<name>`, ffmpeg 8.0.1, and the
  [filter docs](https://ffmpeg.org/ffmpeg-filters.html)): `sidechaincompress`
  (main plus sidechain input, threshold, ratio up to 20, attack, release) for
  envelope ducking, `loudnorm` (EBU R128, `I`, `LRA`, `TP`, two-pass
  `measured_*` inputs, `linear`) for the master, `alimiter` (lookahead, sample
  peak, not true peak) as a safety, `ebur128` for the gate.
- Ducking from word timings beats an envelope follower here (inferred): the
  skill already has word-timed captions, so a per-frame gain curve like the
  house `Mix.tsx` (duck a few frames before the first word, recover in gaps,
  swell on cards) is deterministic and lands the duck before the voice, where a
  follower reacts after it. Aim the bed 15 to 20 dB under the voice during
  speech, the range the two baselines that measured well sit in (inferred from
  the table above).
- Keep motioncraft's review gate shape (documented): clips at each cue,
  approval bound to the mix's hash, render refuses an unapproved mix. In
  explainer-video this belongs on the storyboard page rather than a separate
  CLI step (inferred).

## Recommendation

1. **Default score: code-synthesised**, instrumental, on a beat grid derived from
   the storyboard's scene timings, with a few presets and a variety guard. Port
   ideas and, where useful, code from motioncraft (MIT, about 400 lines across
   `music.mjs`, `sfx.mjs`, `dsp.mjs`; keep its copyright notice). Do not copy
   anything2explainer's toolkit code: it is PolyForm Noncommercial.
2. **Default SFX: code-synthesised**, one sound per meaningful visual event,
   placed 1 frame before the visual, with a single cue cap (24 per minute,
   120 ms gap, 550 ms between loud cues) and reveals kept over clicks.
3. **Opt-in richer score: ACE-Step 1.5 2B turbo**, offered at setup with its
   size, run with `instrumental=True`, a BPM chosen so scene boundaries fall on
   bar lines, synth hits overlaid for cues, and never in parallel with TTS on
   the GPU.
4. **Opt-in only, with a licence note at opt-in: Stable Audio 3 and Stable
   Audio Open** (revenue cap, registration, notice), and the non-commercial
   models (MusicGen family, MMAudio, Tango family).
5. **Mix and gate**: duck from word timings, master with two-pass `loudnorm` to
   -14 LUFS and -1 dBTP with headroom for the encode, then gate the encoded MP4
   with `ebur128`; a per-cue listening review on the storyboard page before
   final render.

## Thin

- ACE-Step 1.5 names no training data sources or licensors; "commercial-ready"
  is the authors' claim, with no indemnity in an MIT licence.
- ACE-Step VRAM on this machine's 8 GB card, its output quality as a quiet bed
  under speech, and how well its `bpm` holds: not run (weights over 1 GB, no GPU
  runs allowed).
- Stable Audio 3 VRAM figures are peak allocation on an H200, not on an 8 GB
  consumer card.
- BBC RemArc terms: the official licence page refused the fetch; only press
  coverage was read.
- ElevenLabs commercial rights per plan for sound effects: not on the docs page;
  the music page says "cleared for nearly all commercial uses", varying by plan.
- The house pipeline's final loudness was not measured, and motioncraft's
  ducked bed level during speech is inferred from code, not measured on a stem.
- Why the motioncraft lab run exceeded its own 24 per minute cap is inferred
  from the cue file, not from the session log.
