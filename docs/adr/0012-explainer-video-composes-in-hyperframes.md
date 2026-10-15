# explainer-video composes in HyperFrames, not Remotion

`explainer-video` builds every video on HyperFrames (Apache-2.0), even though the owner's house explainer pipeline and its component registry are written for Remotion. Remotion is source-available: anyone working for a company of four or more people, contractors counted, owes a paid seat, so a Remotion default breaks the rule that every shipped default is commercial-safe, and the skill cannot tell which case a user is in. HyperFrames renders deterministically headless on the target machine and shaped a mixed Egyptian Arabic and English line correctly in a real render (HyperFrames 0.8.160, `dir="rtl"` scoped to text elements, 2026-10-15).

## Consequences

- v1 ships this one composer. A Remotion backend is a possible later slice for users who already hold a licence, not a v1 option, so every scene component, caption layer and gate is written once.
- The house pipeline's Remotion components and gates are ported, not reused as they stand.
- Other renderers (Manim, a cached 3D render, a screen recording) enter only as clip inserts in a scene slot; scenes are never concatenated across engines.
- Maths scenes (typeset equations, term-matched transforms, plotted curves) are drawn in the composer; a probe rendered them on a par with the lab's Manim output, so Manim and its TeX Live, Cairo and Pango setup (about 600 MB) stay out of v1 as a possible later clip source.
