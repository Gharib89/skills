# Sound effects and beds a local render can use

Research for [#997](https://github.com/Gharib89/skills/issues/997) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-27.

Labels: **measured** (a command was run on this machine, named inline),
**read** (a primary source says so: the licence page, the official docs, the
skill or repo file, a run's own transcript), **inferred** (my reading, no
direct proof).

## Answer

Ranked by how much each finding changes the new skill's design.

1. **Effects and beds come from recorded CC0 sounds through Openverse, not
   from Freesound's website.** Openverse's audio API needs no key, filters by
   licence (`license=cc0`) and indexes Freesound's catalogue (591,897 Freesound
   items, 3,983,517 Wikimedia Commons, 644,709 Jamendo; measured:
   `curl https://api.openverse.org/v1/audio/stats/`). The ambition stance's run
   got its sounds by scraping `freesound.org/search/` HTML (read, the run's
   transcript), which a skill cannot ship: Freesound's `robots.txt` disallows
   `/search/` for every agent and disallows `ClaudeBot` site-wide (measured:
   `curl https://freesound.org/robots.txt`), and its API terms forbid "robots,
   spiders, scraping" (read, [API terms](https://freesound.org/help/tos_api/)
   section 4(f)). Openverse returns the same Freesound HQ previews (128 kbps
   MP3 on `cdn.freesound.org`; measured, a result's `url` and `bit_rate`).
2. **Openverse is slow when cold, and `media-use` gives up at 10 s.** Thirteen
   cold queries took 1.9 to 16.7 s, median 9.1 s, and 5 of 13 passed 10 s;
   repeating a query took 0.14 to 0.16 s (measured: `curl -w %{time_total}` on
   `api.openverse.org/v1/audio/`, 5 runs of 2 warm queries alternating). Its
   anonymous limit is 20 a minute and 200 a day (measured: the
   `x-ratelimit-limit-anon_*` response headers). `media-use`'s client times out
   at 10 s, and its first timeout stops it asking Openverse for the rest of the
   run (read: `audio/scripts/lib/openverse.mjs` `SEARCH_TIMEOUT_MS`,
   `lib/sfx.mjs` `openverseDown`). In a real `resolve` run, "masking tape rip"
   failed cold after 12.1 s and resolved warm in 2.4 s (measured, below). The
   new skill needs a longer timeout and one retry, or the agent queries
   Openverse itself (inferred).
3. **No local model makes a bed from the concept's world, so beds are
   recordings too.** ACE-Step 1.5 asked for "restaurant kitchen room tone
   ambience, field recording, no music, no melody" returned tonal audio with a
   median spectral flatness of 0.054 to 0.073, the same range as its music bed
   (0.059 to 0.113) and far from the stance run's real CC0 kitchen room tone
   (0.356) (measured: numpy flatness over 2048-sample frames; not heard). Long
   CC0 ambiences are there to fetch: "kitchen ambience" with `length=medium`
   returned 34 CC0 results of 126 s and up (measured). `media-use`
   `resolve --type sfx` drops anything over 15 s, so asked for a "restaurant
   kitchen room tone" it returned its bundled "Negative / error tone"
   (measured, below): it is the wrong tool for a bed.
4. **Do not fork `explainer-video`'s `score/`.** It is 1,227 lines of
   JavaScript that synthesise music (seven presets, a section per scene)
   and two effects, a noise-sweep whoosh and a chime sting, plus a 54-line
   ACE-Step wrapper (measured: `wc -l scripts/score/*`; read, `sfx.mjs`). The
   stance says effects are "never tones" and `hyperframes` says "No
   synthesised tones, chimes or dings" and "Do not spend the run building an
   audio chain or writing music in code" (read: `STANCE.md`,
   `references/sound.md` §3 and §4). The one reusable idea is the duck from
   word timings (`duck()` and `bedLevel()`, about 60 lines), and
   `media-use`'s mixing reference already covers it: a `volume` lane down to
   0.3 to 0.4 while anyone speaks, then `carve.mjs` to dip only the voice's
   bands (read, `references/mixing.md` "Music under a voice").
