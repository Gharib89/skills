# What makes Claude Code make great motion videos

Research for [#963](https://github.com/Gharib89/skills/issues/963) on the
[creative video skill map](https://github.com/Gharib89/skills/issues/961),
gathered 2026-10-26. Upstream pins read: `remotion-dev/skills` at `30d4553`
(skills version 4.0.539) and `heygen-com/hyperframes` at `575f68c`.

Labels on every claim:

- **measured**: a count, eval or diff someone ran, with its owner named (HeyGen's
  eval, or my own read of a pinned commit).
- **sourced**: a primary source says or shows it (the author's own post, video
  or repo; the vendor's own docs). Where a source shows a result next to its
  prompt, the claim says **shown**; where it only reports one, **claimed**.
- **inferred**: my reading for the new skill, with no direct proof.

## Answer, ranked by how much it changes the new skill

1. **The taste is already in the model; what skills add is correctness, and
   what fails is the default look when nothing is decided.**
   - HeyGen's own eval for the pack rewrite
     ([PR #5651](https://github.com/heygen-com/hyperframes/pull/5651)): on
     Sonnet 5.5, 19 cases x 2 repeats, skills lifted correctness and tool
     use from 11% to 71%. A blind judge scoring frames only gave
     6.86/6.94 without the skills and 7.21/7.11 with them, a gap the PR says
     "swings between runs" (measured by HeyGen).
   - The PR's own rationale: "Strong coding agents plan, sequence and check
     their own work; what they lack are private facts" (sourced).
   - Opus 5.5 videos made from short prompts with no skill exist and are
     shown (table below), and the owner's two bar videos came from bare
     Claude Code (sourced, the map).
   - Without direction the model lands on one look. Rexan Wong: "without a
     reference, opus falls back to its default look: centered text, gradient
     background, everything fading in" (sourced). Anthropic's frontend-design
     post names the same convergence for web UI and fixes it by naming the
     defaults to avoid (sourced).
   - **For the skill (inferred):** craft content should force decisions,
     not supply a style: divergent concepts, adjectives turned into numbers,
     the defaults banned by name, and the agent looking at its own frames.
     That fits the map's maximum-freedom stance; a prescribed house style
     would fight the model's own taste and reproduce one look.

2. **Looking at rendered frames is the one workflow every serious source
   repeats.**
   - Claude reads images, not video, so frames are how it sees its own work
     (sourced: ReelStack, which turns references into frames with ffmpeg at
     4 fps).
   - HyperFrames' loop ends every film in `snapshot --review`: three sheets,
     one at 360 px phone width. Each frame is described "as a stranger
     would", and the film is "never" scored out of 10. A fresh-eyes
     subagent reviews, and notes are ranked P0/P1/P2 into `REVIEW.md`
     (sourced, `references/review.md`).
   - Its `check` warns on `dead_stretch` (over 3 s with nothing changing),
     `line_unread`, `text_below_floor`, `first_frame_empty` and `film_silent`
     (sourced).
   - snapcn, interpt and reelcn each say to render stills or a contact sheet
     and review them before the full render (sourced, vendor posts). In one
     CTOL report, Claude rendered test frames and caught overflowing text, a
     broken logo and a wrong gradient (claimed).
   - Jonny Burger's own session shows the failures a frame look catches: a
     flickering glitch effect from unseeded randomness, and subtitle words
     glued together (shown).
   - **For the skill (inferred):** frame review is the defect gate's natural
     home, and the stranger-description rule keeps it honest.

3. **Ambition wording works only when it carries direction.**
   - Anthropic's prompting guide says to ask for ambitious work explicitly,
     "Go beyond the basics", and models it with "Don't hold back. Give it
     your all." (sourced).
   - The viral prompt is a persona plus a bar plus permission: "Make a
     dynamic 15-second motion graphics video that shows what an incredible
     motion designer you are, like it is your showreel for a résumé. Go all
     out." Charlie Hills and CTOL report it working with no skill in about
     10 minutes for about $2 (claimed, self-reported).
   - Rexan Wong's own one-prompt video "looked mid"; what fixed it was a
     reference video, real UI parts and full context (sourced). A
     framework posted on X the day of writing puts the same thing first: a
     brief with length, aspect ratio, story and "2-3 reference videos you
     like", before any code (sourced, @aiedge_).
   - Claude Motion's own tip: "Say who will watch it, where it will play,
     and roughly how long" (sourced).
   - HyperFrames' prompting guide: "Density never hurts, a stronger model
     just uses less of its own taste" (sourced).
   - **For the skill (inferred):** the ambition stance should set a bar and
     an audience and grant permission, then have the agent write its own
     dense spec (the SPEC.md move). The human then never has to write a
     9,000-character brief.

4. **Diverge, then pick, before anything moves.**
   - HyperFrames `story.md`: "Most weak films are good motion around no
     story". Sketch 5 or more ideas, keep 3 storylines that are three
     different films, in words only, and "Make one of the three the bold
     one you would not have picked first". The person picks (sourced).
   - Rexan Wong makes 3 storyboard variants and one still per scene before
     anything moves (sourced). MaizeCobra's director skill gets a design doc
     approved before the build (sourced). Sabrina Ramonov's prompt asks for
     script approval first (sourced).
   - **For the skill (inferred):** the map's storyboard approval should show
     divergent options, one deliberately bold, as stills. One concept to
     approve or reject is weaker.

5. **"One prompt" showcases hide long briefs and long sessions.**
   - Nikandr Surkov reviewed about 100 viral Opus 5.5 videos. Many "one
     prompt" videos were 10,000 characters plus skills; the Claude Pop brief
     ran over 9,000 characters plus about 12 hours of work; one 45-second
     short took 163 calls, about $34 and about 7 hours (claimed, reported by
     ReelStack).
   - The awesome-opus-5-5-videos collection (424 source posts) finds public
     briefs from 172 to 17,664 visible characters; the Braun turntable
     film's author describes nine days with several human decisions
     (sourced, the collection's own analysis).
   - **For the skill (inferred):** the bar videos from a bare "amaze me" are
     the exception worth studying. The skill should budget for many
     revision passes, not one shot.

6. **Directing a revision works with absolute targets, one change at a
   time.**
   - HyperFrames' prompting guide: one variable per edit, absolute targets,
     "Give every second a job", and "agents skip breathing room unless told"
     (sourced). Its motion guide shows A/B films that differ by one prompt
     line (shown, by the vendor).
   - Rexan Wong gives director notes such as "slow every zoom to 0.7x"
     (sourced).
   - **For the skill (inferred):** a self-review should end in numbered,
     timestamped director notes with absolute values. "Make it pop" is not
     a note.

7. **Community style packs contradict each other, so gates should judge
   outcomes, not taste.**
   - The MotionSites Remotion skill mandates "Idle elements breathe" and a
     five-layer stack with grain and mesh (sourced). HyperFrames lists
     breathing loops among "Defaults that look generated" and bans glow,
     particles and glass cards by default (sourced).
   - Many prompts in Remotion's own showcase ask for exactly those banned
     looks: a glassmorphism HUD, particles, corner brackets, a dark theme
     (sourced; the contradiction is inferred).
   - **For the skill (inferred):** hard gates belong on defects anyone would
     call defects (clipped text, dead stretches, flicker, unread lines). A
     banned-defaults list is a starting point the agent may override with a
     stated reason, matching "The list grows with every film" (sourced,
     `spec.md`).

8. **Remotion's pack teaches correctness and editability; HyperFrames'
   carries most of the craft. Neither settles the engine.**
   - In `remotion-dev/skills` at `30d4553`, the only design prose is
     `remotion-create/video-layout.md`: 9 lines. It says "You are designing
     a video, not a webpage", asks for one focal thing per scene, and sets a
     safe area and text minimums (headline 84 px, supporting 44 px at 1080
     wide) (measured, my read of the pinned tree).
   - The rest of that pack covers frame-driven animation, Studio-editable
     structure, text measuring and transitions (measured, same read).
   - Burger says to invoke the best-practices skill explicitly, because
     Claude does not always pick it up (shown).
   - The HyperFrames craft (`story.md`, `spec.md`, `review.md`, `motion.md`)
     is prose about films, not about its API (sourced).
   - **For the skill (inferred):** craft knowledge can be written
     engine-neutral and carried into either engine.

## What changed since the earlier tickets

- HyperFrames PR #5651 (merged 2026-10-21) cut the published pack from 21
  skills to 7 "knowledge skills". It retired the workflow skills, including
  `faceless-explainer`, whose `motion-language.md` [#772](https://github.com/Gharib89/skills/issues/772)
  cited (sourced). Its craft now lives in the `hyperframes` skill's
  references (story, spec, review, motion).
- Our vendored copy under `.claude/skills/hyperframes/` (at `683e9b1`) already
  carries `story.md`, `spec.md` and `review.md`; it differs from `575f68c`
  only in `references/runtimes.md` (measured, `diff -r`).
- Claude Motion launched 2026-10-08 as a Team and Enterprise beta:
  code-based animation with MP4 export and no video model (sourced).
- Opus 5.5 (2026-09-22) started a wave of shared motion videos. Video was not
  a launch headline; the launch post cites a one-prompt game's "graphics and
  polish" (sourced).

## Showcases: prompt, result, and what is shown versus claimed

| Showcase | Prompt published | Result | Basis |
| --- | --- | --- | --- |
| Showreel prompt ([Charlie Hills](https://charliehills.substack.com/p/claude-code-motion-graphics), [CTOL](https://www.ctol.digital/news/claude-opus-5-5-ai-video-model-to-studio/)) | Yes, one sentence | Clips in the posts; no skill, about 10 min, about $2 | Prompt and clip shown; cost and time claimed |
| Kevin Ngo's watermelon short, [Anthropic launch thread](https://x.com/kevin_t_ngo/status/2102761406315839798) | No | About 1.39M views; "animated in Python and rendered in Blender by Claude Opus 5.5" | Result shown, process claimed |
| [Rexan Wong thread](https://x.com/rexan_wong/status/2103707054108299437) | Partly; workflow described | One-prompt version "looked mid"; reference-led version shown | Both shown, workflow claimed |
| [Remotion Prompt Showcase](https://www.remotion.dev/prompts) | Yes, full specs (one is an 8-scene spec on Opus 4.6) | Each video beside its prompt | Shown, by the vendor |
| [HyperFrames prompting docs](https://github.com/heygen-com/hyperframes/tree/main/docs/prompting) | Yes | A/B films differing by one prompt line | Shown, by the vendor |
| [Jonny Burger, "Creating videos just from prompting"](https://www.youtube.com/watch?v=Xtd4DjU9AU8) | On screen | Three videos plus the failures along the way | Shown |
| [MoSidd, documentary motion graphics](https://www.youtube.com/watch?v=rK4vrMK4i2U) | Dictated on screen: three editable scenes at 1920x1080, 30 fps, scene timings to the tenth of a second, supplied footage | Documentary-style sequence | Prompt and result shown |
| [Roboverse tutorial](https://www.youtube.com/watch?v=6_rCyryA6hg) | On screen | "insane motion graphics from one single prompt" with the Remotion plugin | Result shown, "one prompt" claimed |
| Claude Pop and the 45-second short, via [ReelStack](https://thereelstack.com/lab/one-prompt-motion-is-a-myth) | Brief sizes only | Over 9,000 characters plus about 12 h; 163 calls, about $34, about 7 h | Claimed, secondary |
| [awesome-opus-5-5-videos](https://github.com/athemeroy/awesome-opus-5-5-videos) | Five public briefs | 424 source posts; nine-frame previews of 199 | Collection's own analysis, sourced |
| [Eden Digital](https://www.edendigital.io/posts/building-video-through-conversation) | Conversation described | 74-second video; Claude re-timed scenes to the narration itself | Claimed |

## Failure modes, their fixes and a possible gate

| Failure | Fix the sources give | Possible gate (inferred) |
| --- | --- | --- |
| Slides with motion ("PowerPoint slide that learned to move", KAIAK; Sarah Pan) | Carry one object across each cut; enter the next scene through something on screen and cut mid-move (HyperFrames `motion.md`) | Count scene changes that are a fade or a hard swap with nothing carried over |
| The default look (centred text, gradient, everything fading up) | A reference, numbers in place of adjectives, the defaults banned by name (Rexan Wong; HyperFrames `spec.md`) | Frame review against the banned list, with overrides stated |
| The same entrance everywhere, linear easing, uniform 0.5 s timing | Vary entrances; ease by cause (frame-smith `anti-cheap-motion.md`; HyperFrames `motion.md`) | Tally entrance types and durations per film |
| Dead stretches, flat pacing | Something new every 2 to 4 s; give every second a job (HyperFrames `spec.md`, prompting guide) | `dead_stretch` style check: over 3 s with no change |
| Lines too short to read; clipped or overflowing text | Text minimums; measure text before layout (Remotion `video-layout.md`, measuring text) | `line_unread`, `text_below_floor`, overflow check on still sheets |
| Empty first frame | Frame 0 is the thumbnail (HyperFrames `story.md`) | `first_frame_empty` |
| Flicker from unseeded randomness | Everything a function of frame or timeline time (both packs; shown by Burger) | Lint for `Math.random()` and `Date.now()` |
| Motion around no story | Three storylines, one bold; an explainer worked through one concrete example (HyperFrames `story.md`) | Storyboard approval shows the options |

## Sources

- HyperFrames: [PR #5651](https://github.com/heygen-com/hyperframes/pull/5651);
  [`skills/hyperframes`](https://github.com/heygen-com/hyperframes/tree/main/skills/hyperframes)
  (`SKILL.md`, `references/story.md`, `spec.md`, `review.md`, `motion.md`);
  [prompting docs](https://github.com/heygen-com/hyperframes/tree/main/docs/prompting)
  (`overview.mdx`, `motion.mdx`).
- Remotion: [`remotion-dev/skills`](https://github.com/remotion-dev/skills);
  [Prompt Showcase](https://www.remotion.dev/prompts);
  [Jonny Burger video](https://www.youtube.com/watch?v=Xtd4DjU9AU8).
- Anthropic:
  [prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices);
  [Improving frontend design through skills](https://claude.com/blog/improving-frontend-design-through-skills);
  [Get started with Claude Motion](https://support.claude.com/en/articles/17454997-get-started-with-claude-motion);
  [Claude Opus 5.5](https://www.anthropic.com/claude-opus-5-5).
- Practitioners:
  [Rexan Wong](https://x.com/rexan_wong/status/2103707054108299437);
  [Kevin Ngo](https://x.com/kevin_t_ngo/status/2102761406315839798);
  [Charlie Hills](https://charliehills.substack.com/p/claude-code-motion-graphics);
  [ReelStack](https://thereelstack.com/lab/one-prompt-motion-is-a-myth);
  [CTOL](https://www.ctol.digital/news/claude-opus-5-5-ai-video-model-to-studio/);
  [awesome-opus-5-5-videos](https://github.com/athemeroy/awesome-opus-5-5-videos);
  [Sarah Pan](https://dev.to/sarahpan/i-asked-ai-for-a-video-it-gave-me-an-animated-powerpoint-1dp8);
  [Eden Digital](https://www.edendigital.io/posts/building-video-through-conversation);
  [KAIAK](https://kaiak.io/blog/remotion-video-content-non-developer);
  [Sabrina Ramonov](https://www.sabrina.dev/p/5-insane-claude-code-video-prompts);
  [@aiedge_](https://x.com/aiedge_/status/2114590347288629720);
  [MoSidd](https://www.youtube.com/watch?v=rK4vrMK4i2U);
  [Roboverse](https://www.youtube.com/watch?v=6_rCyryA6hg).
- Skills and vendors:
  [MotionSites remotion-motion-graphics](https://motionsites.org/skills/remotion/remotion-motion-graphics);
  [frame-smith anti-cheap-motion](https://github.com/mouse-lin/frame-smith/blob/main/skills/frame-smith/references/anti-cheap-motion.md);
  [MaizeCobra motion-graphic-director-skill](https://github.com/MaizeCobra/motion-graphic-director-skill);
  [snapcn](https://snapcn.dev/why-ai-motion-graphics-look-the-same);
  [interpt](https://interpt.co/blog/claude-code-motion-graphics/);
  [reelcn](https://www.reelcn.dev/docs/agent-skill);
  [Modellix](https://www.modellix.ai/blog/remotion-agent-skills-claude).
