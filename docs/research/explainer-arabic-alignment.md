# Egyptian Arabic word alignment and voice QC

Research for [#684](https://github.com/Gharib89/skills/issues/684) on the [explainer-video map](https://github.com/Gharib89/skills/issues/651). The question: what gives word timings and a working voice QC for Egyptian Arabic narration that keeps English kept terms (push, pull request, worktree) inside Arabic sentences, when Gemini 3.8 TTS returns no timestamps and Whisper spells the kept terms in Arabic script.

Each claim carries its basis: **measured** (a command run here, named; scripts in [`explainer-arabic-alignment/`](explainer-arabic-alignment/)), **read** (a primary source, linked) or **inferred**. Machine: i7-10750H (6 cores, 12 threads), RTX 2070 Super Max-Q 8 GB, 30 GB RAM shared with other sessions (swap was full during the CPU runs, so CPU timings are an upper bound).

## Answer

1. **Time words by forcing the script onto the audio, not by timing Whisper's words.** The recommended aligner is `IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53` (Apache-2.0 card) run as a CTC forced aligner, with each kept term spelled into Arabic letters by a 35-rule table. At waveform pause edges its boundaries sit a median 45 ms from the truth (84 percent within 100 ms), and it agrees with torchaudio's MMS_FA to a median 20 ms (98 percent within 100 ms; kept terms 94 percent). MMS_FA is slightly tighter (35 ms) but its weights are CC-BY-NC 4.0. faster-whisper word timestamps mapped onto the script land a median 140 to 200 ms off at pause edges and start the first word at 0 s, 300 ms before the voice (measured, `timing.py`).
2. **Voice QC: transliteration-aware content-word recall, floor 0.8.** Fold the script and the Whisper transcript into one consonant key per word (Arabic letters and English spelling map to shared sound classes, so `push` and `بوش` both give `bS`), match monotonically allowing one script word to span up to three transcript words, and count a content word as heard at similarity 0.6 or better. Good and re-encoded Gemini renders score 0.98 to 1.00; every render that really speaks under 80 percent of its content words (cut off, skipped, spliced, babble, wrong script; n=26) scores 0.77 or less. The house rule (exact word match) scores the same good renders 0.38 to 0.75, and CER 0.18 to 0.38, which is the #676 failure (measured, `table.py`, `summary.py`).
3. **Add an extra-speech floor: precision 0.85.** Recall cannot see a looped render (all words present, some twice). The share of transcript words that match the script is 0.92 or more on good renders and 0.73 to 0.79 on four of five looped renders (Whisper dropped the repeat in the fifth). The 9 to 22 chars/s rate band from #661 catches neither: cut renders ran 17 to 21 chars/s and looped ones 9.7 to 10.9 (measured).
4. **Do not prompt Whisper with the script for QC.** With `initial_prompt` set to the script, Whisper writes kept terms in Latin, but recall on clips buried in 0 dB noise rose from between 0.50 and 0.88 to between 0.88 and 1.00: the prompt fills in words it did not hear (measured).
5. **Whisper small is enough for QC.** small, medium, large-v3 and large-v3-turbo all put good renders at 0.98 or more and under-covered renders at 0.79 or less. small is 464 MB and ran clean clips at 0.23 x real time on CPU (int8); turbo is 1.6 GB and 0.70 x (measured).
6. **Under ADR 0012 both halves can run from Node without Python.** The aligner, exported to ONNX (1.26 GB, or 317 MB int8) and run by `onnxruntime-node` with a 60-line JavaScript Viterbi pass, reproduced the Python timings exactly (fp32 median 0 ms difference; int8 p90 20 ms) at 0.18 x real time on CPU. The same model's own greedy transcript works as the QC transcriber with a thinner margin (good 0.92 to 1.00, under-covered 0.71 or less), so one 317 MB model could serve both gates. Transformers.js Whisper turbo (q8) also runs in Node but at 1.64 x real time and hallucinated at a 30 s chunk seam. The Python route (`uv` venv with faster-whisper, 393 MB, no torch) fits the ADR's existing "Python only through `uv`" allowance (measured; this is a finding, not a decision).
7. **Gemini's free tier allows 10 `gemini-3.8-flash-tts` requests a day.** The eleventh returned HTTP 429 "limit: 10 requests per day on Free Tier". A run that re-synthesises failing scenes twice (#661) needs a paid key (measured with `curl` against `/v1beta/interactions`).

## Test set

| Item | Basis |
|---|---|
| Good renders: the #662 paragraph (6 sentences, 30.6 s and 28.6 s) in `ar-eg-csagent-2` and `ar-eg-commercial-11`, from `prototype/explainer-narrators` `clips/ar-female-C.mp3` and `clips/ar-male-C.mp3` | measured: `build_clips.py` |
| Five new Gemini sentence renders (stock voices only): `s1` (2 sentences, both voices) and `s2a` (1 sentence, `ar-eg-csagent-2`), each sentence rendered alone and joined with 0.45 s gaps, so each sentence's onset and offset in the joined clip is known from the waveform | measured: `render.py`, `build_clips.py` |
| More renders were planned (6 scripts, a perturbed twin of each); the free-tier cap stopped them at 5 calls | measured: HTTP 429 |
| Benign variants that must pass: 48 kbit/s MP3 at 1.1 x tempo | measured: `build_clips.py` |
| Corrupted variants of each good clip: `trunc` (last 35 percent cut), `drop` (middle 30 percent removed), `splice` (middle 30 percent replaced by another Gemini clip of the same voice), `babble` (every 250 ms reversed), `repeat` (25 percent said twice), `noise` (white noise at 0 dB SNR); plus `wrong` (each good clip scored against another script) | measured: `build_clips.py`, `table.py` |
| True coverage of each cut variant: the share of the script's content words whose MMS-aligned midpoint on the good clip lies in the kept audio. Two `drop` and two `splice` clips keep 0.83, above the floor, so they count as pass cases, not block cases | measured: `labels.py` |
| No owner voice or clone audio was used | by construction |

Five good clips, 173 script words (62 of them kept terms), 76 pause edges, 50 scored pairs per transcriber. That is thin; see "What remains thin".

## Word timing

All on the five good clips. "Pause edges": silences of 150 ms or more found from frame energy (under -35 dB of peak); the word ending nearest a silence's start and the word starting nearest its end are scored against those two instants. "Sentence edges": first-word onset and last-word offset against the known sentence spans of the joined `s1` and `s2a` clips.

| Method | Pause edges, median / p90 / within 100 ms | Kept-term edges, median | Sentence onset error | Agreement with MMS_FA, median / within 100 ms | Basis |
|---|---|---|---|---|---|
| MMS_FA (torchaudio `MMS_FA`, uroman romanisation) | 35 ms / 181 ms / 83 % | 48 ms | +12 to +61 ms | (reference) | measured: `align_run.py mms`, `timing.py` |
| Egyptian wav2vec2 CTC, kept terms spelled in Arabic | 45 ms / 133 ms / 84 % | 47 ms | +52 to +101 ms | 20 ms / 98 % (kept terms 20 ms / 94 %) | measured: `align_run.py egy`, `timing.py` |
| faster-whisper large-v3-turbo word timestamps, mapped to script words | 160 ms / 430 ms / 37 % | 150 ms | -280 to -310 ms (first word at 0 s) | 47 ms / 74 % | measured: `whisper_run.py`, `timing.py` |
| faster-whisper large-v3 | 200 ms / 440 ms / 29 % | 200 ms | -500 to -300 ms | 106 ms / 47 % | measured |
| faster-whisper medium | 140 ms / 335 ms / 32 % | 145 ms | -300 to +70 ms | 56 ms / 73 % | measured |
| faster-whisper small | 145 ms / 470 ms / 38 % | 100 ms | -490 to -160 ms | 54 ms / 72 % | measured |
| Transformers.js whisper-large-v3-turbo_timestamped q8, in Node | not run | not run | not run | 105 ms / 48 % | measured: `node/whisper.mjs` |
| Node: Egyptian model as ONNX + JavaScript Viterbi, fp32 / int8 | identical to the Python row (fp32 0 ms median difference; int8 p90 20 ms) | same | same | 20 ms / 98 % (int8 97 %) | measured: `node/align.mjs` |

- **The sentence-offset errors** were -131 to +29 ms (MMS_FA), -171 to -11 ms (Egyptian), -100 to +10 ms (turbo): every method ends the last word slightly early on a trailing fade (measured).
- **Kept terms align as well as Arabic words** at pause edges with both CTC aligners (48 and 47 ms medians against 35 and 45 overall), but their per-word confidence is lower: 0.52 against 0.84 for Arabic words with MMS_FA, 0.53 against 0.80 with the Egyptian model (measured). The rule table is in `align_run.py` (`EN2AR`); acronyms are spelled as letter names first (`CI` becomes "si ay").
- **Whisper word timing needs a fix-up either way.** Its first word starts at 0 s whatever the leading silence (the house pipeline already corrects the first-word onset from the waveform, per `research/explainer-tts`), and it stretches words across pauses. Snapping Whisper boundaries to pause edges would help, but was not measured (inferred).
- **Every script word got a time** from each CTC aligner (173 of 173). Whisper-mapped timing also reached 173 of 173 with turbo, 172 with large-v3 and 171 with small, through words it merged or split (measured). A forced aligner always times every script word, which the caption gate ("every spoken word timed", #661) needs.
- **Two bugs to avoid when porting** (measured, both hit here): torchaudio's `merge_tokens` assumes blank id 0, but this model's blank is `[PAD]` (40) and id 0 is its word separator `|`; and the model expects `|` between words in the target. With either wrong, words drift by seconds.

## Voice QC

### Why the naive metrics fail

On good renders Whisper writes `ship` as `شب` or `شيب`, `worktree` as `وورك تري`, `CI` as `سي آي`. An exact content-word match therefore scores good renders 0.38 to 0.75 (it would block every good Arabic render at 0.8), and CER sits at 0.18 to 0.38 on good renders against 0.44 or more on every under-covered one: a 0.06 gap with no meaning against a 0.8 floor (measured, `table.py`).

### The metric

The key folds one word to its consonant skeleton in a script-independent alphabet. In Python here; a JavaScript port is the same three steps (inferred):

```python
AR = dict(zip("بتثجحخدذرزسشصضطظغفقكلمنه", "bttjhxddrssSsdtdgfkklmnh"))
EN_RULES = (("tch", "S"), ("sh", "S"), ("ch", "S"), ("th", "t"), ("ph", "f"), ("ck", "k"), ("qu", "k"),
            ("ce", "se"), ("ci", "si"), ("c", "k"), ("q", "k"), ("p", "b"), ("v", "f"), ("g", "j"), ("z", "s"), ("x", "ks"))

def key(word):
    w = ar_norm(word).replace("ـ", "").replace(" ", "")      # tashkeel off; alef, ya, ta marbuta folded
    if re.fullmatch("(و|ف|ب|ل)?(ال|ل)?[A-Z]{2,4}", w):            # acronym: letter names
        w = "".join(LETTER[ch] for ch in re.sub("^[^A-Z]*", "", w))
    if LATIN.search(w):                                             # kept term: English spelling to sound classes
        w = re.sub("^(و|ف|ب|ل)?(ال|ل)", "", w).lower()
        for a, b in EN_RULES: w = w.replace(a, b)
        k = re.sub("[aeiouwy]", "", re.sub("[^a-zS]", "", w))
    else:                                                           # Arabic: article off, letters to classes
        w = re.sub("^(و|ف|ب|ل)?ال(?=..)", "", w)
        k = "".join(AR.get(ch, "") for ch in w)                     # vowel letters, hamza, ain drop
    return re.sub(r"(.)\1+", r"\1", k)
```

Then (`common.py`): split the script into words, gluing a tatweel clitic (`الـ`, `لـ`) to the next word as it is spoken; drop a short stop list of function words; align script keys to transcript keys with a monotonic dynamic programme where one script word may match one to three consecutive transcript words (Whisper splits `worktree`) and two script words may match one; similarity is 1 minus normalised edit distance, and a pair counts at 0.6 or better (keys under two letters must match exactly). **Recall** is matched content words over content words; **precision** is matched transcript words over transcript words.

The match threshold was swept (`sweep.py`): 0.5 let a babble clip reach 0.88 recall, 0.67 and up dropped good renders to 0.92, and 0.6 kept good renders at 0.98 or more.

### Separation by transcriber

| Transcriber | Good and benign recall (n=10) | Max recall, true coverage under 0.8 (n=26) | Cut renders with true coverage 0.83 | Clean-clip speed | Basis |
|---|---|---|---|---|---|
| faster-whisper large-v3-turbo, GPU fp16 | 0.98 to 1.00 | 0.77 | 0.83, 0.83, 0.83, 0.75 | 0.039 x real time | measured: `summary.py` |
| same, CPU int8 | 0.98 to 1.00 | 0.77 | same | 0.70 x | measured |
| faster-whisper large-v3, GPU | 0.98 to 1.00 | 0.77 | same | 0.12 x | measured |
| faster-whisper medium, GPU | 1.00 | 0.77 | 0.83, 0.83, 0.75, 0.75 | 0.073 x | measured |
| faster-whisper small, GPU / CPU int8 | 1.00 | 0.77 / 0.79 | 0.83, 0.83, 0.75, 0.83 | 0.038 x / 0.23 x | measured |
| turbo with the script as `initial_prompt` | 1.00 | 0.77 | all 0.83 | 0.042 x | measured; inflates noise clips, see Answer 4 |
| Egyptian wav2vec2 greedy CTC transcript | 0.92 to 1.00 | 0.71 | 0.83, 0.83, 0.75, 0.75 | 0.012 x GPU | measured: `egy_asr.py` |
| Transformers.js turbo q8, Node CPU (good clips only) | 0.90 to 1.00 | not run | not run | 1.64 x | measured: `node/whisper.mjs` |

Recall tracked true coverage on the cut renders within 0.04 on average (turbo; measured). The one cut render that lands on the wrong side of 0.8 in most rows is a splice keeping 0.83 of its content words that recall puts at 0.75: blocking it is the safe error, since the render does say wrong words.

MMS_FA's mean confidence over content words also separates (good 0.68 to 0.73, every corrupted kind except `repeat` 0.62 or less), but it is CC-BY-NC and is not a share of words, so it does not read against a 0.8 floor. The Egyptian model's confidence overlaps (good 0.61 to 0.90, splice up to 0.75) and does not separate (measured).

### Floor

- **Block below 0.8 recall**, as #661 set, on this transliteration-aware recall (measured gap: 0.77 to 0.98). Score per scene rather than per sentence: at 8 content words, one misheard kept term costs 0.125 and a single sentence could fail on it (inferred from the `s2a` rows).
- **Block below 0.85 precision** for extra speech, with less confidence: good renders bottomed at 0.92 on 30 s clips, looped ones topped at 0.79, but the sample is five loops and Node's q8 Whisper dropped two good 30 s clips to 0.81 and 0.83 by hallucinating at a chunk seam (measured). Feed the QC one scene at a time, under 30 s.
- **Noise is out of scope of the floor**: at 0 dB SNR the words are present but Whisper hears 0.50 to 0.88 of them, so such a render blocks. That is the right outcome for a TTS render (inferred).

### Full table (turbo, GPU)

Clip voice: `cs` is `ar-eg-csagent-2`, `co` is `ar-eg-commercial-11`. House match is the house `qc-voice.py` rule (difflib matching blocks over content words) on Arabic-normalised words. MMS conf is the mean MMS_FA confidence over content words.

| kind | clip | script | true coverage | house match | CER | recall | precision | chars/s | MMS conf |
|---|---|---|---|---|---|---|---|---|---|
| good | p0/co | p0 | 1.00 | 0.46 | 0.37 | **1.00** | 0.94 | 13.6 | 0.71 |
| good | p0/cs | p0 | 1.00 | 0.48 | 0.36 | **0.98** | 0.92 | 12.7 | 0.71 |
| good | s1/co | s1 | 1.00 | 0.75 | 0.18 | **1.00** | 1.00 | 12.9 | 0.68 |
| good | s1/cs | s1 | 1.00 | 0.67 | 0.24 | **1.00** | 1.00 | 12.1 | 0.70 |
| good | s2a/cs | s2a | 1.00 | 0.38 | 0.37 | **1.00** | 1.00 | 12.5 | 0.73 |
| benign | p0/co | p0 | 1.00 | 0.42 | 0.38 | **1.00** | 0.95 | 15.0 | 0.69 |
| benign | p0/cs | p0 | 1.00 | 0.48 | 0.36 | **0.98** | 0.92 | 14.0 | 0.69 |
| benign | s1/co | s1 | 1.00 | 0.67 | 0.24 | **1.00** | 1.00 | 14.2 | 0.68 |
| benign | s1/cs | s1 | 1.00 | 0.58 | 0.25 | **1.00** | 1.00 | 13.3 | 0.71 |
| benign | s2a/cs | s2a | 1.00 | 0.38 | 0.37 | **1.00** | 1.00 | 13.8 | 0.73 |
| noise | p0/co | p0 | 1.00 | 0.23 | 0.56 | **0.58** | 0.70 | 13.6 | 0.32 |
| noise | p0/cs | p0 | 1.00 | 0.25 | 0.48 | **0.60** | 0.61 | 12.7 | 0.38 |
| noise | s1/co | s1 | 1.00 | 0.08 | 0.52 | **0.50** | 0.58 | 12.9 | 0.38 |
| noise | s1/cs | s1 | 1.00 | 0.25 | 0.41 | **0.83** | 0.82 | 12.1 | 0.43 |
| noise | s2a/cs | s2a | 1.00 | 0.25 | 0.44 | **0.88** | 0.90 | 12.5 | 0.50 |
| repeat | p0/co | p0 | 1.00 | 0.50 | 0.54 | **1.00** | 0.76 | 10.9 | 0.71 |
| repeat | p0/cs | p0 | 1.00 | 0.54 | 0.52 | **0.96** | 0.73 | 10.2 | 0.71 |
| repeat | s1/co | s1 | 1.00 | 0.83 | 0.09 | **1.00** | 1.00 | 10.3 | 0.71 |
| repeat | s1/cs | s1 | 1.00 | 0.67 | 0.46 | **1.00** | 0.78 | 9.7 | 0.73 |
| repeat | s2a/cs | s2a | 1.00 | 0.38 | 0.54 | **1.00** | 0.79 | 10.0 | 0.76 |
| trunc | p0/co | p0 | 0.69 | 0.31 | 0.58 | **0.69** | 0.93 | 21.0 | 0.40 |
| trunc | p0/cs | p0 | 0.69 | 0.33 | 0.57 | **0.69** | 0.93 | 19.6 | 0.41 |
| trunc | s1/co | s1 | 0.58 | 0.33 | 0.44 | **0.67** | 0.93 | 19.8 | 0.41 |
| trunc | s1/cs | s1 | 0.58 | 0.25 | 0.47 | **0.67** | 1.00 | 18.6 | 0.42 |
| trunc | s2a/cs | s2a | 0.62 | 0.25 | 0.53 | **0.75** | 1.00 | 19.2 | 0.42 |
| drop | p0/co | p0 | 0.69 | 0.33 | 0.53 | **0.67** | 0.93 | 19.5 | 0.46 |
| drop | p0/cs | p0 | 0.69 | 0.38 | 0.52 | **0.67** | 0.91 | 18.2 | 0.47 |
| drop | s1/co | s1 | 0.83 | 0.42 | 0.58 | **0.83** | 1.00 | 18.4 | 0.44 |
| drop | s1/cs | s1 | 0.83 | 0.42 | 0.58 | **0.83** | 1.00 | 17.3 | 0.46 |
| drop | s2a/cs | s2a | 0.62 | 0.12 | 0.53 | **0.62** | 1.00 | 17.8 | 0.45 |
| splice | p0/co | p0 | 0.69 | 0.33 | 0.45 | **0.77** | 0.75 | 13.6 | 0.59 |
| splice | p0/cs | p0 | 0.69 | 0.35 | 0.45 | **0.75** | 0.74 | 12.7 | 0.58 |
| splice | s1/co | s1 | 0.83 | 0.42 | 0.51 | **0.83** | 0.69 | 12.9 | 0.57 |
| splice | s1/cs | s1 | 0.83 | 0.42 | 0.53 | **0.75** | 0.53 | 12.1 | 0.62 |
| splice | s2a/cs | s2a | 0.62 | 0.12 | 0.51 | **0.62** | 0.67 | 12.5 | 0.54 |
| babble | p0/co | p0 | 0.00 | 0.00 | 0.73 | **0.38** | 0.31 | 13.6 | 0.30 |
| babble | p0/cs | p0 | 0.00 | 0.00 | 0.77 | **0.23** | 0.19 | 12.7 | 0.29 |
| babble | s1/co | s1 | 0.00 | 0.00 | 0.78 | **0.00** | 0.16 | 12.9 | 0.37 |
| babble | s1/cs | s1 | 0.00 | 0.00 | 0.81 | **0.08** | 0.20 | 12.1 | 0.41 |
| babble | s2a/cs | s2a | 0.00 | 0.00 | 0.76 | **0.38** | 0.31 | 12.5 | 0.38 |
| wrong | p0/co | s1 | 0.00 | 0.08 | 2.55 | **0.42** | 0.11 | 4.0 |  |
| wrong | p0/co | s2a | 0.00 | 0.25 | 4.29 | **0.38** | 0.05 | 2.6 |  |
| wrong | p0/cs | s1 | 0.00 | 0.08 | 2.58 | **0.33** | 0.11 | 3.7 |  |
| wrong | p0/cs | s2a | 0.00 | 0.25 | 4.32 | **0.25** | 0.03 | 2.4 |  |
| wrong | s1/co | p0 | 0.00 | 0.02 | 0.82 | **0.08** | 0.33 | 44.4 |  |
| wrong | s1/co | s2a | 0.00 | 0.12 | 1.03 | **0.25** | 0.11 | 8.3 |  |
| wrong | s1/cs | p0 | 0.00 | 0.02 | 0.82 | **0.08** | 0.33 | 41.7 |  |
| wrong | s1/cs | s2a | 0.00 | 0.12 | 1.06 | **0.25** | 0.11 | 7.8 |  |
| wrong | s2a/cs | p0 | 0.00 | 0.04 | 0.89 | **0.08** | 0.27 | 66.6 |  |
| wrong | s2a/cs | s1 | 0.00 | 0.08 | 0.76 | **0.08** | 0.18 | 19.3 |  |

## Running under ADR 0012

ADR 0012 (on `wayfinder/explainer-video`) makes every shipped script Node and allows Python "only inside the TTS adapters, run through `uv`" (read). The measured options:

| Route | What ships | Size | CPU speed (clean clips) | Basis |
|---|---|---|---|---|
| faster-whisper behind a Node script, `uv run` | a `uv` venv with `faster-whisper` 1.2.1 (pulls CTranslate2 4.8.3 and onnxruntime, no torch) | 393 MB venv plus 464 MB (small) or 1.6 GB (turbo) | small 0.23 x, turbo 0.70 x | measured: `uv pip install faster-whisper`, `du`; CTranslate2 publishes wheels for Linux x86_64 and aarch64, macOS arm64 and x86_64, Windows amd64 ([PyPI](https://pypi.org/project/ctranslate2/4.8.3/#files)) |
| Torch CTC aligner behind a Node script, `uv run` | torch, torchaudio, transformers | 1.2 GB torch alone (CPU wheel smaller; not measured), plus the 1.26 GB model | 0.17 x (Egyptian), 0.20 x (MMS_FA) | measured: `align_run.py egy cpu`, `align_run.py mms cpu` |
| Egyptian wav2vec2 as ONNX in `onnxruntime-node`, Viterbi in JavaScript | `onnxruntime-node` (MIT; npm lists win32, darwin, linux) and one model file | 317 MB int8 (1.26 GB fp32); 1.25 GB RSS int8 | 0.17 x int8, 0.18 x fp32 | measured: `torch.onnx.export` plus `quantize_dynamic`, `node/align.mjs`; the export is a one-time build step, and the model must be hosted somewhere the skill downloads from (inferred) |
| Transformers.js Whisper in Node | `@huggingface/transformers` (Apache-2.0), `onnx-community/whisper-large-v3-turbo_timestamped` q8 | 1.08 GB model; 3.4 GB RSS | 1.64 x | measured: `node/whisper.mjs`; `return_timestamps: 'word'` read in the [pipeline typedef](https://github.com/huggingface/transformers.js/blob/main/packages/transformers/src/pipelines/automatic-speech-recognition.js) |

The Node-only path with the fewest moving parts is one ONNX model doing both jobs: forced alignment for timing and its greedy transcript for QC (inferred from the two measured halves). Its QC margin is thinner than Whisper's (0.92 good minimum against 0.98), so it trades margin for a single 317 MB file and no Python. The Viterbi and the key function are short enough to own (60 and 25 lines here).

## Licences and sizes

| Component | Code | Weights | Size | Basis |
|---|---|---|---|---|
| faster-whisper | MIT | Whisper weights MIT (openai/whisper) | small 464 MB, medium 1.5 GB, turbo 1.6 GB, large-v3 2.9 GB | read: GitHub licence API for `SYSTRAN/faster-whisper` and `openai/whisper`; HF card `deepdml/faster-whisper-large-v3-turbo-ct2` MIT; sizes measured with `du -shL` |
| torchaudio MMS_FA | BSD-2-Clause (torchaudio) | **CC-BY-NC 4.0** | 1.26 GB | read: `torchaudio.pipelines.MMS_FA` docstring, which links the [fairseq MMS licence](https://github.com/facebookresearch/fairseq/tree/100cd91db19bb27277a06a25eb4154c805b10189/examples/mms#license); measured size |
| `MahmoudAshraf97/ctc-forced-aligner` | BSD-2-Clause | default model `MahmoudAshraf/mms-300m-1130-forced-aligner`: **CC-BY-NC 4.0** | | read: GitHub licence API, HF API |
| PyPI `ctc-forced-aligner` 1.0.2 | a different project: Deskpai's fork under the "Deskpai Open Source License", which requires a prominent attribution line in any redistribution, and downloads its own ONNX model | not stated; derived from MMS (inferred) | | read: the installed package's `LICENSE` and `MODEL_URL` |
| `IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53` | | **Apache-2.0** (card); trained on Common Voice, MGB-3, MASC, Arabic Speech Corpus and custom YouTube data, whose own terms the card does not discuss | 1.26 GB safetensors; 317 MB int8 ONNX | read: [model card](https://huggingface.co/IbrahimAmin/egyptian-arabic-wav2vec2-xlsr-53); measured sizes |
| WhisperX | BSD-2-Clause | aligns Arabic with `jonatasgrosman/wav2vec2-large-xlsr-53-arabic` (Apache-2.0) and sends characters outside the model's alphabet (a kept term's Latin letters) to a wildcard | | read: [`whisperx/alignment.py`](https://github.com/m-bain/whisperX/blob/main/whisperx/alignment.py); not measured |
| Qwen3-ForcedAligner-0.6B (the house aligner) | | Apache-2.0 | | read: [card](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B): 11 languages, no Arabic |
| onnxruntime-node 1.30.0 | MIT | | 503 MB installed (all platforms' binaries) | read: npm; measured `du` |

## What remains thin

- **Five good clips from two voices**, all one domain. The free-tier cap stopped the planned 12 more renders (with natural word-substitution errors). The recall floor's gap (0.77 to 0.98) and the precision floor (0.85) need a paid-key batch of real Gemini failures before they are trusted (inferred).
- **The garbled renders are synthetic.** Cuts, splices, reversal and loops stand in for what Gemini actually does wrong; no real Gemini mis-read was captured (measured: none occurred in the 7 renders).
- **Interior word boundaries have no ground truth.** Timing truth covers pause edges (76) and sentence edges (10); interior words rest on two independent CTC aligners agreeing within 20 ms, which shows consistency, not correctness. A hand-marked sentence or two would settle it (inferred).
- **The kept-term rule table was written for these 20 terms.** Unusual spellings (`queue`, `cache`, `null`) may fold badly; their per-word confidence is already lower than Arabic words' (measured: 0.53 against 0.80).
- **Node Whisper was only tried at q8.** The fp32 encoder (larger download) and chunk-free scene clips may close its gap to faster-whisper (inferred). Windows and macOS runs of either Node route were not tried; only npm's and PyPI's platform lists were read.
- **CPU timings ran under memory pressure** (swap full from other sessions), so they are upper bounds.

## Reproducing

From `docs/research/explainer-arabic-alignment/` with a `uv` venv holding `torch torchaudio faster-whisper uroman soundfile numpy transformers google-genai nvidia-cublas-cu12 nvidia-cudnn-cu12==9.*` (CTranslate2 on GPU needs the CUDA 12 cuBLAS and cuDNN wheels on `LD_LIBRARY_PATH` when torch is a CUDA 13 build):

```sh
python render.py scripts.json good          # Gemini renders, one call per sentence (needs GEMINI_API_KEY)
python build_clips.py                       # good, benign and corrupted clips; out/truth.json
bash runall.sh > out/runall.log 2>&1        # aligners and Whisper sizes, GPU then CPU
python egy_asr.py cuda                      # Egyptian model as the QC transcriber
python summary.py out/whisper-*.json        # floor separation per transcriber
python sweep.py out/whisper-faster-whisper-large-v3-turbo-ct2-cuda-none.json
python table.py out/whisper-faster-whisper-large-v3-turbo-ct2-cuda-none.json
python timing.py out/whisper-faster-whisper-large-v3-turbo-ct2-cuda-none.json
node node/align.mjs egy-int8.onnx tokens.json f32/*.f32   # after exporting the model to ONNX
node node/whisper.mjs onnx-community/whisper-large-v3-turbo_timestamped q8 f32/*.f32
```

The ONNX export was `torch.onnx.export(model, (audio,), "egy.onnx", input_names=["audio"], output_names=["logits"], dynamic_axes={"audio": {1: "n"}, "logits": {1: "t"}}, opset_version=17, dynamo=False)` followed by `onnxruntime.quantization.quantize_dynamic(..., weight_type=QuantType.QUInt8)`. The Node aligner normalises the audio to zero mean and unit variance as the model's feature extractor does.
