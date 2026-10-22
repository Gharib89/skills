// The first-render estimate the storyboard shows: render seconds from the
// measured rates table (render-rates.json, written by
// maintainer/calibrate-render-rates.mjs). The board comes after the voice, so
// the estimate covers the render, the gates and the brief's score, not the
// narration.

import fs from "node:fs";
import path from "node:path";
import { HOLD } from "./length.mjs";
import { skill } from "./tools.mjs";

// Render seconds allowed per video second: 5 minutes per video minute.
export const BUDGET = 5;

// The measured table: `{ hyperframes, rates: { base, texture, live3d, gates,
// score, aceStep? } }`, each rate in render seconds per video second. `score` is
// the synthesised score; `aceStep` is there only where the calibrator ran on a
// machine with that row installed.
// Refuses a table of the wrong shape by naming the file and the field: a
// missing rate would otherwise show on the page as `NaN s`.
export function loadRates(file = path.join(skill, "render-rates.json")) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (e) {
    throw new Error(`${file}: cannot be read (${e.code})`);
  }
  let table;
  try {
    table = JSON.parse(text);
  } catch (e) {
    throw new Error(`${file}: is not JSON (${e.message})`);
  }
  const refuse = (field, want) => {
    throw new Error(`${file}: ${field} is not ${want}`);
  };
  if (typeof table?.hyperframes !== "string" || !table.hyperframes)
    refuse("hyperframes", "the HyperFrames version it was measured on");
  if (!table.rates || typeof table.rates !== "object")
    refuse("rates", "an object of rates");
  for (const k of ["base", "texture", "live3d", "gates", "score", "aceStep"]) {
    const v = table.rates[k];
    if (k === "aceStep" && v === undefined) continue;
    if (!Number.isFinite(v) || v < 0)
      refuse(`rates.${k}`, "a number of 0 or more");
  }
  return table;
}

const r1 = (x) => Math.round(x * 10) / 10;

// `scenes` is `[{ id, seconds, webgl }]`, `seconds` the voiced length. Every
// video second pays the base, gates and, in a textured style, texture rate; a
// WebGL scene pays the live 3D rate on top, which is the only thing a scene
// adds over a default one, so `adds` is each scene's live 3D seconds. The video
// is the voiced seconds and the closing hold, the length the calibrator divides
// its timings by. `score` is the brief's mode, on by default as in the brief:
// every video second pays the rate of the score it asks for, none for `off`. A
// brief asking `ace-step` where the table has no rate for it gets the estimate
// without a score and `unmeasured` true, never a guess.
export function estimate(scenes, rates, { textured, score = "on" }) {
  const video = scenes.reduce((n, s) => n + s.seconds, HOLD);
  const adds = Object.fromEntries(
    scenes.map((s) => [s.id, r1(s.webgl ? s.seconds * rates.live3d : 0)]),
  );
  const bed = { on: rates.score, "ace-step": rates.aceStep }[score] ?? 0;
  const flat = rates.base + rates.gates + (textured ? rates.texture : 0) + bed;
  const seconds = r1(
    video * flat + Object.values(adds).reduce((n, a) => n + a, 0),
  );
  const budget = r1(video * BUDGET);
  const unmeasured = score === "ace-step" && rates.aceStep === undefined;
  return { seconds, budget, over: seconds > budget, adds, unmeasured };
}
