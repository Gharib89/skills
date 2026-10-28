// Maintainer only: re-measure the render rates the render stage's estimate
// reads and write them into render-rates.json with the HyperFrames version they
// were measured on. Run it with each HyperFrames bump.
//
//   node maintainer/calibrate-render-rates.mjs [render-rates.json]
//     [--seconds <n>] [--runs <n>]
//   (from the skill folder)
//
// Needs the npm-packages and chrome rows installed (`node scripts/setup.mjs
// install`) and ffmpeg. A fixture run folder (real-render-lib.mjs) of four
// scenes in two chapters, about `--seconds` of video (default 60), is voiced by
// tones, timed, given its chapters and put through the skill's own claims,
// gates and render stages with real HyperFrames. The chapters are written into
// its timeline after the timing stage: the stage holds a chapter to 2 to 6
// minutes, which a fixture of a minute is not, and the gates (the chapter titles
// gate included) judge it as they judge a video. It is then rendered `--runs`
// times (default 3), the median kept, each run clearing the render cache and
// running render.mjs, which renders both chapters, then the audio pass; a second
// render.mjs on the cached chapters times the audio pass, its mastering and
// join alone. The rates, in render seconds per video second:
//   render  (cold render - cached render) / video s
//   audio   cached render / video s
// stdout: `calibrate-render run <i>/<n>: chapters <s> s, audio pass <s> s over
//         <s> s of video` per run, then the values written:
//         `calibrate-render: HyperFrames <version>: render <r>, audio <r>
//         render s per video s`
// exit:   0 written · 1 a stage failed or rendered nothing, the table left
//         alone · 2 usage, or a tool row is missing
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { stage } from "../scripts/lib/stage.mjs";
import { skill } from "../scripts/lib/tools.mjs";
import { FPS } from "../scripts/render/grid.mjs";
import {
  authored,
  gatesPass,
  missingRows,
  runFolder,
  runStage,
} from "./real-render-lib.mjs";
import { ratesFrom } from "./render-rates-lib.mjs";

const NAME = "calibrate-render";
stage(NAME);
const args = process.argv.slice(2);
let runs = 3;
let seconds = 60;
let file = path.join(skill, "render-rates.json");
const usage = () => {
  console.error(
    "usage: node calibrate-render-rates.mjs [render-rates.json] [--seconds <n>] [--runs <n>]",
  );
  process.exit(2);
};
for (let i = 0, named = false; i < args.length; i++) {
  if (args[i] === "--runs") {
    runs = Number(args[++i]);
    if (!Number.isInteger(runs) || runs < 1) usage();
  } else if (args[i] === "--seconds") {
    seconds = Number(args[++i]);
    if (!(seconds >= 8)) usage();
  } else if (!args[i].startsWith("--") && !named) {
    file = args[i];
    named = true;
  } else usage();
}
const missing = missingRows();
if (missing.length) {
  console.error(
    `${NAME}: ${missing.join(", ")} not installed: run /creative-video setup`,
  );
  process.exit(2);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), `${NAME}-`));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

// Each chapter's first scene draws the chapter's title, a box slides in each,
// so every frame differs from the one before.
const BOX =
  '<div id="b" style="position:absolute;left:160px;top:600px;width:200px;height:200px;background:#7cc"></div>';
const SLIDE = 'tl.to("#b", { x: 600, duration: 3, ease: "none" }, 0);';
const title = (text) =>
  `<h1 style="position:absolute;left:200px;top:200px;margin:0;white-space:nowrap;font:700 72px Inter,sans-serif;color:#fff">${text}</h1>`;
const TITLES = ["Chapter one", "Chapter two"];
const frames = Math.round((seconds * FPS) / 4);
const scenes = ["a", "b", "c", "d"].map((id, i) => ({
  id,
  frames,
  html: authored(id, (i % 2 ? "" : title(TITLES[i / 2])) + BOX, SLIDE),
}));
const run = runFolder(work, "calibrate", scenes);
runStage("render/timing.mjs", run);
const record = path.join(run, "timeline.json");
const timeline = JSON.parse(fs.readFileSync(record, "utf8"));
timeline.chapters = [0, 2].map((first, k) => ({
  n: k + 1,
  title: TITLES[k],
  start: timeline.scenes[first].start,
  end: timeline.scenes[first + 2]?.start ?? timeline.total,
  scenes: [timeline.scenes[first].id, timeline.scenes[first + 1].id],
}));
fs.writeFileSync(record, JSON.stringify(timeline, null, 2) + "\n");
gatesPass(run);

// One render.mjs on the run as its caches stand, in seconds.
function timed() {
  const t = performance.now();
  runStage("render/render.mjs", run);
  return (performance.now() - t) / 1000;
}
const r2 = (x) => Math.round(x * 100) / 100;
const cold = [];
const cached = [];
for (let i = 1; i <= runs; i++) {
  fs.rmSync(path.join(run, ".cache", "render"), {
    recursive: true,
    force: true,
  });
  cold.push(timed());
  const parts = fs
    .readdirSync(path.join(run, ".cache", "render"))
    .filter((f) => /^chapter-\d+-[0-9a-f]{16}\.mp4$/.test(f));
  if (parts.length !== 2)
    throw new Error(`rendered ${parts.length} of 2 chapter renders`);
  cached.push(timed());
  console.log(
    `${NAME} run ${i}/${runs}: chapters ${r2(cold.at(-1) - cached.at(-1))} s, audio pass ${r2(cached.at(-1))} s over ${r2(timeline.total)} s of video`,
  );
}
const rates = ratesFrom({ cold, cached }, timeline.total);
for (const k in rates) rates[k] = r2(rates[k]);

const { hyperframes } = JSON.parse(
  fs.readFileSync(path.join(skill, "package.json"), "utf8"),
).dependencies;
fs.writeFileSync(file, JSON.stringify({ hyperframes, rates }, null, 2) + "\n");
console.log(
  `${NAME}: HyperFrames ${hyperframes}: render ${rates.render}, audio ${rates.audio} render s per video s`,
);
