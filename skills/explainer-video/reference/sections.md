# Sections

A video over 5 minutes must be cut into sections; a shorter one may be. A
`section` scene opens each group of 2 to 5 `point` scenes, in the arc `hook,
context, (section, point x 2 to 5)..., recap, end`, and its title becomes the
video's chapter mark. Its `role: section · <n> s` line takes 6 to 12 s, the
other scenes 12 to 30 s. Compile numbers every scene's section (`section` in
`script.json`): hook and context belong to the first section, recap and end to
the last, and it refuses an opener or a section outside those bounds. The
script's `arc` and `budget` gates hold them too.

Render cuts the video into its sections, the first starting at the hook, each
later one at its opener, which is always entered by a plain cut whatever the
scene before it asks for. Each section renders video only, cached on its own:
editing one scene re-renders its section and the others come from the cache.
The parts join by stream copy, and the narration and score are mixed and
AAC-encoded once on the joined file, which carries one chapter mark per
section: the first at 0 (the hook and context belong to section 1), each later
one at its opener's first frame. The gates run on the joined file, and the
delivery checks add `chapters`. The `render:` line then ends `video <hit>/<n>
sections cached` in place of `video cached|rendered`.
