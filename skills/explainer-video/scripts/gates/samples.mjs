// The sampling pass: layout and reading time judged on the composition's
// samples before the storyboard posts, so a red shows on its card instead of
// after a render.
//
//   node samples.mjs <run-folder>
//
// Reads <run>/script.json, timeline.json, style.json and composition/ (the
// stills step writes them) and samples each scene as gates.mjs does: every 15
// frames, each timeline event and the last frame. HyperFrames' check and the
// layout probe run once over every scene's samples; the layout probe's findings
// (contrast stays with the video gates) and the reading rules are judged with
// the same floors.
// stdout: `sample <scene>: <finding>` per finding, then `samples: <n> scene(s),
//         <k> finding(s) in <s> s`, the pass's cost on this machine
// writes: <run>/samples.json: the seconds it took and each scene's findings,
//         which `board.mjs build` reads
// exit:   0 no finding · 1 a finding, or `samples: <why>` on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { judge } from "../lib/layout.mjs";
import { sampleTimes } from "../lib/motion.mjs";
import { floors, loadStyle } from "../lib/style.mjs";
import { hyperframesEnv, loadBackend } from "../lib/tools.mjs";
import { FPS } from "../render/compose.mjs";
import { sceneEvents } from "./events.mjs";
import { readingFindings } from "./reading.mjs";

const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node samples.mjs <run-folder>");
  process.exit(2);
}
function fail(why) {
  console.error(`samples: ${why}`);
  process.exit(1);
}
async function orFail(call) {
  try {
    return await call();
  } catch (e) {
    fail(e.message);
  }
}
const at = (...p) => path.join(run, ...p);
for (const f of [
  "script.json",
  "timeline.json",
  "style.json",
  "composition/index.html",
])
  if (!fs.existsSync(at(f)))
    fail(`no ${f}: run node render.mjs ${run} --stills`);
const script = JSON.parse(fs.readFileSync(at("script.json"), "utf8"));
const timeline = JSON.parse(fs.readFileSync(at("timeline.json"), "utf8"));
let floor;
try {
  floor = floors(loadStyle(run, script.style));
} catch (e) {
  fail(e.message);
}

const started = Date.now();
const backend = await loadBackend();
const env = hyperframesEnv();
const comp = at("composition");
const { times: eventTimes, moving } = sceneEvents(
  await orFail(() => backend.events(comp, { env })),
  timeline.scenes,
);
const plan = timeline.scenes.map((sc) => ({
  sc,
  end: sc.start + sc.duration,
  times: sampleTimes({ ...sc, fps: FPS, events: eventTimes }),
  layout: new Map(),
}));
const times = plan.flatMap((p) => p.times);
const checked = await orFail(() => backend.check(comp, times, { env }));
// A check that never reached the browser answers {ok: false, error} alone.
if (!checked.layout || !checked.contrast)
  fail(`hyperframes check: ${checked.error ?? "no layout or contrast result"}`);
const frames = await orFail(() => backend.probe(comp, times, { env }));
// A scene with no text of its own in any sample is a probe that saw nothing,
// not a pass: captions and the header draw over every scene.
for (const p of plan)
  if (
    !frames.some(
      (f) =>
        p.times.includes(f.t) && f.elements.some((e) => e.scene === p.sc.id),
    )
  )
    fail(`layout probe: no text in scene ${p.sc.id}`);

// One defect held across a scene is one finding: its first time, and the
// number of samples it showed in.
const add = (gate, t, what) => {
  if (gate !== "layout") return;
  const p = plan.find((p) => t < p.end - 1e-6) ?? plan.at(-1);
  const key = `${p.sc.id}: ${what}`;
  const hit = p.layout.get(key);
  if (hit) hit.n += 1;
  else p.layout.set(key, { t, what, n: 1 });
};
judge(checked, frames, floor, add, moving);

const scenes = plan.map((p) => ({
  id: p.sc.id,
  findings: [
    ...[...p.layout.values()].map(
      ({ t, what, n }) =>
        `${t.toFixed(2)} s ${p.sc.id}: ${what}${n > 1 ? ` (${n} samples)` : ""}`,
    ),
    ...readingFindings(p, frames, moving),
  ],
}));
const seconds = +((Date.now() - started) / 1000).toFixed(1);
fs.writeFileSync(
  at("samples.json"),
  JSON.stringify({ seconds, scenes }, null, 2) + "\n",
);
for (const s of scenes)
  for (const f of s.findings) console.log(`sample ${s.id}: ${f}`);
const n = scenes.reduce((k, s) => k + s.findings.length, 0);
console.log(
  `samples: ${scenes.length} scene(s), ${n} finding(s) in ${seconds.toFixed(1)} s`,
);
process.exit(n ? 1 : 0);
