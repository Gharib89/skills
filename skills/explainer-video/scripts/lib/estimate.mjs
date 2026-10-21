// The first-render estimate the storyboard shows: render seconds from the
// measured rates table (render-rates.json, written by
// maintainer/calibrate-render-rates.mjs). The board comes after the voice, so
// the estimate covers the render and the video gates, not the narration.

import fs from "node:fs";
import path from "node:path";
import { skill } from "./tools.mjs";

// Render seconds allowed per video second: 5 minutes per video minute.
export const BUDGET = 5;

// The measured table: `{ hyperframes, rates: { base, texture, live3d, gates } }`,
// each rate in render seconds per video second.
export const rates = () =>
  JSON.parse(fs.readFileSync(path.join(skill, "render-rates.json"), "utf8"));

const r1 = (x) => Math.round(x * 10) / 10;

// `scenes` is `[{ id, seconds, webgl }]`. Every video second pays the base,
// gates and, in a textured style, texture rate; a WebGL scene pays the live 3D
// rate on top, which is the only thing a scene adds over a default one, so
// `adds` is each scene's live 3D seconds.
export function estimate(scenes, rates, { textured }) {
  const video = scenes.reduce((n, s) => n + s.seconds, 0);
  const adds = Object.fromEntries(
    scenes.map((s) => [s.id, r1(s.webgl ? s.seconds * rates.live3d : 0)]),
  );
  const flat = rates.base + rates.gates + (textured ? rates.texture : 0);
  const seconds = r1(
    video * flat + Object.values(adds).reduce((n, a) => n + a, 0),
  );
  const budget = r1(video * BUDGET);
  return { seconds, budget, over: seconds > budget, adds };
}
