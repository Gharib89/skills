# Explainer visual directions (PROTOTYPE, never merged)

Throwaway prototype for the wayfinder ticket
[Visual directions storyboard on dora-core](https://github.com/Gharib89/skills/issues/777).
It answers which visual direction `explainer-video` takes by default.

Verdict (owner, 2026-10-17): **B, Velocity Cut**, is the default look, with room
for the agent to be creative by topic and style. A safe default is not a
restriction.

Published page: https://claude.ai/artifact/JcSo7v4noea9KnTnkfKNjq

## What is here

- `storyboard.html`: the built page. It has five directions over three
  `dora-core` scenes (hook, trails, integrate), synced to 72.5 s of their real
  narration (`film.mp3`, word timings in `scenes.json`).
- `shell.html`: the page. Inside it, `H` holds the cue helpers, the player, the
  storyboard cards, the side-by-side sheet and the pick form.
- `dir-a.js` to `dir-e.js`: one direction each.
  - A: Infinite Canvas.
  - B: Velocity Cut.
  - C: Word Stage.
  - D: Depth Stack, live Three.js.
  - E: Catalog Kit, HyperFrames registry items as shipped.
- `build.py`: inlines the fonts, the audio, the scene data and the directions.
  - `python3 build.py` writes `storyboard.html`.
  - `python3 build.py B` writes `preview-B.html`, holding that one direction.
  - It reads narration and props from
    `explainer-videos/explainers/dora-core/script.md`, an absolute path.
- `contact.mjs`: a headless contact sheet of one direction at set times.
  - Run it as `node contact.mjs B out.png [times...]`.
  - It needs `puppeteer-core` in `node_modules` and a `vendor/` folder holding
    `gsap`, `CustomEase` and `three`.
  - It uses the Playwright headless shell path inside the script.
