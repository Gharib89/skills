# What made the bar videos work

Research for [#962](https://github.com/Gharib89/skills/issues/962) on the map
[#961](https://github.com/Gharib89/skills/issues/961). Date: 2026-10-26.
Builds on `research/explainer-motion-refs` (#773: narrated explainers build,
they do not cut), the visual vocabulary resolution (#796: custom scenes beside
components, five hard rules) and the current `skills/explainer-video/`.

The two bar videos are both Remotion projects that Claude Code made with no
video skill: **the WILL IT RUN? game show** (5:32, on Claude Code permissions)
and **the ship skill explainer** (33:49, on the `ship` skill). Their sources
live in the owner's local workspace; files are named below by
project-relative path. No frames are committed.

Labels: **measured** (a command was run, named inline), **read** (read from
the project source, the build session's transcript, or this repo), **inferred**
(my reading of the measured or read material).

## Answer

Ranked by how much each finding should change the new skill's design.

1. **The game show's win is one format concept, chosen before any scene, that
   every layer then obeys.** "A game show where you are the contestant" set the
   arc (cold open, how to play, warm-up, rounds, lightning round, final round,
   scoreboard, challenge), the audience device (five questions with a spoken
   3-2-1 countdown and an always-on score HUD), the cast (a host plus an
   announcer for round stings), the sound (buzzer for blocked, ding for runs),
   the colour semantics (green runs, amber asks, red blocked, used everywhere)
   and the furniture (stage spotlights, marquee bulbs, round banners) (read:
   `src/explainer/Explainer.tsx`, `src/explainer/theme.ts`,
   `src/explainer/kit.tsx`, `script/explainer.json`). `explainer-video` fixes
   the arc to hook, context, point, recap, end, gives one narrator per brief,
   and places only two sound effects itself (read: `SKILL.md` Script and Brief,
   `scripts/score/score.mjs`). So the skill's first creative act should be the
   agent choosing a frame for the whole video, and the plumbing must let that
   frame own the arc, the cast, the sound cues and the palette (inferred).
2. **The game show changes the picture three to four times as often, without
   cutting.** 15.2 visible change events a minute and 18 % of frames in motion,
   against 0.9 to 3.9 events and 5 to 7 % for three `explainer-video` renders,
   and 4.6 events and 8 % for a deck-presenter video the same agent built in
   the same project the session before (measured, ffmpeg scene scores, table in
   [Pacing](#pacing-and-density)). The ship explainer sits in the
   `explainer-video` band, 1.6 events and 7 % (measured), so motion density is
   the game show's edge alone. Hard cuts stay near zero in all of them, so
   #773's "build, don't cut" holds; the gap is how many things happen inside a
   held frame. The mechanism is sub-sentence timing: each visual event is a
   narration line's start plus a hand-tuned offset in seconds
   (`beatsOf(id)[i] + s(1.4)`), so the fridge scene runs about ten timed events
   in 32 s, and the countdown ticks land on the spoken "three, two, one",
   measured with `silencedetect` (read: `src/explainer/timeline.ts`,
   `src/explainer/ScenesA.tsx`, session summary). `explainer-video`'s motion
   rule ("one element moves at a time", UI moves at most about 250 ms) and its
   cue grain (a sentence, or a phrase of it) push the other way (read:
   `reference/recipes.md`).
3. **The two bars are opposite recipes, and only one of them is "freedom".**
   The game show is 12 bespoke scene components (1,249 lines, about 104 a
   scene) over a 499-line show kit the agent wrote for this video (measured,
   `wc -l`). The ship explainer is a closed vocabulary: its style guide says
   "the build implements exactly these" 14 component names, scenes are YAML
   specs written by parallel chapter subagents, and over 45 scenes `flow` is
   used 17 times and `table` 14, while `kinetic`, `quiz` and `filetree` appear
   once each (read: `STYLE.md`; measured, a count over `public/script.json`).
   What makes the ship explainer strong is structure and depth, not per-scene
   freedom or motion: the rail, the chapter frame, the citations, diagrams with
   the real content (findings 2, 6 and 9). The map's "maximum
   freedom" stance is supported by the game show alone (inferred).
4. **The ship explainer's "amaze me" brief was written by an agent, not by
   the owner.** The owner's draft said only "use diagrams pictures ... amaze me
   with the video and the power of visual design and effects"; a prompt
   enhancement session expanded it into the specific list (persistent phase
   rail, one accent per phase, flowcharts, sequence and state diagrams, a
   zoomable file tree, typing terminals, code callouts with `file:line`,
   kinetic type, springs, parallax, particles), grounded in the real file list
   of `skills/ship/` (read: the drafting session's transcript). The game show
   prompt was one sentence, "attractive engaging and uses creative way to
   explain the concept and engage the audience", beside the lesson deck (read:
   its session). So in both cases the art direction came from an agent writing
   a concrete plan from the material; the ambition stance can ask for that
   plan as an artifact the owner sees (inferred).
5. **Metaphors are drawn as objects only where an action needs showing; the
   rest live in the narration.** Drawn and acted: CLAUDE.md as a sticky note
   that falls off a CSS-drawn fridge while the agent orb reaches past it, then
   a gold chain and padlock slam on and bounce the agent (`Fridge`); `bash -c`
   as a trench coat with sunglasses and a "bash" name tag that a hook X-rays to
   reveal `rm -rf` (`Disguise`, `Hook`) (read: `src/explainer/ScenesA.tsx`,
   `src/explainer/ScenesB.tsx`). The club door staff and the gears are three
   verdict cards with a walker and three mode cards: the metaphor is in the
   host's lines and the labels ("The banned list", "Learner's permit",
   "Cruise control") (read; frames). Every object is CSS divs, one inline SVG
   and literal hex colours (fridge `#e9e6f6`, note `#ffe76a`): no images, no
   library (read). `explainer-video`'s compile lint refuses literal colours in
   a custom scene, which a drawn fridge or note needs (read:
   `reference/recipes.md`, #796's five hard rules).
6. **The ship explainer's long-form spine is portable plumbing.** A phase rail
   0 to 9 on every scene after the cold open, lit by the scene's `phase:` field
   and driven event by event in the replay, with the focused cell pulsing
   (`src/Rail.tsx`); a header with chapter chip and scene title; a source chip
   showing the `file:line` behind what is on screen, changing with the
   narration (`src/SceneView.tsx`); 3 s chapter cards with a riser and chime;
   12-frame cross-fades between every item (`src/plan.ts`, `src/Mix.tsx`); a
   background of a drifting grid plus 70 seeded particles whose speed and size
   scale with a depth value, tinted with the focused phase's accent
   (`src/Background.tsx`) (read). The map calls it "two-depth" parallax; the
   code's comment says two depths, but `depth` is continuous from 0.3 to 1.0
   per particle (read). These are video-level layers above the scenes, which
   `explainer-video` has no slot for beyond sections (inferred).
7. **Sound effects carry meaning in the game show and only punctuation in the
   ship explainer.** The game show synthesises a 116 BPM game-show bed and
   seven effects in one numpy script, adds one downloaded record scratch, and
   places 29 cues inside scenes on story events: buzzer on a blocked verdict,
   ding on runs, ticks on each countdown number and each gear shift, a thud on
   impact, a record scratch freeze on "Wait. All of Bash?" (read:
   `scripts/music_show.py`, a grep of `<Sfx` in `src/explainer/`). Music sits
   at 0.1 under the voice, 0.22 in gaps and 0.34 under the closing logo
   (`Explainer.tsx`). The ship explainer puts effects only in silences:
   a whoosh between scenes, riser and chime on chapter cards, a success sting
   at the outro; its `pop` and `tick` files are generated and never used (read:
   `src/Mix.tsx`, `scripts/gen-music.py`). `explainer-video` places a whoosh at
   each cut and one sting at the end, capped per minute (read:
   `scripts/score/score.mjs`).
8. **A two-voice cast cost one config block.** Host and announcer are two
   instruct strings on the same local TTS (`female, young adult ... american
   accent`, seed 23; `male, middle-aged, very low pitch`, seed 5, speed 0.82);
   the announcer speaks five lines, all format stings ("Round one!",
   "Lightning round!"); a voice change adds a 0.7 s gap against 0.38 s within a
   speaker (read: `script/explainer.json`, `scripts/voice.py`). Takes are
   cached by a hash of text plus voice, verified by transcribing back, and a
   bad take is fixed by a per-line seed override: 11 of 59 takes came out
   garbled or near silent, and one line had to be reworded (read: session
   summary). So a cast is a speaker field per line plus per-line overrides
   (inferred).
9. **Truth: the ship explainer cited every sentence and the visuals stayed
   free of that rule.** Every narration sentence ends in fact IDs or
   `[no-claim]`; fact sheets came from parallel reader subagents with
   `file:line` on each fact; three fact-check agents compared each sentence to
   its cited facts and fixed 34 problems; six unclear points became on-screen
   "open question" badges (read: `STYLE.md`, `OUTLINE.md`, session messages).
   The game show had no citation step; the agent reported that only the
   terminal text and Claude's on-screen reply were invented (read: session).
   This answers the map's open point "facts traced to sources while metaphors
   stay free": cite the sentence, not the picture (inferred).
10. **Neither bar had a storyboard; both reviewed stills.** The game show had
    zero owner turns between prompt and render; the agent rendered contact
    sheets of every scene, found about ten layout bugs (a wrapped logo, a
    flash showing early, overlapping badges, overflowing text) and fixed them
    (read: session summary). The ship explainer had owner checkpoints at the
    outline, the script ("you can get creative") and the voice, and the same
    stills review per chapter (read). Both derived scene length from measured
    audio, as `explainer-video` already does (read).

## Pacing and density

Method (measured), the same as #773 so the numbers compare:
`ffmpeg -vf "scale=320:-2,select='gt(scene,0.3)',showinfo"` for hard cuts;
per-frame `lavfi.scene_score` at 10 fps for the rest. "Changes/min" counts
steps scoring 0.1 or more (#773's threshold); because the scene score
under-reads motion on dark grounds (#773's caveat) and all these videos build
rather than cut, "Events/min" also counts each rise to 0.02 or more, and
"Moving %" is the share of 0.1 s steps scoring 0.002 or more. The
`explainer-video` rows are the three newest renders on this machine (two
consumer runs and one owner video, all from 2026-10-17). Words a minute come
from the narration text over the timeline length.

| Video | Dur s | Cuts/min | Changes/min | Events/min | Moving % | Words/min |
|---|---|---|---|---|---|---|
| WILL IT RUN? game show | 332 | 0.2 | 2.5 | 15.2 | 18 | 153 |
| Ship skill explainer | 2029 | 0.0 | 0.0 | 1.6 | 7 | 154 |
| Deck presenter (same project, same agent) | 596 | 0.6 | 2.0 | 4.6 | 8 | |
| explainer-video, 16 min owner video | 979 | 0.0 | 0.7 | 3.9 | 5 | |
| explainer-video, http-caching | 130 | 0.0 | 0.0 | 0.9 | 5 | |
| explainer-video, readme-overview | 61 | 0.0 | 0.0 | 1.0 | 7 | |

Scene shape (measured from each project's timeline JSON):

| | Scenes | Median s | Range s | Lines | s a line |
|---|---|---|---|---|---|
| Game show | 12 | 29.2 | 15.0 to 40.1 | 59 | 5.6 |
| Ship explainer | 45 | 40.6 | 12.6 to 97.9 | 469 | 4.3 |
| `explainer-video` rule | | | 12 to 30 per scene | | |

Four of the game show's twelve scenes and 37 of the ship explainer's 45 run
past `explainer-video`'s 30 s scene ceiling (measured).

Density (read and inferred from contact sheets of 16 frames each): the game
show fills the frame with large type (headlines 76 to 84 px, commands 52 to
64 px, display face Bungee) and saturated objects on a night-stage ground; the
ship explainer packs small text (body at least 22 px, labels 20, chips 18 by
its own brief) into diagrams and tables under a rail; the `explainer-video`
owner video shows grey cards and small type on a mostly empty white frame.

## Technique catalog

Where each lives, and whether it needs freedom the skill must keep
(**freedom**: the agent must be allowed to author it; **plumbing**: the skill
can supply it; **gate**: a defect check can police it).

| Technique | Video | Where | Kind |
|---|---|---|---|
| One format concept owning arc, cast, sound, palette | Game show | `Explainer.tsx`, `theme.ts`, `script/explainer.json` | freedom |
| Audience as contestant, five scored questions, 3-2-1 countdown, HUD pips | Game show | `kit.tsx` `AnswerBoard`, `HUD` | freedom (device), plumbing (word-timed countdown) |
| Physical metaphor drawn and acted (note falls, lock slams, coat X-rayed) | Game show | `ScenesA.tsx` `Fridge`, `ScenesB.tsx` `Disguise`, `Hook` | freedom, incl. literal colours |
| Metaphor carried by narration plus labelled cards | Game show | `Door`, `Modes` | freedom |
| Sub-sentence event timing (line start plus offset) | Game show | `timeline.ts` `beatsOf`, `absBeat`, `segEnd` | plumbing (word timings), freedom (choreography) |
| Verdict colour semantics used everywhere | Game show | `theme.ts` `X.runs/asks/blocked` | freedom |
| Story-event sound effects (buzzer, ding, scratch, ticks) | Game show | `<Sfx>` calls in scene files, `scripts/music_show.py` | plumbing (library, placement API), freedom (where) |
| Two-voice cast by instruct string and seed | Game show | `script/explainer.json`, `scripts/voice.py` | plumbing |
| Music ducking from voice intervals | Both | `Explainer.tsx` `musicVolume`, `src/Mix.tsx` | plumbing (exists) |
| Self-made show kit (stamp, banner, code card, bulbs, spotlights) | Game show | `kit.tsx` | freedom |
| Persistent progress rail, lit per scene and per replay event | Ship | `src/Rail.tsx` | plumbing (a video-level layer slot), freedom (what it shows) |
| Source chip with live `file:line` | Ship | `src/SceneView.tsx` `SourceChip` | plumbing |
| Chapter cards, riser and chime, cross-fades | Ship | `src/plan.ts`, `src/Mix.tsx`, `src/Cards.tsx` | plumbing |
| Particle and grid background with depth, phase-tinted | Ship | `src/Background.tsx` | freedom (look), plumbing (seeded, deterministic) |
| Sentence-cited narration, fact sheets, fact-check agents, open-question badges | Ship | `STYLE.md`, `facts/`, `src/components/OpenQ.tsx` | plumbing and gate (exists in `explainer-video`) |
| Closed component vocabulary filled by YAML | Ship | `STYLE.md`, `src/Visual.tsx` | the opposite of freedom |
| Stills contact-sheet review loop | Both | session transcripts | gate |

## Caveats

- The ship explainer's project was edited in place after the bar render for a
  second version (`Main.tsx`, `Captions.tsx`, `theme.ts`, `types.ts`,
  `components/Flow.tsx` are newer than `out/ship-explainer.mp4`), so a few
  read details may describe the second version (measured, file times). The
  rail, background, mix, plan and scene files predate the render.
- The game show was not watched end to end for this ticket; claims about it
  come from source, the session, the contact sheet and the scene scores.
- The deck-presenter control answered a different ask (a teaching rehearsal
  with simulated interruptions), so it bounds the agent's default, not a
  same-brief A/B.
- The scene score under-reads small moves on dark grounds, which both bar
  videos use, and small reveals inside a dense frame; the ship explainer's
  text reveals are likely undercounted, and the 16 min `explainer-video` owner
  video is on a white ground (inferred from #773's caveat and the frames).
