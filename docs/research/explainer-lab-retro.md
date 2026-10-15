# Video lab retrospective: what `explainer-video` should adopt

Research for [#652](https://github.com/Gharib89/skills/issues/652), on the map [#651](https://github.com/Gharib89/skills/issues/651).

**Answer.** Build on the house pipeline's shape (per-sentence voice cache, a timeline file of sentence and word times that drives every reveal, a DOM layout probe, a contrast gate, contact sheets, an independent critic) and add three things the lab proved: motioncraft's `brief.json` and `storyboard.json` with one preview still per scene, a procedurally synthesized score, and an audio path that never stream-copies AAC across cuts. Two of the house pipeline's own parts fail the map's commercial-safe rule and must not be defaults: its voice (OmniVoice weights are CC-BY-NC) and, for larger companies, Remotion itself (company licence above 3 employees). anything2explainer's code is PolyForm Noncommercial: take ideas only.

Labels: **measured** (a command I ran, named), **documented** (a primary file or licence, cited by path or URL), **reported** (the lab session's own final report, read from its transcript), **inferred** (my reasoning from the above).

## Method

- Session reports: the last assistant messages holding "Verdict" or "Deviations" in each `~/.claude/projects/-home-ribo-wip-projects-video-lab-<name>/*.jsonl`, and the house session `~/.claude/projects/-home-ribo-wip-projects-ship-explainer-video-v2/7499cae8-....jsonl`, extracted with a small JSON reader.
- Outputs: `ffprobe -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate` on every `out/<name>.mp4`. Nothing was rendered or played.
- Licences: the `LICENSE` files in each vendored repo, `node_modules/remotion/LICENSE.md`, the cached Hugging Face model cards, and `https://huggingface.co/api/models/<id>` and `https://api.github.com/repos/<repo>` licence fields.

## Per-run findings

All ten outputs are h264 1920x1080 with AAC (measured, ffprobe). Render cost is the final full render's wall time from each report (reported); the ratio is render seconds per video second (inferred).

| Run | Length, size (measured) | Render (reported) | Ratio |
|---|---|---|---|
| article-highlights | 63.9 s, 20.0 MB, 30 fps | 28 s (28 to 47 over 6 renders) | 0.44 |
| video-use | 69.1 s, 37.9 MB, 24 fps | 91.5 s (86 to 147) | 1.33 |
| remotion-saas | 61.0 s, 18.2 MB, 30 fps | 26.6 s, concurrency 6 | 0.44 |
| remotion-markup | 62.0 s, 18.9 MB, 30 fps | 33 s, concurrency 6 | 0.53 |
| remotion-interactivity | 71.0 s, 20.9 MB, 30 fps | 29.6 s, concurrency 6 | 0.42 |
| remotion-maps | 70.0 s, 20.5 MB, 30 fps | 200 s (264 first), concurrency 6 | 2.86 |
| manim | 62.5 s, 6.5 MB, 60 fps | 71 to 133 s, plus 60 s voice once | 1.1 to 2.1 |
| hyperframes | 60.0 s, 101.2 MB, 30 fps | 94.3 s, 3 workers, 0.8 GB RSS | 1.57 |
| motioncraft | 57.0 s, 20.1 MB, 30 fps | 56.7 s, plus 121 s 3D pre-render and 20 s mux | 3.47 all in |
| anything2explainer | 61.1 s, 15.1 MB, 30 fps | 63 s, concurrency 3 | 1.03 |
| house `showcase.mp4` | 62.6 s, 12.1 MB | 35.44 s | 0.57 |

### article-highlights (Remotion, `liamrjohnston/remotion-motion-graphics-skill`, MIT)

- **Did well** (reported): a research gate made every on-screen string traceable; an independent reviewer caught a cropped overview and an overflowing quote the builder missed; final critic mean 8.63 against an 8.5 pass mark.
- **Did badly** (reported): the approval gate only accepts a 2 to 15 s candidate, so a 15 s excerpt stood in for a 64 s video. Confirmed in source: `promptible-gate.mjs` dies with `--duration must be 2–15 seconds` (documented, `.claude/skills/motion-graphics/scripts/promptible-gate.mjs` line 39). Its intake asks questions even when choices are delegated; its recommended highlighter breaks under a moving camera; reviewers disagreed between rounds 1 and 2.
- **Reusable**: the critic brief's hard-failure list and score keys (`references/visual-critic.md`), MIT (measured, GitHub API licence field `MIT`).

### video-use (`browser-use/video-use`, MIT)

- **Did well** (reported): hard rules (subtitles last, overlays shifted to start time, fades at every cut) prevented real mistakes; parallel animation agents built 5 cards at once; sync verified at 0 ms on 23 lines and 26 cuts by cross-correlation and scene detection.
- **Did badly**: audio drifts about 21 ms per cut, 250 ms by 23 s (reported, measured by cross-correlation). Root cause confirmed in source: each segment is encoded to AAC on its own (`helpers/render.py` lines 294 to 296) and then joined with the concat demuxer and `-c copy` (lines 371 to 381) (documented, commit `9575612`). 21 ms is 1024 samples at 48 kHz, the AAC encoder's priming delay per segment (inferred). It also needs a paid ElevenLabs key for transcription by default, allows one grade per edit, and its phrase grouping breaks on whisper timings (reported).
- **Reusable**: the lab's fix, decoding each clip's audio and `apad,atrim` to exact length before one AAC encode (`video-use/scripts/render_trailer.py` line 156, measured by grep). Picture drift fix: pick an fps where the beat grid is whole frames (0.25 s at 24 fps is 6 frames; at 30 fps it is 7.5) (reported).

### remotion-saas (Remotion skill `remotion-best-practices`)

- **Did well** (reported): fastest render in the lab (26.6 s for 61 s); contact sheets plus exact-frame grabs at cuts caught four bugs, including animations visible before their start frame.
- **Did badly** (reported): the SaaS reference is thin; it omits serving `public/` outside Remotion's bundler and the Player's `acknowledgeRemotionLicense` prop; its 150 px headline minimum is a phone rule, wrong for 16:9 desktop.
- **Reusable**: the Vite plus `@remotion/player` preview page with chapter seek (`remotion-saas/player/`), a candidate for the storyboard page's inline preview (inferred).

### remotion-markup

- **Did well** (reported): transitions, light leaks, rough-notation, Lottie and `@remotion/three` worked first time; frame-number-driven animation kept picture locked to music.
- **Did badly**: `HtmlInCanvasMotionBlur` crashes at `samples >= 2` with `captureElementImage: No cached paint record for element` on every GL backend (reported, probe composition). The version is 4.0.535 for every `@remotion/*` package (measured, `package.json` and `node_modules/@remotion/motion-blur/package.json`). The call site is `@remotion/motion-blur/dist/cjs/HtmlInCanvasMotionBlur.js` line 91 (measured, grep). `CameraMotionBlur` works. `visualizeAudio()` needs log-scale resampling to be usable.
- **Reusable**: the log-scale spectrum hook `src/useSpectrum.ts` (project code, no third-party licence).

### remotion-interactivity

- **Did well** (reported): Studio edits write back to source (font size change rewrote `ClockScene.tsx:134`); a `dataFile` prop plus `calculateMetadata` made one composition render any repo's stats, proven with a second repo.
- **Did badly** (reported): Studio-editability rules fight data-driven loops; `AbsoluteFill` forces `width: 100%`, breaking `left`/`right` boxes; `defaultProps` must be inline.
- **Reusable**: the props-driven pattern (scene data in a JSON file read by `calculateMetadata`), which is how a storyboard revision can re-render one scene without code edits (inferred). `scripts/extract.py` (150 lines) is a repo-to-JSON extractor for the "repo" source kind.

### remotion-maps (MapLibre plus Turf)

- **Did well** (reported): keyless 3D terrain, globe and pitch rendered stable; the skill's "wait for the map to load each frame" pattern works.
- **Did badly** (reported): headless Chrome aborted tile downloads (`ERR_NETWORK_CHANGED`, 88 failures in 140 frames); slowest render in the lab (2.86x real time); the skill wrongly says MapLibre has no terrain or pitch.
- **Reusable**: `scripts/tile-proxy.mjs` (58 lines, a local caching tile proxy) plus in-page retries took failures to zero (reported). Map tiles carry their own terms (OpenFreeMap, AWS Terrarium, Esri World Imagery), credited on screen; I did not verify commercial terms (see Thin).

### manim (Manim CE, MIT; `adithya-s-k/manim_skill`, MIT)

- **Did well** (reported): visuals computed from a simulation of git's real algorithm, not keyframed; manim-voiceover bookmarks fired 14 of 15 on time, one 0.03 s late; voice generated once and cached.
- **Did badly** (reported): `pycairo` and `manimpango` needed an apt install (no Linux wheels); `ease_in_out_cubic` not exported; `wait(0)` throws; the skill is a shallow API digest that tells the agent to interview the user.
- **Reusable**: `voicestudio_service.py` (93 lines), a manim-voiceover SpeechService that gets word timings from the TTS server's own transcription endpoint instead of installing whisper. Licences: Manim MIT (measured, GitHub API), `manim_skill` MIT (measured, `vendor/manim_skill/LICENSE`).

### hyperframes (`heygen-com/hyperframes`, Apache-2.0)

- **Did well** (reported): plain HTML plus GSAP is fast to write; `snapshot` takes about 17 s; `lint` and `check` give specific findings with fixes; `hyperframes beats` measured 117 of 119 cuts on the grid, median error 4 ms; deterministic renders.
- **Did badly**:
  - `check` flags outlined text (transparent fill plus `-webkit-text-stroke`) as invisible with no opt-out (reported). Confirmed in source: `invisibleTextIssue` reads only `webkitTextFillColor || color` and returns an issue when its alpha is at most 0.05, and the file never mentions text stroke (measured, `grep text-stroke` on `node_modules/hyperframes/dist/commands/layout-audit.browser.js` returns nothing, function at lines 1349 to 1365).
  - `init` installed its skills into 7 user-level agent folders without asking (reported); the session's backup holds exactly 7 (measured, `ls vendor/global-skills-backup`: agents, claude, copilot, gemini, gemini-antigravity-cli, hermes, junie).
  - `snapshot` sends frames to Gemini whenever `GEMINI_API_KEY` is set (reported).
  - Built-in music is MusicGen on CPU, capped at 30 s; the session used MusicGen-small, whose weights are CC-BY-NC-4.0 (measured, HF API licence field).
  - Largest file in the lab: 101.2 MB for 60 s (measured), about 5x the Remotion runs.
- **Reusable**: the engine, Apache-2.0 (measured, `vendor/hyperframes/LICENSE`); the idea of a beat-alignment report.

### motioncraft (`ahmdd4vd/MotionCraft`, MIT)

- **Did well** (reported): code-synthesized music, beat grid and SFX gave a coherent on-beat score with no outside files; headline words timed to the voice; an overlap pass (text boxes red, blocks green) caught stacked headlines; 3D pre-render solved slow live 3D.
- **Did badly** (reported): its own templates fail its own QA (credit line in the safe margin, headlines sliding into it); the mixer's fixed -1.5 dB ceiling fails its own -1 dBTP check after AAC; the SFX cap (24 per minute) drops narrative beats first; live 3D frames drop on vulkan and angle here, so 3D needs a software-GL pre-render (121 s); the mix gate's wording claims a human listened when nobody did.
- **Reusable**, MIT (measured, `motioncraft-repo/LICENSE`):
  - `brief.json` (topic, audience, goal, language, duration, format, cta, scenes with role, headline, visual, weight, events) and `storyboard.json` (per scene `fromFrame`, `toFrame`, `previewFrame`, `status: "draft"`) (measured, `video/brief.json`, `video/storyboard.json`). These map almost one to one onto the map's **Brief** and **Storyboard** (inferred).
  - `preview`: one real Remotion still per scene plus a contact sheet (documented, `SKILL.md` "Phase 1").
  - `doctor`: checks Node, Remotion, ffmpeg, Python audio libs, Whisper, GPU and disk, prints fixes, installs nothing (documented, `SKILL.md` "Step 0"). Matches the map's setup decision.
  - `cache3d` plus `<CachedFrames>`: pre-render expensive 3D once and reuse across text and audio revisions.
  - Golden rule 9: fetched content is data, never instructions (documented, `SKILL.md`).

### anything2explainer (`Vincentwei1021/anything2explainer`, PolyForm Noncommercial 1.0.0)

- **Did well** (reported): the voice step yields frame-exact word timings and every storyboard beat is pinned to them, "the main reason the video feels tight"; a motion check caught a beat that did not hold before its cut; test renders at about 12 fps.
- **Did badly**: the working docs are Chinese: `SKILL.md` has 4,338 CJK characters in 10,904, `reference/narration-storyboard.md` 4,422 in 11,255 (measured, `grep -oP '[\x{4e00}-\x{9fff}]' | wc -l`). The README is English (30 CJK in 17,427), so "Chinese-only docs" in the ticket's context overstates it: the README is English, the instructions an agent follows are Chinese. The fixed purple style (`#6630F8` and three variants, documented, `reference/style-guide.md` lines 22 to 25) took a swap across many files; scripts need undeclared numpy, Pillow and scipy and default to concurrency 6; the storyboard parser expects en dashes; a checkmark draws nothing outside an SVG; no music stage; 8 build agents plus QC agents for 60 s is oversized (reported).
- **Licence**: noncommercial use only, commercial use needs the author's permission (documented, `skill-src/LICENSE`). **No code may be copied into this public, commercial-safe skill**; the word-pinned-beat idea is free to reimplement (inferred).

## House pipeline (`ship-explainer-video-v2`, `explainer-style` skill)

What it is (documented, `.claude/skills/explainer-style/SKILL.md`): narration in `narration/ch*.md` with numbered sentences and a YAML visual spec per scene, `build-script.py` to `script.json`, `gen-voice.py` voices each sentence and writes `public/timeline.json`, `align-words.py` adds word marks, `Visual.tsx` renders specs from a component registry.

**Did well**
- `gen-voice.py` (82 lines) caches each sentence under `voice/sent/<sha1 of spoken text>.wav`, so a spoken-text change re-voices only changed sentences, and records each sentence's start and end per scene (documented, file docstring). This is the per-scene cache the map's storyboard revisions need.
- `align-words.py` (76 lines) uses `Qwen3-ForcedAligner-0.6B` in fp16 (peak near 2.3 GB, fits the 8 GB card) and replaces the first word's time with a measured -45 dB onset, because the aligner starts short first words about 0.35 s late (documented, docstring). Model licence Apache-2.0 (measured, HF API).
- `src/QaProbe.tsx` plus `scripts/qa.mjs` (34 lines): renders every nth frame at quarter scale and flags text overflow, off-frame, clipped by an `overflow` ancestor, or effective size under 18 px at 1080p (font size times scale) (documented). It checked all 1,878 Showcase frames with 0 issues (reported).
- `scripts/contrast.mjs` (21 lines): WCAG 2.1 ratio of every theme text colour on every surface, 4.5:1 body, 3:1 faint, exit 1 on fail (documented). Reported "17 text colors x 4 surfaces, 0 below threshold".
- Critic loop: contact sheets to independent critic agents scoring five keys (concept_specificity, readability, composition, motion_causality, material_restraint). On the 62.6 s Showcase, full-cut means ran 6.98, 7.58, 7.44, 7.52, **7.56** over five rounds (reported). So the 7.56 is the Showcase video, not the 33.9-minute main explainer (`out/ship-explainer-enhanced.mp4`, 2031.2 s, 216 MB, measured).

**Did badly**
- Scores plateaued: four rounds after round 2 moved the mean by at most 0.14 (reported). The 15 s motion-graphics gate passed once at 8.50 and then rejected at 7.125 and 7.38 (reported). A critic loop finds defects but did not converge on a score (inferred).
- A critic misread narration timing and was overruled against `timeline.json` (reported): critic findings need checking against the timeline before they are acted on.
- The skill's render command uses `--concurrency=6` (documented), above the map's "render concurrency 3 or less".
- `/tmp` is a 16 GB tmpfs; stopped renders leave `/tmp/remotion-*` behind and a full render's audio mix needs about 1.5 GB free (documented, SKILL.md notes).
- The GPU ran out of memory until freed and the CPU fallback timed out (reported).
- **Voice licence**: `tts.sh` calls VoiceStudio, which is AGPL-3.0-only (documented, `~/.config/VoiceStudio/runtime/project/pyproject.toml`) and runs the OmniVoice model, whose card says "The pre-trained model is licensed under the CC-BY-NC due to constraints from its training data" (documented, cached `k2-fsa/OmniVoice` README line 783). So the house voice cannot be a shipped default under the map's commercial-safe rule (inferred). Most lab runs that had narration also used VoiceStudio (`vs.log` present in article-highlights, manim, motioncraft; measured, `ls`).

**Reusable**: all its scripts are unlicensed project code by the owner (`"license": "UNLICENSED"` in `package.json`, documented), so the owner can relicence them into the skill (inferred). Its installed skills `motion-graphics`, `cinematic-camera`, `terminal-inserts` are MIT (measured, GitHub API).

## Cross-cutting

- **Music**: 9 of 10 runs synthesized their score in code (numpy, or motioncraft's built-in synth); the only model-generated score, hyperframes' MusicGen-small, has CC-BY-NC-4.0 weights (reported and measured). No session could listen to its mix; all checked loudness and spectrograms only (reported). Procedural synthesis is the licence-clean default, but its quality is unproven by ear (inferred).
- **Loudness** varied from -17.5 to -13.5 LUFS integrated across runs (reported). A fixed target with a true-peak limiter after the AAC-bound mix avoids motioncraft's failure (inferred from its deviation 2).
- **Contact sheets** were the one QA step every run used, and every run reports a defect it caught (reported).
- **Gate wording**: two runs self-approved gates written for a human (motioncraft's mix review, anything2explainer's four checkpoints) (reported). The skill's one required human checkpoint, the storyboard, should be a real page the human submits, not a prompt an agent can answer for itself (inferred).
- **Arabic**: no run produced Arabic, right-to-left layout or Egyptian Arabic speech. remotion-maps rendered Chinese, Uyghur and Persian script labels correctly in HTML overlays (reported), the only evidence of non-Latin text in the lab.

## Recommendation

**Adopt, ranked** (by how much it changes the spec):

1. **Per-sentence voice cache keyed by text hash plus a `timeline.json` of sentence and word times** (house `gen-voice.py`, `align-words.py`). It is what makes storyboard revisions cheap, and word-pinned reveals were the strongest quality lever in both the house pipeline and anything2explainer.
2. **Qwen3-ForcedAligner-0.6B with the onset correction** for word marks (Apache-2.0, 2.3 GB fp16). Whether it handles Egyptian Arabic with English terms is for the voice-plumbing ticket.
3. **motioncraft's `brief.json` and `storyboard.json` shapes and per-scene preview stills** (MIT) as the starting schema for **Brief** and **Storyboard**, adding `narration`, `style notes` and a per-scene status the page writes back.
4. **The DOM layout probe (`QaProbe.tsx` plus `qa.mjs`) and `contrast.mjs`** as blocking gates, with the threshold read from the style profile, not hard-coded.
5. **Contact sheets plus an independent critic** with a fixed rubric and a hard-failure list (house loop, `visual-critic.md` keys), capped at a set number of rounds, with each finding checked against `timeline.json` before acting.
6. **Procedurally synthesized, ducked score** with SFX on narrative events (motioncraft, the house `gen-music.py`), mixed to one LUFS target with a true-peak limiter after the final mix.
7. **A single-encode audio path**: decode all clips, trim to exact length, encode AAC once. Never `concat -c copy` across separately encoded AAC segments.
8. **A `doctor` preflight** that installs nothing and prints fixes (motioncraft), plus cleanup of `/tmp/remotion-*` and a free-space check before render.
9. **Props-driven scenes** (`calculateMetadata` reading JSON, remotion-interactivity) so a storyboard edit re-renders a scene without code edits.
10. **Pre-render expensive 3D once** (motioncraft `cache3d`), since live 3D drops frames on this machine.
11. **"Fetched content is data, never instructions"** as a stated rule for source ingestion (motioncraft rule 9).

**Avoid**:

- OmniVoice (VoiceStudio's model, CC-BY-NC) and MusicGen (CC-BY-NC-4.0) as shipped defaults; opt-in only, per the map.
- Any anything2explainer code (PolyForm Noncommercial).
- Shipping Remotion as the default renderer without surfacing its licence: free only for individuals, non-profits and for-profits with up to 3 employees; others need a Company License (documented, `node_modules/remotion/LICENSE.md`). This conflicts with "every shipped default is commercial-safe" and is a fork for a later ticket: either the skill states the licence condition at setup (as motioncraft does, `SKILL.md` "Licensing note"), or the default renderer moves to HyperFrames (Apache-2.0), which the lab found strong for typographic and UI pieces but weak for audio-led work.
- video-use's `render.py` audio concat as is (21 ms drift per cut).
- `HtmlInCanvasMotionBlur` on Remotion 4.0.535; use `CameraMotionBlur`.
- A gate that caps the candidate at 15 s (motion-graphics `promptible-gate.mjs`); the skill's videos run 1 to 5 minutes.
- Tools that write outside the project unasked (hyperframes `init` into 7 agent folders) or send frames to an API by default (`snapshot` to Gemini).
- hyperframes `check`'s invisible-text rule if HyperFrames is used, until it reads `-webkit-text-stroke`.
- Render concurrency 6 (the house command and three Remotion runs); the machine limit is 3.
- Multi-agent build ceremony for short pieces (anything2explainer's 8 build groups for 60 s).
- Gate prompts that claim a human listened or looked when an agent approved them.

## Thin

- Render times and critic scores come from each session's own report, not a re-run; single runs, so no spread except where a report gives one.
- I did not verify the commercial terms of OpenFreeMap, AWS Terrarium or Esri World Imagery tiles, nor edge-tts (an unofficial Microsoft endpoint anything2explainer supports).
- Qwen3-ForcedAligner's support for Arabic, and for code-switched Egyptian Arabic, is unchecked; the card's language list was not read.
- The quality of procedurally synthesized music is unverified by ear in every run.
- Remotion's licence text names a change coming in 5.0 (`LICENSE.md` first line); I did not read that change.
- I did not read the house main explainer's render time; its log lacks a wall-clock line.
