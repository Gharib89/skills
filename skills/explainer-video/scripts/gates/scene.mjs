// The gates stage's per-scene measures of the render: the fullest moment, read
// off the layout probe's samples, and the motion peak and its determinism
// check, read off the encoded video.
import fs from "node:fs";
import path from "node:path";
import {
  frameTime,
  fullest as fullestSample,
  peak as peakFrame,
  deadBeats,
  sceneFrames,
} from "../lib/motion.mjs";
import { readable } from "../lib/layout.mjs";
import { FPS } from "../render/compose.mjs";

// The scene's fullest moment as a video frame index: the sample with the most
// readable words of the scene at once, the latest on a tie.
export function fullestFrame(p, frames, moving) {
  const samples = p.times.map((t) => ({
    t,
    words: frames
      .find((f) => f.t === t)
      .elements.filter((e) => e.scene === p.sc.id && readable(e, t, moving))
      .reduce((n, e) => n + e.words, 0),
  }));
  return Math.round(fullestSample(samples) * FPS);
}

// Motion, then determinism on the frame it picks: the scene's peak-motion
// frame outside every seam, rendered twice in two browsers and compared as
// decoded pixels; and the scene's dead beats, read off its timeline from
// `tweens`. Sets p.found.motion and p.found.determinism.
export async function motionAndDeterminism(
  p,
  { run, mp4, comp, env, backend, orFail, seams, tweens, band },
) {
  const scene = { start: p.sc.start, duration: p.sc.duration, fps: FPS };
  const { first } = sceneFrames(scene);
  const diffs = await orFail(() =>
    backend.bandMotion(path.join(run, mp4), { ...scene, band }),
  );
  const pk = peakFrame(diffs, first, FPS, seams);
  const t = frameTime(pk.frame, FPS);
  p.found.motion = {
    still: pk.still,
    frame: pk.frame,
    t,
    dead: deadBeats(scene, tweens),
  };
  const base = path.basename(p.file, ".json");
  const files = ["a", "b"].map((x) =>
    path.join(".cache", "gates", "frames", `${p.sc.id}-${base}-${x}.png`),
  );
  fs.mkdirSync(path.join(run, path.dirname(files[0])), { recursive: true });
  const hashes = [];
  for (const f of files) {
    await orFail(() => backend.frame(comp, t, path.join(run, f), { env }));
    hashes.push(await orFail(() => backend.framePixels(path.join(run, f))));
  }
  p.found.determinism = {
    frame: pk.frame,
    t,
    a: hashes[0],
    b: hashes[1],
    files,
  };
}
