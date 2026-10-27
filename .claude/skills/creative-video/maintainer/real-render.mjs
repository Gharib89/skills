// Maintainer only: render short fixtures through the skill's own timing, gates
// and render stages with real HyperFrames, and prove what the fake backend
// cannot: the delivered MP4 has exactly the frame grid's frames, three renders
// match frame for frame, two chapters rendered apart and joined by the chapter
// join have the sum of their frames and a chapter mark each, and five hard
// gates (determinism, layout, caption band, anchors, script errors) each fail a
// fixture built to fail them and pass the same fixture without the defect,
// layout also on a clip held at the key or the out sample only. Contrast,
// reading and must and avoid have no real-render fixture.
//
//   node maintainer/real-render.mjs
//
// Needs the npm-packages and chrome rows installed (`node scripts/setup.mjs
// install`) and the ffmpeg row. The fixtures are run folders
// (real-render-lib.mjs) voiced by tones of whole frames. The whole's 122
// frames are 4.0666... s, which a grid writing its times rounded to the voice
// stage's 3 places instead of truncated would render as 123.
// stdout: `creative-real-render <check>: pass|fail: <detail>` per check, `gate
//         <name>` for each gate's fixture pair
// exit:   0 every check passed · 1 a check failed, or a stage or tool failed
//         with `creative-real-render: <why>` on stderr · 2 a tool row is
//         missing
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { HOLD } from "../scripts/lib/length.mjs";
import { stage } from "../scripts/lib/stage.mjs";
import { catalogue, dest, loadBackend, skill } from "../scripts/lib/tools.mjs";
import { chapterCheck, joinChapters } from "../scripts/render/chapters.mjs";
import { FPS, gridScenes } from "../scripts/render/grid.mjs";
import { authored, differing, runFolder, tone } from "./real-render-lib.mjs";

const NAME = "creative-real-render";
stage(NAME);
const WHOLE = [
  { id: "open", frames: 50 },
  { id: "close", frames: 42 },
];
const CHAPTERS = [
  { title: "First", scenes: [{ id: "first", frames: 41 }] },
  { title: "Second", scenes: [{ id: "second", frames: 34 }] },
];

let failed = 0;
const check = (name, ok, detail) => {
  if (!ok) failed++;
  console.log(`${NAME} ${name}: ${ok ? "pass" : "fail"}: ${detail}`);
};
const missing = catalogue()
  .filter((r) => ["npm", "chrome"].includes(r.kind))
  .filter((r) => !fs.existsSync(path.join(dest(r), ".stamp")))
  .map((r) => r.id);
if (["ffmpeg", "ffprobe"].some((t) => spawnSync(t, ["-version"]).error))
  missing.push("ffmpeg");
if (missing.length) {
  console.error(
    `${NAME}: ${missing.join(", ")} not installed: run /creative-video setup`,
  );
  process.exit(2);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), `${NAME}-`));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));

// The stdout of `cmd`; a failure throws with both streams, since the render
// stage prints its delivery failures on stdout and its renderer on stderr.
function capture(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 1 << 26 });
  if (r.status !== 0) {
    const files = args.filter(path.isAbsolute).map((a) => path.basename(a));
    const said = [r.stdout, r.stderr].map((s) => s?.trim()).filter(Boolean);
    throw new Error(
      `${path.basename(cmd)} ${files.join(" ")}: ${said.join("\n") || r.error?.message}`,
    );
  }
  return r.stdout;
}
// Runs the skill's stage `script` (under scripts/) on `run`; the MP4 it would
// deliver.
function runStage(script, run) {
  capture(process.execPath, [path.join(skill, "scripts", script), run]);
  return path.join(run, "out", `${path.basename(run)}.mp4`);
}
const count = (file) =>
  +capture("ffprobe", [
    ...["-v", "error", "-count_frames", "-select_streams", "v:0"],
    ...["-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", file],
  ]).trim();
const hashes = (file) =>
  capture("ffmpeg", [
    ...["-v", "error", "-i", file, "-map", "0:v", "-f", "framemd5", "-"],
  ])
    .split("\n")
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => l.split(",").at(-1).trim());
const grid = (scenes) =>
  gridScenes(
    scenes.map((s) => s.frames / FPS),
    HOLD,
  ).total;

// The whole: its frame count against the grid, then two more renders against
// the first, frame for frame.
const whole = runFolder(work, "whole", WHOLE);
runStage("render/timing.mjs", whole);
runStage("gates/gates.mjs", whole);
const mp4 = runStage("render/render.mjs", whole);
const frames = count(mp4);
const want = grid(WHOLE);
check("frame count", frames === want, `${frames} frames vs the grid's ${want}`);
const first = hashes(mp4);
const diffs = [2, 3].flatMap((k) => {
  const d = differing(first, hashes(runStage("render/render.mjs", whole)));
  return d.length
    ? [
        `render ${k} differs at frame(s) ${d.slice(0, 10).join(", ")}${d.length > 10 ? ` and ${d.length - 10} more` : ""}`,
      ]
    : [];
});
if (first.length !== frames)
  diffs.unshift(`render 1 hashed ${first.length} of its ${frames} frames`);
