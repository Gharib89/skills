# Three-arm comparison on one concept

Prototype for [#970](https://github.com/Gharib89/skills/issues/970) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.

Labels: **measured** (a command was run, named inline), **read** (read from a
session's own summary or source), **owner** (the owner's verdict, quoted),
**inferred** (my reading of the rest).

## Answer

The owner ranked, blind: **(b) plain "amaze me" 1st, (c) plain neutral 2nd,
(a) `explainer-video` 3rd** (owner).

1. **The ambition prompt is the skill's core, and freedom alone is not
   enough.** (b) beat (c) on the same plain Claude Code, so the prompt carries
   weight of its own (owner ranking). (b) also spent 2.6 times (c)'s output
   tokens, 125k against 48k (measured, session transcripts), and built a
   synthesised score, sound effects, particle text and a tilted 3D city where
   (c) shipped narration over HTML scenes (read). Inferred: the stance makes
   the agent reach, not just permits it.
2. **Today's `explainer-video` loses even to an unprompted plain run.** Owner:
   "boaring and the audio and pace is not energitic and not engaging". It was
   the only arm with cited sources and passing gates, so correctness did not
   buy engagement, matching #963 (skills raise correctness, not judged
   quality). Its own critic rated motion lowest, 2.1 of 5 (read).
3. **The winner still has a ceiling.** Owner on (b): "pacing, teaching and
   overall is the best of 3 but could be better, the sound effects is not the
   best and maybe the coloring". Sound design and palette are where a skill
   can add craft on top of the stance.

## Setup

One concept the owner named, "why agentic engineering", about 2 minutes,
English. Each arm ran once, in its own empty folder, in a Herdr tab on
Claude Opus 5.5, auto permission mode.

| Arm | Launch | Prompt |
|---|---|---|
| (a) | `claude`, normal config | `/explainer-video` + neutral text |
| (b) | `claude --safe-mode` | neutral text + "Make it attractive and engaging, and use a creative way to explain the concept and engage the audience. Amaze me." |
| (c) | `claude --safe-mode` | neutral text |

Neutral text: "Make a narrated explainer video, about 2 minutes long, in
English, on this concept: why agentic engineering. Render the finished video
to final.mp4 in this folder." `--safe-mode` turns off CLAUDE.md, skills,
plugins, hooks and MCP, matching the bar videos' no-skill conditions. (a)'s
storyboard was approved as-is, so no arm got a human edit pass. The owner
judged on a blind page (`creative-three-arm/screening-page.html`), the arms
shuffled into Video 1 to 3, all re-encoded the same way to 720p at about
14 MB; loudness within 1.2 dB (measured, ffmpeg `volumedetect`).

## Measurements

| Arm | Length | Session | Output tokens | Engine | Voice | Sound | Moving % | Events/min |
|---|---|---|---|---|---|---|---|---|
| (a) | 2:12 | 39 min, $9.81 | 85k (19 transcripts) | HyperFrames | Kokoro bf_emma | music | 7 | 1.8 |
| (b) | 1:58 | 39 min | 125k | canvas + Playwright | Kokoro af_heart | synthesised score, SFX | 30 | 0.5 |
| (c) | 2:02 | 58 min | 48k | HTML scenes + Playwright | Gemini TTS Charon | narration only | 17 | 5.4 |

Session time and tokens from each session's transcript (measured); cost only
where a status line showed it. Moving % and Events/min use the
`creative-bar-videos` method (ffmpeg scene scores at 10 fps; Moving % is the
share of steps at 0.002 or more, Events/min counts rises to 0.02 or more).
Events/min under-reads continuous motion: (b) almost never drops below 0.02,
so Moving % is the column to trust here (inferred). For reference: game show
18 % and 15.2, ship explainer 7 % and 1.6.

## Notes

- (c)'s Gemini free tier ran out on its last scene, which uses a lighter
  backup model (read). The owner gave (c) no note.
- Each arm ran once, on one concept: a direction, not a measured effect size.
- Kept here: each arm's narration script (and (a)'s outline and brief). Scene
  code and the videos stay in the owner's local workspace.
