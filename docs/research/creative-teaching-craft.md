# Teaching craft of the best animated explainers

Research for [#969](https://github.com/Gharib89/skills/issues/969) on the
[creative video skill map](https://github.com/Gharib89/skills/issues/961).

Labels: **documented** (a primary source says so, linked: the creator's own
words or the researchers' own paper), **reported** (a secondary source quotes or
summarises the primary one), **inferred** (my reading for this skill, no direct
proof).

Each item below is written as craft knowledge an agent can draw on while it
authors a scene freely: a pattern, the evidence behind it, and what it suggests
for this skill. None is meant as a hard rule; the map keeps hard rules for real
defects.

## Baseline: what earlier research covered

- [#656](https://github.com/Gharib89/skills/issues/656) (`research/explainer-design-refs`)
  covered the *look* of the reference studios: palettes, type, the five
  directions, and four shared habits (narration sets the timing, one visual
  idea per spoken idea, colour bound to meaning, a consistent look). It quoted
  Kurzgesagt's process page and Joss Fong on Vox's black hole video.
- [#773](https://github.com/Gharib89/skills/issues/773) measured that narrated
  explainers *build* a held frame rather than cut (0 to 10 cuts a minute).
- [#796](https://github.com/Gharib89/skills/issues/796) settled freedom held by
  gates for the visual vocabulary.

None of them covered *pedagogy*: how a metaphor is chosen and kept honest, build
order, misconceptions, retrieval, characters, worked examples, or the learning
evidence. That is this file. Where it agrees with the earlier findings it says
so; nothing here contradicts them, but finding 1 adds a limit on spectacle that
the "amaze me" framing did not have.

## Answer, ranked by how much it changes the new skill

1. **Spectacle must carry the idea, or it costs learning.** Interesting but
   irrelevant additions lower learning: removing them gave d = 0.80 (3 of 3
   experiments), removing background music d = 0.95 (2 experiments) (Mayer
   2021), and a meta-analysis of seductive details finds a negative effect,
   about g = -0.3 to -0.4. The bar videos' best moments (the sticky note that
   falls off against a padlock) are the explanation itself, which is the safe
   kind. The ambition stance should aim creativity at the explanation, not at
   decoration around it.
2. **A clear explanation can teach nothing; staging the wrong idea teaches.**
   Muller's concise physics video felt "clear" to students and moved novices
   from 6.0 to 6.3 of 26; versions that voiced and resolved common
   misconceptions, including a student and tutor dialogue, gained d = 0.79 and
   0.83 over it with 364 students. This is the strongest single argument for a
   cast: a learner character who holds the likely wrong idea.
3. **Retrieval beats recap.** In video lectures, short tests between segments
   cut mind wandering (19% against 41% of probes) and lifted the final test
   (90% against 68%), while a restudy recap did no better than nothing
   (Szpunar 2013). Questions *before* a segment also help, including on
   material not asked about (Carpenter 2017). A recap works best as a question
   the viewer answers in their head, then the answer.
4. **A metaphor is chosen by shared structure and closed by saying where it
   breaks.** TED-Ed picked a tree for Big Data because both grow, branch and
   produce; Glynn's teaching-with-analogies model ends with "indicate where
   the analogy breaks down"; Kurzgesagt deleted a hit video because they
   "simplified an idea so much that it made a great story, but became
   distorting".
5. **Build order: hook with a concrete question, give examples before the
   abstraction, name the parts early, add one part per spoken idea.** Grant
   Sanderson's own advice, plus Mayer's pre-training (d = 0.85), segmenting
   (d = 0.67) and temporal contiguity (d = 1.31) principles.
6. **Pacing: short segments, energy over slowness, room to ponder at the
   hard step.** Engagement falls past about 6 minutes per video (Guo 2014), so
   a 30-minute film is a chain of short chapters.
7. **Characters earn their place by acting, gesturing or holding a view.** A
   gesturing on-screen agent helped (d = 0.76), a static figure hurt
   (d = -0.25); stories run on causality, conflict, complications and
   character (Willingham).
8. **Voice: conversational wording matters most, and modern TTS is no longer a
   penalty.** Personalisation d = 1.00; a modern TTS engine matched a recorded
   human voice (Craig and Schroeder 2017, 2018).
9. **Worked examples help novices and get in the way of experts.** The
   audience's level picks how much is worked through (expertise reversal).

Thin spots and open questions are listed at the end.

## Evidence, item by item

- Items 1 to 4 (spectacle, misconceptions, retrieval, metaphor):
  [creative-teaching-craft-what-to-show.md](creative-teaching-craft-what-to-show.md)
- Items 5 to 9 (build order, pacing, characters, voice, worked examples):
  [creative-teaching-craft-how-to-build.md](creative-teaching-craft-how-to-build.md)

## Thin or open

- The learning effects come from lab studies of short science lessons, mostly
  under 10 minutes, with students; none measured a 30-minute chaptered film or
  a developer audience (documented in the papers' own scope; transfer here is
  inferred).
- The retrieval studies had learners answer; a linear video can only pose the
  question. How much of the effect survives an unanswered prompt is unmeasured
  (inferred).
- No creator source quantifies how much music or sound effects help or hurt;
  Kurzgesagt values them, Grant and Mayer warn against them under dense
  explanation. A three-arm comparison on the map could measure it.
- Sundararajan and Adesope 2020 is paywalled; its numbers here come from the
  author's dissertation and a secondary summary.
- Gentner 1983 is cited from memory of its abstract, not re-read.
- I found no first-party writing by Justin Helps (Primer) on method beyond the
  videos themselves, and no TED-Ed written animator guideline; their practice
  is read from their own videos.
- Vox evidence is unchanged from #656 (one reported interview).
