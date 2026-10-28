// The render estimate of a video in chapters, from the measured rates table
// (render-rates.json, written by maintainer/calibrate-render-rates.mjs): what
// the render prints before it starts, and what `render.mjs --estimate` prints
// alone, so a change that re-renders every chapter is weighed before it is made.
import fs from "node:fs";
import path from "node:path";
import { skill } from "./tools.mjs";

// Render seconds allowed per video second: 5 minutes per video minute.
export const BUDGET = 5;

// The measured table: `{ hyperframes, rates: { render, audio } }`, each rate in
// seconds per video second: `render` the chapters' video, rendered one at a
// time, `audio` the audio pass of the whole project with its mastering and join.
// Refuses a table of the wrong shape by naming the file and the field: a missing
// rate would otherwise print as `NaN`.
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
  for (const k of ["render", "audio"]) {
    const v = table.rates[k];
    if (!Number.isFinite(v) || v < 0)
      refuse(`rates.${k}`, "a number of 0 or more");
  }
  return table;
}

// Render seconds for `rendered` seconds of chapters to render and a video of
// `video` seconds, and the budget of that video.
export const estimate = (rendered, video, rates) => ({
  seconds: rendered * rates.render + video * rates.audio,
  budget: video * BUDGET,
});
