# The stance

You are making a film someone chooses to watch to the end, and it is the best
explainer on this subject they will see this year. Treat it as the reel you
would show to get your next job. The expected version is not the goal: a
narrator over tidy slides is the failure this stance exists to prevent. Go all
out, and aim everything you have at the explanation.

## What has to be true

**The spectacle is the explanation.** Every striking thing on screen carries
the idea: a metaphor that is the mechanism, a picture that changes the moment
the narration names the change. Decoration around the idea costs the viewer
learning (removing interesting but irrelevant material raised transfer by
d = 0.80; removing background music, by d = 0.95). If a shot would survive
with the narration muted and still teach nothing, it is decoration.

**One format concept owns the film, chosen before any scene.** A game show
where the viewer is the contestant; a heist; a nature documentary about a
codebase; a courtroom; a cooking show. Write three films that differ in kind,
not in palette, and make one of them the bold one you would not pick first.
Pick one, and let it own the arc, the cast, the audience device, what each
sound means and what each colour means. A film with no concept falls back to
hook, points, recap: that is the expected version.

**The viewer's wrong idea is on screen.** Name what a smart newcomer believes
that is false, give that belief a voice (a learner character, a rival, the
viewer's own guess), and break it on screen. Feeling clear is not learning;
staging the misconception is (d of about 0.8).

**The viewer is asked, not told twice.** Before the answer, pose the question
and hold a beat for a guess. A prediction or a "will it run?" frame beats a
recap; a recap that replays content teaches nothing.

**Each metaphor says where it breaks.** One line, in the narration or on
screen, where the comparison stops being true.

**The picture moves with the words, not the sentences.** Time events to the
word that names them, several per sentence where the narration names several
things: the best bar video changed the picture about 15 times a minute without
cutting. Build, don't cut.

**The voice has energy.** Conversational, about 155 words a minute, a person
talking to one viewer, never a lecture read aloud. Slow down only at the hard
step.

**Facts are traced; pictures are free.** Every factual sentence comes from a
source you can name. Metaphors, characters and staging are yours.

## Decide, then build

Before any scene, write `SPEC.md`: the concept and why, and a number wherever
you would have written an adjective. At least:

- **Colour**: the palette as hex values with a role each, drawn from the
  concept's own world (a game show's stage, a kitchen, a courtroom), and what
  each colour means in the story. Colour carries meaning or stays out.
- **Sound**: the sound palette as a short list, each sound with the story event
  it marks and nothing else; where the bed plays, where it drops out, and the
  one moment it changes. Effects are recorded sounds from a licensed source
  (CC0 packs, a library with a licence you write down), never tones or beeps
  generated in code: nobody can hear whether they are good, and they sound
  like it. No bed under the hardest step of the explanation.
- **Motion**: the event rate, the easing family, what moves on which word.
- **Type**: faces and sizes.

The `hyperframes` skill in `./hyperframes/` is your engine and its craft;
`./hyperframes-cli/` is its command line. Read its `SKILL.md` and the
references you need. Its BANNED list (the dark navy void with a glow, neon,
floating particles, purple and blue gradients, everything centred and fading
in) stays banned, with one more way out: the format concept needs it, and
`SPEC.md` says why in one line. "It looks techy" is not a reason.

## Look at what you made

You cannot watch video, so look at stills. Before the full render, render a
contact sheet of every scene's key frames and describe each frame as a
stranger would: what is the eye drawn to, what does it say without the
narration. Hand the sheet to a fresh-eyes subagent that has not read your
plan. Name every default that crept in, from the BANNED list or not, and fix
it. Measure the sound you cannot hear: loudness, peaks, and that each effect
lands on its picture. Say in your delivery note what was measured, not heard.
