# The brag skill: what explainer-video should adopt

Research for [#659](https://github.com/Gharib89/skills/issues/659) on the
[explainer-video map](https://github.com/Gharib89/skills/issues/651).

## Answer

"The brag skill" is almost certainly **`/brag` by Latent Spaces**
([latent-spaces/brag](https://github.com/latent-spaces/brag), MIT, author Shunit
Haviv Hakimi). Confidence: high. It is the only "brag" skill that makes videos
at scale (about 16k stars, 16.7k installs); every other "brag" skill writes a
text brag document. It makes 15 to 25 second **launch videos**, not explainers:
it reads a project's code, writes a plan and storyboard, then hands a brief to
HeyGen's **HyperFrames** (HTML compositions rendered to MP4). Narration is off by
default and uses Kokoro, which has no Arabic voice.

explainer-video should adopt its **planning discipline** (rubric, storyboard
contract, grounding rule, reading-time floor, beat-cue presets, SFX analysis,
poster-as-frame-0, secrets rule), not its stack or its length.

## Candidates

| Candidate | What it does | Video? | Signals |
|---|---|---|---|
| [latent-spaces/brag](https://github.com/latent-spaces/brag) `brag`, `brag-slim` | Project or URL to 15 to 25 s launch video with music, SFX, share copy | Yes | 15,997 stars, 1,170 forks, last push 2026-10-13, MIT (measured: `gh api repos/latent-spaces/brag`); 16.7K installs on [skills.sh](https://skills.sh/latent-spaces/brag/brag) |
| [kammradt/brag-skill](https://github.com/kammradt/brag-skill) | Accomplishment report from PRs, commits, Asana, Slack | No | 8 stars, 7 installs (measured: `gh search repos`, `npx skills find brag`) |
| [matheusm/brag](https://github.com/matheusm/brag), cristiano-pacheco `ai-brag-document`, iambharathpadhu, sdshah09, javiermolinar/dope-brag | Brag document for performance reviews | No | 0 to 1 stars, at most 6 installs (measured: same commands) |
| [GrandpaEJ/brag-bn](https://github.com/GrandpaEJ/brag-bn) | /brag variant with a Bangla edge-tts voiceover, word-synced | Yes | 0 stars, no licence file (measured: `gh api repos/GrandpaEJ/brag-bn`) |
| Am0stafa/brag-video, DarkWzrd-Zeref/brag, clezcoding/brag-for-cursor | Forks or wrappers of latent-spaces/brag (Docker, local HyperFrames, Cursor installer) | Yes | 0 to 1 stars (measured: `gh search repos`) |
| `ui-skills.com@brag` (latent-spaces-brag) | Registry mirror of latent-spaces/brag | Yes | 3 installs (measured: `npx skills find brag`) |

Why latent-spaces/brag (inferred): "good at making videos" only fits the video
candidates, and every video candidate is a fork, wrapper or mirror of it. A
hosted version runs at [letsbrag.app](https://letsbrag.app) (documented:
README).

## How it makes a video

Read at commit `069432c` (2026-10-13), shallow clone, nothing run.

1. **Inspect** (`references/step-1-inspect.md`): reads `index.html`, CSS custom
   properties (exact colours), fonts, README, `package.json`, routes and feature
   components, then answers a **9-question rubric** (what is it, best claim,
   visual hook, UI to show, shortest satisfying length, tone, audio role, share
   caption, user flow "entry, key action, result"). Gate: all nine answered.
2. **Plan** (`references/step-2-plan.md`): writes `brag-plan.md`, a fixed-shape
   page (angle, hook, key moments, outro, tone preset plus freeform direction,
   format, visual identity, audio direction, music cue guidance) and a
   **scene-by-scene storyboard** where each scene names what is on screen, a
   `Sequential/interaction` line, audio intent and transition mood. Gate: scene
   durations sum to 15 to 25 s.
3. **Compose** (`references/step-3-compose.md`): writes `composition-brief.md`,
   the boundary contract: brag owns angle, copy, tone, moments, audio choice;
   HyperFrames owns structure, timing, animation mechanics, lint and render. It
   then loads HyperFrames' own skills (`hyperframes-core`, `-animation`,
   `-creative`, `-keyframes`, `-cli`) and lets them build `composition/`. Gate:
   `npx hyperframes check` passes (layout overflow and WCAG contrast are errors).
4. **Deliver** (`references/step-4-deliver.md`): optional `hyperframes preview`
   for the user, `hyperframes render`, then picks the strongest *settled* frame
   with ffmpeg to `brag.jpg` and **overlays it on frame 0** so platform
   thumbnails show it, and writes a one-caption `share-copy.txt`.

`/brag-slim` (`skills/brag-slim/SKILL.md`, 105 lines) is the same workflow with
no HyperFrames and no bundled assets: the model builds and renders the video
with whatever is on the machine, and accepts a URL as input (headless browser,
scroll section by section). `/brag` switches to it automatically on Opus 5.5
unless `--full` or `--voice` is passed (documented: `skills/brag/SKILL.md`,
README).

## Stack

| Part | What | Licence |
|---|---|---|
| Renderer | [HyperFrames](https://github.com/heygen-com/hyperframes) CLI via `npx hyperframes` (Node 22+, FFmpeg); HTML plus `data-*` timing attributes, headless browser capture | Apache-2.0 (measured: `gh api repos/heygen-com/hyperframes`, 63.9k stars) |
| Voice (opt-in `--voice`) | `npx hyperframes tts --voice af_heart`, Kokoro only; music ducks to 0.12 to 0.15 under the voice | Kokoro-82M weights Apache-2.0 (documented: [model card](https://huggingface.co/hexgrad/Kokoro-82M)) |
| Music | 5 bundled tracks, ende.app "Happy Beats / Business Moves" | CC BY 4.0, commercial use allowed, attribution optional, not to be registered with Content ID (documented: [ende.app licence](https://ende.app/en/standard-license)); brag's own `assets/music/README.md` says to "verify and document the exact music license terms" before redistributing, so it never did |
| Beat cues | Precomputed `*.music-cues.json/.md` per track (tempo, beat grid, `strongCues`), from `scripts/analyze_music_cues.py` (librosa `beat_track`, onset, RMS, bass band); fallback `npx hyperframes beats` | Script MIT; librosa ISC (inferred, not checked) |
| SFX | Kenney packs (casino, impact, interface, ui) plus 32 keypress WAVs, with `sfx-analysis.md/json` rating each file's brightness and high-frequency risk | CC0 (documented: `references/audio.md`) |

## Quality signals

- **Adoption**: 15,997 stars, 1,170 forks, 57 watchers, 10 open issues; 44
  commits from 2026-06-16 to 2026-10-13; 10 contributors, the author holds 22
  commits (measured: `gh api` on repo, commits, contributors). No releases, no
  CI workflows; one consistency script keeps `slim.md` identical to
  `brag-slim/SKILL.md` (measured: file listing).
- **Examples**: five benchmark fake-product sites under `examples/` (built with
  Impeccable) with rendered videos, all 1920x1080 H.264 plus AAC, 20.0 to 23.0
  s; the launch-site video is 1080x1920, 22.5 s; the brag-slim sample is
  1080x1080, 22.5 s (measured: `ffprobe` on each mp4).
- **Security**: skills.sh shows passed audits from Gen Agent Trust Hub, Socket
  and Snyk (documented: [skills.sh page](https://skills.sh/latent-spaces/brag/brag)).

## Fit with the map's settled decisions

| Map decision | brag | Gap |
|---|---|---|
| 1 to 5 min explainer, any source | 15 to 25 s hard cap, project code or URL | Its pacing rules assume 20 s; the planning shape scales, the numbers do not |
| Storyboard page is the human checkpoint | Storyboard is a Markdown file; the only human look is an optional `hyperframes preview` before render | No per-scene still, no approval loop, no partial redo |
| English plus Egyptian Arabic | Kokoro: American and British English, Japanese, Mandarin, Spanish, French, Hindi, Italian, Brazilian Portuguese; no Arabic (documented: [VOICES.md](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)) | Voice path unusable for Arabic |
| Word-timed captions plus SRT | None | Not covered |
| Ducked score by default | Music on by default, ducked only under voice | Close; its volume policy (bed 0.3 to 0.4, never above 0.5, SFX 0.55 to 0.85) is reusable |
| Style profiles | Visual identity extracted per run from the project's CSS (colours, fonts) and written into the plan | Extraction recipe is reusable; nothing is saved |
| Commercial-safe defaults | MIT skill, Apache renderer and TTS, CC0 SFX, CC BY music with attribution optional | Safe as shipped (inferred from the licences above) |

## What to adopt

Ranked by value to explainer-video (inferred from the source read above).

1. **The plan as a contract with a boundary.** One planning file (brief) owns
   story, copy, tone and moments; the renderer owns mechanics. brag's split
   between `brag-plan.md` and `composition-brief.md` maps onto the map's
   **Brief** and **Storyboard**. Copy the scene fields: on-screen content,
   sequential or simulated interaction, audio intent, transition mood.
2. **The grounding rule.** Any name, number, capability or quote on screen must
   appear in the source; framing, jokes and transitions are free. brag notes
   that a structural `check` cannot catch an invented claim, so it is a
   separate self-review step. For an explainer built from a repo or document
   this is the main correctness guard.
3. **The reading-time floor.** About 0.8 s settled for a short label, 0.3 s
   per word (minimum 1.2 s) for a sentence; pace comes from motion and cuts,
   not from pulling text early; sequential text snaps to every other beat at
   fast tempos. Directly reusable for captions and on-screen labels.
4. **Inspection rubric and colour and font extraction.** The 9 questions (minus
   the share caption) and the CSS custom-property recipe are a ready start for
   source ingestion and for drafting a style profile from a website.
5. **Precomputed music cues and an SFX analysis file.** Ship cue JSON beside
   each bundled track and rate every SFX file for high-frequency risk, so the
   model picks quiet, consistent sounds without listening. The librosa script is
   MIT and small.
6. **Poster as frame 0** with one ffmpeg overlay, plus the secrets rule (never
   carry keys, internal hosts or personal data into the video; swap in
   fictional stand-ins and say so).
7. **A single pre-render gate** that treats layout overflow and contrast as
   errors. If the renderer is HyperFrames, `hyperframes check` is that gate; if
   not, the storyboard's rendered stills need an equivalent check.

Do not adopt: the 15 to 25 s cap and its Hook, Reveal, Highlights, Punchline
shape (a launch-ad shape, not an explainer), Kokoro as the only voice, the tone
presets as written (parody and chaotic tones do not suit explainers), or
brag-slim's "build with whatever is on the machine" (unreproducible renders
make per-scene caching and revision impossible, inferred).

## Recommendation

Treat `/brag` as a reference for the planning and quality layer, not as a base
to fork. Lift items 1 to 6 above into the explainer-video spec (MIT, credit the
source in the skill's references). Decide the renderer separately: brag's
HyperFrames path is commercially safe (Apache-2.0) and the video lab already
has a HyperFrames project at `~/wip/projects/video-lab/hyperframes/`, so the
renderer ticket should weigh it there. Voice, captions, Arabic and the
storyboard approval loop all need designs brag does not have.

## Thin

- The video lab's HyperFrames verdict: no verdict file found under
  `~/wip/projects/video-lab/hyperframes/` (only `out/hyperframes.mp4`,
  `contact-sheet.jpg`, `render.log`), so brag's render quality on this machine
  is unmeasured.
- The example videos were probed for format only; their visual quality was not
  watched.
- ende.app's page is internally inconsistent (CC BY 4.0, which requires
  credit, yet "you do NOT have to credit me") and silent on redistributing raw
  files in a repository; bundling them in a public repo is unconfirmed.
- librosa's licence was not checked.
- Whether "the brag skill" the owner heard of is latent-spaces/brag is
  inferred from popularity and the "videos" hint; no direct source names it.
