// The seams between scenes: which move hands each scene over to the next, and
// how long it runs. The outgoing scene draws the seam on past its own last
// moment (its slot grows) while the next scene starts on time, so no scene
// start and no narration time moves; the incoming scene draws its entry over
// the same window. compose.mjs draws both from the plan.
import { grammar } from "../lib/style.mjs";
import { frames, written } from "./grid.mjs";

// The cut on a curve peaks at 4/9 of the zoom-through's blur: 8 px at the
// default 18.
const CURVE_BLUR = 4 / 9;

// A scene's seam out and in, `[{ out, in }]` by scene: a move, or null for a
// plain cut and for the last scene's end. The move is the scene's own `seam`
// (`visual.seam`), else read off the arc: a zoom-through where the next scene
// opens another beat (its role differs), a cut on a curve inside a beat (the
// same role). A seam carries its whole `frames` and `duration` in seconds,
// written as the frame grid writes it, and its peak `blur` in px.
export function seamPlan(scenes, profile) {
  const { seams } = grammar(profile);
  const n = frames(seams.duration);
  const out = scenes.map((s, i) => {
    const next = scenes[i + 1];
    if (!next) return null;
    const move =
      s.visual.seam ??
      (seams.family === "cut"
        ? "cut"
        : s.role && s.role === next.role
          ? "cut-the-curve"
          : "zoom-through");
    if (move === "cut") return null;
    const blur =
      move === "zoom-through"
        ? seams.blur
        : Math.round(seams.blur * CURVE_BLUR);
    return { move, frames: n, duration: written(n), blur };
  });
  return out.map((o, i) => ({ out: o, in: out[i - 1] ?? null }));
}

// A scene's slot in seconds: its own frames and its seam out's.
export const slot = (own, seam) => written(own + (seam.out?.frames ?? 0));
