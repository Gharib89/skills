# The video sibling gates rendered output, never scene code

The sibling skill that makes freely authored narrated videos blocks a video only on a defect it measures in the rendered output or the narration, and puts no rule on what a scene's code may do. `explainer-video` guards determinism and Arabic joins with lints that refuse code before any render (no `Math.random`, timers, `requestAnimationFrame`, CSS animation, libraries, per-letter spans in Arabic), and guards facts by treating every digit on screen as a cited claim. Each lint bans a whole technique to prevent one defect, and the research behind the sibling found the defect does not follow the technique: a frame is deterministic when it is driven from the frame, whatever the library (#968), and Arabic per-letter motion keeps its joins under a ZWJ split (#964). So the sibling checks the frames and the shapes, and leaves the code free.

## Consequences

- Determinism is one gate: each scene's sample frames are rendered twice in separate launches, and the scene fails only when the pixels differ. A clock and random scan of the scene's code is a warning that names suspects, never a refusal. The frame clock and seeded random the skill ships are tools, not requirements.
- Broken Arabic under motion is measured on each animated Arabic text box against the same words set unsplit. Whether that measurement is feasible is unproven; until a probe shows it, the critic's right-to-left kind is the guard.
- Facts are traced at the narration sentence (cites and the support check). Everything drawn on screen is staging by default; the critic's invented kind fails only an on-screen fact that no narration or excerpt states, or one that contradicts them.
- Readable text may be drawn on a canvas or in 3D; the measured layout, contrast and reading time gates see only DOM text, so the critic's stills review is the only guard on the rest.
- Sync is held by construction: scene events anchor to aligned word times, and only an anchor naming a word the alignment lacks fails.
- Checks with no defect behind them (sound-effect rate, per-scene length, long sentences, pacing, critic description) report and never block. The critic describes each still as a stranger would and gives no scores.
