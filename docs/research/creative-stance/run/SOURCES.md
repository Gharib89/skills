# Sources

## Facts on screen and in the voice

| Claim (where) | Source |
| --- | --- |
| Karpathy coined "vibe coding": "I 'Accept All' always, I don't read the diffs anymore" … "not too bad for throwaway weekend projects" (vibe, 21–30 s) | Andrej Karpathy on X, 2 Feb 2025: https://x.com/karpathy/status/1886192184808149383 (text read through the public syndication endpoint `cdn.syndication.twimg.com/tweet-result?id=1886192184808149383`) |
| METR randomised trial: 16 experienced open-source developers, 246 real issues, AI allowed on a random half; tasks took 19 % longer with AI; afterwards developers believed AI had sped them up by 20 % (call, 30–55 s) | METR, "Measuring the Impact of Early-2025 AI on Experienced Open-Source Developer Productivity", 10 Jul 2025: https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/ |
| The length of task an agent finishes alone, half the time, has doubled about every 7 months (bigger, 59–66 s). "70 months ≈ 6 years" is 10 doublings × 7 months; the ticket sizes are illustrative, which the frame says on screen | METR, "Measuring AI Ability to Complete Long Tasks", 19 Mar 2025: https://metr.org/blog/2025-03-19-measuring-ai-ability-to-complete-long-tasks/ |
| "An agent is a model, using tools, in a loop, checking against the real world at every step" (pass, 69–75 s) | Anthropic, "Building effective agents" (agents get "ground truth from the environment at each step", using tools in a loop): https://www.anthropic.com/engineering/building-effective-agents |
| `0.1 + 0.1 + 0.1` is `0.30000000000000004` in JavaScript (pass, 83–96 s) | Checked by running `node -e "console.log(0.1+0.1+0.1)"` → `0.30000000000000004` |
| Karpathy, Feb 2026, naming "agentic engineering": "personally my current favorite 'agentic engineering'" … "'agentic' because the new default is that you are not writing the code directly 99% of the time, you are orchestrating agents who do and acting as oversight" … "'engineering' to emphasize that there is an art & science and expertise to it" (name, 110–124 s) | Quoted in Glide, "Agentic engineering glossary": https://www.glideapps.com/blog/agentic-engineering-glossary (secondary source; the original X post could not be fetched; the same wording appears in https://aibuilderclub.com/blog/karpathy-agentic-engineering) |

The `applyCoupon("SAVE10")` row in scene 6 is an invented example, not a fact. It shows a passing test missing a bug.

Not used: METR's Feb 2026 update (https://metr.org/blog/2026-02-24-uplift-update/). It reports a later, different setup. The film quotes only the 2025 trial and dates it on screen ("METR · EARLY 2025").

## Sounds (all recorded; none generated)

| File | Source | Author | Licence |
| --- | --- | --- | --- |
| `printer_a.wav` | https://freesound.org/s/16942/ | cognito perceptu | CC0 |
| `printer_b.wav`, `printer_long.wav` | https://freesound.org/s/345057/ (0–1.7 s, 0–3.4 s) | azumarill | CC0 |
| `scrape.wav` | https://freesound.org/s/634156/ | Erbsland-Music | CC0 |
| `bell_a.wav` | https://freesound.org/s/398281/ | FlashTrauma | CC0 |
| `bell_b.wav` | https://freesound.org/s/221515/ (from 0.2 s) | AlaskaRobotics | CC0 |
| `crumple.wav` | https://freesound.org/s/197179/ (0.45–2.45 s) | razrox | CC0 |
| `tape_a/b/c.wav` | https://freesound.org/s/742620/ (at 0.80 / 1.78 / 2.30 s) | WaltzOfTheWifi | CC0 |
| `timer_ticks.wav` | https://freesound.org/s/204103/ (1.9–5.4 s) | maphill | CC0 |
| `bed_kitchen.wav` | https://freesound.org/s/766292/ | Freesound user 241051 | CC0 |
| `sizzle.wav` | https://freesound.org/s/353124/ | BenjaminNelan | CC0 |
| `plate_a/b/c.wav` | Kenney "Impact Sounds" (`impactPlate_light_000–002`), https://kenney.nl/assets/impact-sounds | Kenney | CC0 |

The licence of each Freesound clip was checked on its page. Edits: trims, and peak normalisation to −3 dBFS (−6 dBFS for the bed and sizzle).

## Voice, fonts, code
- Voice: Kokoro-82M (Apache 2.0), run locally through `kokoro-onnx`. Narrator voice `af_heart`; Sam is `am_michael`.
- Fonts: IBM Plex Mono (SIL OFL 1.1), Permanent Marker (Apache 2.0).
- Rendering: HyperFrames 0.8.204, GSAP 3.14.2.
