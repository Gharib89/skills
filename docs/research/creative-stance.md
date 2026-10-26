# The ambition stance's wording

Prototype for [#974](https://github.com/Gharib89/skills/issues/974) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.

Labels: **measured** (a command was run, named inline), **read** (read from the
run's own files or summary), **owner** (the owner's verdict, quoted),
**inferred** (my reading of the rest).

## Answer

The drafted stance beat the three-arm winner, plain Claude Code told to "amaze
me", in a blind A/B (owner: ranked 1st; "both are good videos and each
approached it from different style", "I think this video is better overall").
The stance, with three edits the owner agreed after the screening, is the
skill's core text: [`creative-stance/STANCE.md`](creative-stance/STANCE.md).
The version that ran is [`STANCE-as-run.md`](creative-stance/STANCE-as-run.md).

1. **The stance keeps the reach and adds the teaching.** The run staged the
   wrong idea (a rookie cook: "just send it all out"), held two "make your
   call" pauses before answers, said where its metaphor breaks, and traced
   every fact in `SOURCES.md` (read, `run/SPEC.md`, `run/SOURCES.md`). It did
   not lose the energy that won the three-arm round (owner ranking).
2. **It moved off the default look.** "Amaze me" landed on a dark navy ground
   with cyan neon glow, the first item on `hyperframes`' BANNED list (read,
   contact sheet). The stance run took its palette from its concept's world:
   steel, tile and paper, with red, green and amber meaning fail, pass and
   wait (read, `run/SPEC.md`). Different styles from the same request are the
   point: the stance names no look (inferred).
3. **Sound: recorded effects tied to story events, plus a low bed.** No
   synthesised tones; 15 recorded CC0 kitchen sounds from Freesound plus a
   room-tone bed, each marking one event;
   22 of 24 hits peak 31 to 35 ms after their picture (read, the run's own
   measurement). Owner: "a background sound that is low makes the videos more
   interesting", so the stance now makes a low bed the default, out for the
   hardest step.
4. **It costs about twice as much.** 260k output tokens against 125k (measured,
   transcripts incl. the subagent), about 83 minutes of work against 39.

## Edits after the screening (owner agreed)

- **A concept, not always a world.** A concept is a world, a format, or the
  subject drawn directly when that teaches better than any metaphor (the
  forced-metaphor distortion #969 found). The agent writes three directions
  that differ in kind, one bold, one the direct drawing when it fits,
  recommends one, and **the person picks**; with nobody there, the agent takes
  its recommendation and writes down why. Owner asked whether the agent
  should pick alone or ask; the answer is always offer three, because the
  agent judging "only one fits" is where the default creeps back, and the pick
  fixes arc, cast, sound and colour before a run that cost over $10.
- **A low bed by default**, drawn from the concept's world, well under the
  voice, out for the hardest step (owner; reconciles #969's music finding,
  which measured music under the whole explanation).
- **Facts still current.** The run built its reveal on METR's 2025 slowdown
  study and left out the authors' later update; Claude Code's own notice
  flagged it (read). The facts line now asks whether the source still stands.

## Setup

| Arm | Launch | Prompt |
|---|---|---|
| (b) three-arm winner | `claude --safe-mode` | neutral text + "Make it attractive and engaging ... Amaze me." |
| (d) stance | `claude --safe-mode`, Opus 5.5, auto mode | neutral text + "Before anything else, read ./STANCE.md and work by it. Nobody is available to choose for you: wherever it says to pick, pick yourself and write down why." |

Neutral text as in #970. The folder held `STANCE.md` and a copy of the pinned
`hyperframes` and `hyperframes-cli` skills as plain files (safe mode turns
skills off; the new skill composes `hyperframes`). In the shipped skill, the
stance's `./hyperframes/` pointer becomes the composed skill.

Both videos re-encoded to 720p at about 14 MB with the same two-pass settings,
loudness normalised (measured: −15.9 and −16.0 LUFS, ffmpeg `ebur128`), order
shuffled, judged on [`screening-page.html`](creative-stance/screening-page.html).

## Measurements

| Arm | Length | Output tokens | Engine | Voice | Moving % | Events/min |
|---|---|---|---|---|---|---|
| (b) | 1:58 | 125k | canvas + Playwright | Kokoro af_heart | 30 | 0.5 |
| (d) | 2:12 | 260k | HyperFrames | Kokoro af_heart | 38 | 29.0 |

Moving % and Events/min by the #962 method (measured, ffmpeg scene scores at
10 fps). Reference: game show 18 % and 15.2.

## Caveats

- One run per arm, one concept: a direction, not an effect size. The owner
  rated both good.
- The stance run was killed once by an out-of-memory event from another
  process on the machine and resumed with one message ("continue"); (b) had
  no such message.
- No ablation: which clause did the work is unmeasured.

## Kept here

`STANCE.md` (revised), `STANCE-as-run.md`, the run's `SPEC.md`,
`STORYLINES.md`, `SOURCES.md` and `REVIEW.md` under `run/`, and the screening
page. Scene code and videos stay in the owner's local workspace. The run's
files are verbatim except em dashes, replaced with hyphens for the repo's
house-style check.
