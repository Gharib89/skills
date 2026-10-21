// A reference video read for style extraction: its colour frames, the frames
// around two of its cuts for the agent to judge motion from, and the motion
// measure.mjs reports from the frames it measured.
import fs from "node:fs";
import { decodePpm, measureMotion, planStills } from "./motion.mjs";

// Each cut kept as a strip is three reference images.
const STRIP = 3;

// `{ files, motion }` for one video: `files` the reference images
// (`<out>-<n>.png` colour frames, then `<out>-cut<n>-before|at|after.png`), at
// most `max` of them, and `motion` its `{ duration, cuts, cutsPerMinute,
// blurAtCuts, grain }`. The stills measured and not kept are deleted.
export async function readVideo(backend, file, out, { max }) {
  const { duration, cuts } = await backend.videoCuts(file);
  const plan = planStills({ duration, cuts });
  const stills = await backend.videoStills(file, `${out}-still`, plan.times);
  const frames = [];
  for (const f of stills) frames.push(decodePpm(await backend.ppm(f)));
  const motion = measureMotion({
    duration,
    cuts,
    shots: plan.shots.map((s) => ({
      steady: frames[s.steady],
      ...(s.before !== undefined && { before: frames[s.before] }),
    })),
  });
  const kept = [];
  for (const s of plan.strips)
    for (const w of ["before", "at", "after"]) {
      const f = `${out}-cut${s.cut}-${w}.png`;
      fs.renameSync(stills[s[w]], f);
      kept.push(f);
    }
  for (const f of stills) fs.rmSync(f, { force: true });
  const colour = await backend.videoFrames(file, out, {
    max: max - STRIP * plan.strips.length,
  });
  return {
    files: [...colour, ...kept],
    motion: { duration, cuts: cuts.length, ...motion },
  };
}