5. **ACE-Step fits this 8 GB card after all, but only matters for a musical
   bed.** `explainer-video` sends any card under compute capability 8.0 to the
   CPU, because ACE-Step picks float16 there and float16 gives NaN (read:
   `scripts/lib/tools.mjs` `torchDevice`); on the CPU it costs 88 s and
   15.5 GB of RAM per 30 s (read, `setup/rows.json` `cpu`). Forcing bfloat16,
   which PyTorch emulates on this card, plus `offload_to_cpu=True`: 30 s of
   audio in 10.3 s median (10.2 to 10.4), 120 s in 31.9 s (30.6 to 32.6), 5
   runs each, peak VRAM 5.79 GiB, peak RSS 5.7 GB, no NaN, and the same seed
   gave byte-identical audio in 5 of 5 runs and across processes (measured:
   probe script below, RTX 2070 Super Max-Q, 8 GB, capability 7.5, under
   `systemd-run -p MemoryMax=10G`). Without offload it ran out of VRAM loading
   the text encoder (measured). Every take peaked at +0.7 to +1.1 dBFS, so it
   clips until normalised (measured).
6. **The offline fallback should be Kenney's CC0 packs, not `media-use`'s
   bundled files.** Nine Kenney audio packs hold 706 files in about 14 MB,
   each zip fetched in 1.0 to 8.6 s with no key, CC0 by the pack's own licence
   file (measured: `curl` plus `unzip -l`). They are impacts, UI, casino, RPG,
   sci-fi and jingles, with no ambiences (measured, file names). `media-use`
   bundles 19 Pixabay files (measured: `ls`; its `SKILL.md` says 21), and the
   Pixabay licence forbids redistributing them standalone (read, #655's
   licence table), so a public skill copying them is the wrong move
   (inferred).
7. **`hyperframes`' ban on synthesised sound is in `sound.md`, not in the
   BANNED list.** `spec.md` "BANNED by default" lists only visual defaults
   (measured: `grep -n -A14 'BANNED by default'`); "No synthesised tones,
   chimes or dings" is the last line of `sound.md` §4 (read). `hyperframes`'
   default for a film over 15 s is "a music bed and sounds on its visible
   actions" (read, `sound.md` §1), while the stance's default bed is the
   concept's world, with no music (read, `STANCE.md`, the stance run's
   `SPEC.md`): the stance overrides `hyperframes` on the bed and should say so
   by name (inferred).

## What the zoomed tickets already settle