check(
  "determinism",
  !diffs.length,
  diffs.join("; ") || `3 renders, ${first.length} frames each, identical`,
);

// Each chapter rendered on its own, the parts joined by the chapter join with
// one narration over the whole and a mark at each chapter's first frame.
const parts = CHAPTERS.map((c, k) => {
  const run = runFolder(work, `chapter-${k + 1}`, c.scenes);
  runStage("render/timing.mjs", run);
  runStage("gates/gates.mjs", run);
  return runStage("render/render.mjs", run);
});
const sizes = parts.map(count);
const sum = sizes.reduce((a, n) => a + n, 0);
let at = 0;
const chapters = CHAPTERS.map((c, k) => {
  const start = at / FPS;
  at += sizes[k];
  return { start, end: at / FPS, title: c.title };
});
const audio = path.join(work, "narration.wav");
fs.writeFileSync(audio, tone(sum));
const output = path.join(work, "chapters.mp4");
const backend = await loadBackend();
await joinChapters(backend, {
  parts,
  joined: path.join(work, "joined.mp4"),
  audio,
  chapters,
  output,
});
const joined = count(output);
check(
  "chapter join",
  joined === sum,
  `${joined} frames vs the parts' ${sizes.join(" + ")} = ${sum}`,
);
const [, got, wanted, marked] = chapterCheck(
  chapters,
  (await backend.ffprobe(output)).chapters,
);
check("chapter marks", marked, `${got} vs ${wanted}`);

// Five gates, each on a one-scene fixture built to fail it and the same fixture
// without the defect, layout twice more on a clip seen at one sample only. The
// gate line is read from the stage's stdout, since a red gate exits 1.
// Determinism's failing twin reads the wall clock.
const BOX =
  '<div id="b" style="position:absolute;left:160px;top:600px;width:200px;height:200px;background:#7cc"></div>';
const slide = (x) => `tl.to("#b", { x: ${x}, duration: 3, ease: "none" }, 0);`;
const line = (top, width = 1200) =>
  `<div id="l" style="position:absolute;left:200px;top:${top}px;width:${width}px;overflow:hidden;white-space:nowrap;font:700 60px Inter,sans-serif;color:#fff"><span>A line the viewer reads</span></div>`;
// The line clipped from `from` to `to` s only: the 4 s scene's key sample is
// at 2 s, its out at 3.967 s.
const clipped = (from, to) =>
  `tl.set("#l", { width: 200 }, ${from});` +
  (to ? ` tl.set("#l", { width: 1200 }, ${to});` : "");
const pairs = [
  {
    gate: "determinism",
    bad: [BOX, slide("Date.now() % 600")],
    good: [BOX, slide(600)],
    warn: "clock",
  },
  { gate: "layout", bad: [line(300, 200)], good: [line(300)] },
  {
    gate: "layout",
    name: "layout at key only",
    bad: [line(300), clipped(1.8, 2.2)],
    good: [line(300)],
  },
  {
    gate: "layout",
    name: "layout at out only",
    bad: [line(300), clipped(3.6)],
    good: [line(300)],
  },
  { gate: "caption band", bad: [line(900)], good: [line(300)] },
  {
    gate: "anchors",
    bad: [BOX + line(300), 'tl.to("#b", { x: 300 }, at("one", "nosuchword"));'],
    good: [BOX + line(300), 'tl.to("#b", { x: 300 }, at("one", "Scene"));'],
  },
  {
    gate: "script errors",
    bad: [line(300), 'throw new Error("no such element");'],
    good: [line(300)],
  },
];
let fixture = 0;
function gateOf(gate, [body, js]) {
  const run = runFolder(work, `gate-${++fixture}`, [
    { id: "one", frames: 90, html: authored("one", body, js) },
  ]);
  runStage("render/timing.mjs", run);
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", "gates", "gates.mjs"), run],
    { encoding: "utf8", maxBuffer: 1 << 26 },
  );
  const m = r.stdout.match(
    new RegExp(`^gate ${gate}: (pass|fail): (.*)$`, "m"),
  );
  if (!m)
    throw new Error(
      `gates.mjs ${gate}: ${r.stdout.trim()}\n${r.stderr.trim()}`,
    );
  return { status: m[1], measured: m[2], out: r.stdout };
}
for (const { gate, name = gate, bad, good, warn } of pairs) {
  const [b, g] = [gateOf(gate, bad), gateOf(gate, good)];
  const warned = (r) => new RegExp(`^warn ${warn}:`, "m").test(r.out);
  check(
    `gate ${name}`,
    b.status === "fail" &&
      g.status === "pass" &&
      (!warn || (warned(b) && !warned(g))),
    `failing twin: ${b.measured}; passing twin: ${g.measured}`,
  );
}
process.exit(failed ? 1 : 0);