- **[#964](https://github.com/Gharib89/skills/issues/964)** (motion skills):
  `media-use` is Apache-2.0, bundles Pixabay-licence effects, and its local
  MusicGen fallback uses CC-BY-NC-4.0 weights; Barty-Bart's `sound-effects`
  skill (MIT) is the best sound pass (beat grid, CC0 kit, licence ledger);
  ElevenLabs and Sonilo need paid keys; `hyperframes` says "no synthesised
  tones". What changed since: `media-use` now searches Openverse before its
  bundled files (read, `audio/references/sfx.md`); #964 counted 19 bundled
  files and that still holds (measured), though `SKILL.md` now says 21.
- **[#970](https://github.com/Gharib89/skills/issues/970)** (three arms): the
  winner's synthesised score and effects were its weak spot ("the sound
  effects is not the best"). Not re-run.
- **[#974](https://github.com/Gharib89/skills/issues/974)** (stance): 15
  recorded CC0 effects tied to story events, a low bed from the concept's
  world by default, out for the hardest step, peaks 31 to 35 ms after their
  picture. What it missed: how the sounds were found (next section).
- **[#655](https://github.com/Gharib89/skills/issues/655)**
  (`research/explainer-music-sfx`, found while zooming): already has the
  licence table for local models and libraries, which this note does not
  redo. It chose synthesised music and effects as the default; the stance and
  `hyperframes` now reverse that for this skill. Its "Thin" list said ACE-Step
  on this 8 GB card was not run; finding 5 runs it.

## How the stance run found its 15 effects

Read from the run's transcript (Claude Code in `--safe-mode`, no MCP):

1. `curl -sI https://kenney.nl`, then downloaded four Kenney zips (Impact,
   Interface, RPG, Casino) and listed their `.ogg` files. Three plate sounds
   came from Impact Sounds.
2. Searched Wikimedia Commons' API (`list=search`, `srnamespace=6`) for
   "service bell", "receipt printer", "kitchen ambience" and four more: one
   restaurant kitchen file and no usable bell or printer.
3. Fetched `https://freesound.org/search/?q=<words>&f=license:"Creative
   Commons 0"&s=Downloads (most first)` with a browser user agent, wrote a
   20-line parser for each result's `data-mp3` preview URL, id, user and
   duration, ran it on about 15 queries, downloaded the `-hq.mp3` previews, and
   grepped each sound's own page for "Creative Commons 0" before keeping it.
4. Trimmed, measured each clip's envelope to place its peak one frame after
   the picture, and normalised.

Openverse covers step 3 with an API that allows it (finding 1).

## Sources compared

| Source | Licence | Key or account | Offline | Catalogue | Fetch time | Fit |
|---|---|---|---|---|---|---|
| [Openverse audio API](https://api.openverse.org/v1/audio/) | per item; filter `cc0` (or `cc0,by` with credits) | none; 20/min, 200/day anon (measured, headers) | no | 5.2M items from Freesound, Wikimedia, Jamendo (measured, stats) | search 1.9 to 16.7 s cold, 0.15 s warm; a preview about 1.6 s (measured) | Default for effects and beds |
| [Freesound APIv2](https://freesound.org/docs/api/overview.html) | per sound | free account and API key; originals need OAuth2 (measured: search 401 without a token, download 401 anon); "commercial use of the API" negotiated case by case (read, API terms §3) | no | 737,979 sounds, 383,950 CC0 (measured, search page header) | not measured (no key) | Only if Openverse misses; key is a setup step |
| Freesound website search | per sound | none | no | same | 0.66 to 0.80 s a page (measured, 10 runs) | Not for a skill: robots and API terms (finding 1) |
| [Kenney](https://kenney.nl/assets) audio packs | CC0 (pack licence file) | none | yes, once vendored | 706 files in 9 packs, about 14 MB (measured) | 1.0 to 8.6 s a zip (measured) | Offline fallback; no ambiences |
| Wikimedia Commons API | per file, mixed | none | no | 3.98M audio items (Openverse stats), mostly music and speech (inferred, the stance run's hits) | not timed | Rarely fits a story event (read, stance transcript) |
| `media-use` bundled set | Pixabay Content License | none | yes | 19 files (measured) | local | UI and glitch sounds; not ours to copy (finding 6) |
| [Pixabay](https://pixabay.com/api/docs/) | Pixabay Content License | key | no | not stated | n/a | Its API serves images and videos only (measured: docs list two endpoints) |
| [Sonniss GDC bundle](https://sonniss.com/gdc-bundle-license/) | royalty-free; may not "supply the sound effects as sound effects"; no AI training (read) | none | yes, a user's own folder | tens of GB per year (#655) | manual | User-supplied only |
| [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk/) | personal and educational; commercial needs a licence (read, site text) | none | no | "over 30,000" (read) | n/a | Exclude |

### Local generation on this machine

RTX 2070 Super Max-Q, 8 GB, compute capability 7.5, 30 GB RAM (measured:
`nvidia-smi`, `free -g`).

| Model | Licence and gate (measured: HF API tags, a ranged download) | What it makes | On this card |
|---|---|---|---|
| ACE-Step 1.5 turbo (2.39B DiT, bfloat16) | MIT, ungated | music; tonal even when asked for room tone or a bell (finding 3) | fits with bfloat16 forced and CPU offload: 30 s in about 10 s, 5.79 GiB (finding 5) |
| Stable Audio 3 small-sfx (2.27 GB weights plus a 1.18 GB T5Gemma encoder) | Stability AI Community License; gated, 403 with this machine's token until the account accepts | effects up to about 2 min (#655) | not run: gated |
| Stable Audio Open 1.0 and Open Small | same licence; gated, 403 | effects better than music (#655) | not run: gated |
| AudioGen, MusicGen, MAGNeT, MMAudio | CC-BY-NC-4.0 | effects or music | excluded: non-commercial |
| AudioLDM2, Tango 2 | CC-BY-NC-SA-4.0 | effects | excluded |
| TangoFlux | "non-commercial research use only" (read, card) | effects | excluded |

The Stability AI Community License ends free use once the organisation earns
over USD 1M a year, needs registration for commercial use, and a "Powered by
Stability AI" notice (read,
[stability.ai/community-license-agreement](https://stability.ai/community-license-agreement)).
No local effects model is both commercial-safe and ungated (inferred from the
table).

## `media-use resolve` on six story cues

Six cues from the stance run's kitchen, each in a fresh project,
`npx hyperframes@0.8.197 media-use resolve --type sfx --intent "<cue>"`
(measured, wall time per call, 2026-10-27):

| Cue | Time | Result |
|---|---|---|
| service desk bell ding | 9.3 s | Freesound 672186 via Openverse, CC0, 0.9 s |
| thermal receipt printer | 7.2 s | Freesound 413838 via Openverse, CC0, 1.6 s |
| restaurant kitchen room tone | 6.1 s | bundled "Negative / error tone", 1.6 s: wrong kind |
| masking tape rip | 12.1 s | nothing (cold timeout); 2.4 s and Freesound 405386 when repeated |
| steel plate on counter | 4.5 s | nothing: 0 Openverse hits, no bundled match |
| frying pan sizzle | 2.3 s | Freesound 234124 via Openverse, CC0, 1.9 s |

Every call also printed "HyperFrames skill out of date or missing" (measured);
the pinned npm is 0.8.197 and the current release 0.8.206 (measured:
`npm view hyperframes version`).

## ACE-Step probe

The probe forces bfloat16 by replacing ACE-Step's
`gpu_config.cuda_supports_bfloat16` (and `memory_utils`' imported copy) with a
function returning true before the handler loads, then calls
`initialize_service(..., device="cuda", offload_to_cpu=True)` and
`generate_music` exactly as `explainer-video`'s `scripts/score/ace.py` does
(DiT only, `thinking=False`, seed 7). PyTorch 2.10 reports
`is_bf16_supported()` true and `including_emulation=False` false on this card
(measured). Run under
`systemd-run --user --scope -q -p MemoryMax=10G -p MemorySwapMax=0`.

| Prompt | Length | Wall | Integrated | Peak | Flatness |
|---|---|---|---|---|---|
| low ambient instrumental bed | 30 s | 9.7 to 10.4 s | -24.1 LUFS | +1.1 dBFS | 0.066 |
| low ambient instrumental bed | 120 s | 30.6 to 32.6 s | -22.2 LUFS | +0.9 dBFS | 0.059 |
| restaurant kitchen room tone, no music | 30 s | 9.7 s | -20.2 LUFS | +0.7 dBFS | 0.054 |
| a single service desk bell ding | 15 s | 6.6 s | -17.7 LUFS | -0.4 dBFS | 0.134 |
| reference: Freesound 766292 kitchen room tone (the stance's bed) | 123 s | n/a | -34.6 LUFS | -3.2 dBFS | 0.356 |

Flatness near 0 is tonal, near 1 is noise-like; it is a proxy for "music, not
ambience", not a listen.

## What this means for the new skill (inferred)

- Effects: the agent names each sound concretely, searches Openverse with
  `license=cc0` (CC BY only with a credit line), allows about 20 s for a cold
  query and retries once, downloads the preview, records id, author, licence
  and URL in a sources file, as the stance run did.
- Bed: the same search with `length=medium`, chosen from the concept's world;
  a musical bed only when the concept is musical, and then ACE-Step on the GPU
  is a cheap local option.
- Offline: a vendored subset of Kenney's CC0 packs, with the gap (no
  ambiences) stated.
- Mix: word-timed duck and carve through `media-use` mixing; measure the
  encoded file, as #655 found the AAC encode raises true peak.
- What is still owed to
  [A cast and sound design](https://github.com/Gharib89/skills/issues/998):
  the sound palette's craft, the per-minute rate (a warning per #972), and
  whether a cast's host voice needs effects of its own.

## Thin

- Openverse cold timing is 13 queries on one day from one network; the
  slowness may be its cache, not a stable property.
- The flatness verdict on ACE-Step is a spectral proxy; nobody listened.
- Freesound APIv2 search speed was not measured (no key on this machine).
- Stable Audio 3 small-sfx was not run: its gate needs the owner's account to
  accept the licence.
- BBC's licence was read from the archive's front-page text; its licensing
  page did not render without JavaScript.
