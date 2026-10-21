// Maintainer only: re-measure the render rates the storyboard's estimate reads
// and write them into render-rates.json, with the HyperFrames version they were
// measured on. Run it with each HyperFrames bump.
//
//   node maintainer/calibrate-render-rates.mjs [render-rates.json] [--runs <n>]
//   (from the skill folder)
//
// Needs every stage row installed (`node scripts/setup.mjs install`) and, for
// the live 3D video, an NVIDIA card. Three videos are made through the stage
// scripts, never through a stand-in, on this machine's real render path: a flat
// one (a style with no texture), the same scenes in the default texture, and
// those with a `stack3d` scene added. Each is composed, voiced and stilled once
// (not timed), then timed `--runs` times (default 3), the median kept. A timed
// run clears the render and gates caches and runs render.mjs, which renders the
// video and gates it cold; a second render.mjs run on the cached video, the
// gates cache cleared again, times the gates alone. Render seconds are the
// first run less the second. The brief's `score` is off. The rates, in render
// seconds per video second:
//   base     flat render / flat video s
//   texture  textured render / textured video s, less base
//   live3d   (live3d render - textured render / textured video s * live3d video
//            s) / the stack scene's s
//   gates    textured gates / textured video s
// stdout, per timed run:
//   calibrate-render <video> run <i>/<n>: render <s> s, gates <s> s over <s> s
//   of video
// the live 3D video's lines end `, <s> s of it the stack scene`, the divisor of
// its rate. Then the values written:
//   calibrate-render: HyperFrames <version>: base <r>, texture <r>, live3d <r>,
//   gates <r> render s per video s
// exit:   0 written · 1 a stage failed or rendered nothing, the table left
//         alone · 2 usage
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { dest, skill } from "../scripts/lib/tools.mjs";

const args = process.argv.slice(2);
let runs = 3;
let file = path.join(skill, "render-rates.json");
const usage = () => {
  console.error(
    "usage: node calibrate-render-rates.mjs [render-rates.json] [--runs <n>]",
  );
  process.exit(2);
};
for (let i = 0, named = false; i < args.length; i++) {
  if (args[i] === "--runs") {
    runs = Number(args[++i]);
    if (!Number.isInteger(runs) || runs < 1) usage();
  } else if (!args[i].startsWith("--") && !named) {
    file = args[i];
    named = true;
  } else usage();
}

// Three scenes of the house register, then the live 3D scene a third video adds.
const HEAD = `# How Ship lands a pull request
language: en
narrator: am_fenrir
`;
const SCENES = `
## Scene hook · The promise

### Narration
1. Ship drives an issue to a merged pull request, one run at a time. [no-claim]
2. Here is how it goes, from the first read to the last check. [no-claim]

### Visual
\`\`\`json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" } }
\`\`\`

## Scene steps · The steps

### Narration
1. It reads the issue and the files the issue names. [no-claim]
2. It writes a failing test that pins the behavior down. [no-claim]
3. Then the code makes that test pass, and nothing else changes. [no-claim]

### Visual
\`\`\`json
{ "component": "cards", "props": { "items": [ { "at": 1, "label": "Input", "value": "issue" }, { "at": 2, "label": "First", "value": "test", "note": "failing" }, { "at": 3, "label": "Then", "value": "code" } ] } }
\`\`\`

## Scene gate · The gate

### Narration
1. The local gate runs every check the repository carries. [no-claim]
2. Then it opens the pull request for a human to read. [no-claim]

### Visual
\`\`\`json
{ "component": "terminal", "props": { "title": "scripts/local-gate.sh", "lines": [ { "at": 1, "text": "$ scripts/local-gate.sh" }, { "at": 2, "text": "gh pr create" } ] } }
\`\`\`
`;
const STACK = `
## Scene stack · The stack

### Narration
1. The issue is the base of the stack. [no-claim]
2. A failing test sits on top of it. [no-claim]
3. Then the code on top makes the test pass. [no-claim]

### Visual
\`\`\`json
{ "component": "stack3d", "props": { "layers": [ { "at": 1, "label": "Issue" }, { "at": 2, "label": "Test" }, { "at": 3, "label": "Code" } ] } }
\`\`\`
`;

const fail = (why) => {
  console.error(`calibrate-render: ${why}`);
  process.exit(1);
};
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "calibrate-render-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const explainers = path.join(tmp, "proj", "explainers");

// A flat style: the default profile with no texture at all.
const base = JSON.parse(
  fs.readFileSync(path.join(skill, "styles", "claude-code.json"), "utf8"),
);
fs.mkdirSync(path.join(explainers, ".styles"), { recursive: true });
fs.writeFileSync(
  path.join(explainers, ".styles", "calibrate-flat.json"),
  JSON.stringify({
    ...base,
    grammar: { ...base.grammar, texture: { surface: "flat", overlays: [] } },
  }),
);

// Runs a stage script on `run`; the wall seconds, the exit and the stderr.
function stage(name, run, ...rest) {
  const t = performance.now();
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", name), run, ...rest],
    { encoding: "utf8", maxBuffer: 1 << 28 },
  );
  return {
    seconds: (performance.now() - t) / 1000,
    code: r.status,
    why:
      (r.stderr.trim() || r.stdout.trim()).split("\n").at(-1) ||
      `exit ${r.status}`,
  };
}
const median = (xs) => [...xs].sort((a, b) => a - b)[(xs.length - 1) >> 1];
const r2 = (x) => Math.round(x * 100) / 100;

const videos = [
  { name: "flat", style: "calibrate-flat", scenes: SCENES },
  { name: "textured", style: "claude-code", scenes: SCENES },
  { name: "live3d", style: "claude-code", scenes: SCENES + STACK },
];
// Compose, voice and still each video, none of it timed.
for (const v of videos) {
  v.run = path.join(explainers, v.name);
  fs.mkdirSync(v.run, { recursive: true });
  fs.writeFileSync(
    path.join(v.run, "script.md"),
    `${HEAD}style: ${v.style}\n${v.scenes}`,
  );
  for (const [script, ...rest] of [
    ["script/compile.mjs"],
    // the voice stage holds a brief's length, which a short fixture misses, so
    // the brief that turns the score off comes after it
    ["voice/voice.mjs"],
    ["brief/brief.mjs", "score=off"],
    ["render/render.mjs", "--stills"],
  ]) {
    const r = stage(script, v.run, ...rest);
    if (r.code !== 0) fail(`${v.name}: ${script}: ${r.why}`);
  }
  const timeline = JSON.parse(
    fs.readFileSync(path.join(v.run, "timeline.json"), "utf8"),
  );
  v.video = timeline.total;
  v.stack = timeline.scenes.find((s) => s.id === "stack")?.duration;
}

// The video's render and gates seconds, `runs` times, the median of each.
function measure(v) {
  const caches = (...dirs) =>
    dirs.forEach((d) =>
      fs.rmSync(path.join(v.run, ".cache", d), {
        recursive: true,
        force: true,
      }),
    );
  const render = [];
  const gates = [];
  for (let i = 1; i <= runs; i++) {
    caches("render", "gates");
    // A gate left red by the critic still pending exits 1 after the video is
    // made; the video is what counts, and its absence is the failure.
    const first = stage("render/render.mjs", v.run);
    const cachedDir = path.join(v.run, ".cache", "render");
    if (
      !fs.existsSync(cachedDir) ||
      !fs.readdirSync(cachedDir).some((f) => /^[0-9a-f]{16}\.mp4$/.test(f))
    )
      fail(`${v.name}: rendered no video: ${first.why}`);
    caches("gates");
    const second = stage("render/render.mjs", v.run);
    render.push(first.seconds - second.seconds);
    gates.push(second.seconds);
    console.log(
      `calibrate-render ${v.name} run ${i}/${runs}: render ${r2(render.at(-1))} s, gates ${r2(gates.at(-1))} s over ${r2(v.video)} s of video${v.stack ? `, ${r2(v.stack)} s of it the stack scene` : ""}`,
    );
  }
  return { render: median(render), gates: median(gates) };
}
for (const v of videos) Object.assign(v, measure(v));

const [flat, textured, live3d] = videos;
const rates = {
  base: flat.render / flat.video,
  texture: textured.render / textured.video - flat.render / flat.video,
  live3d:
    (live3d.render - (textured.render / textured.video) * live3d.video) /
    live3d.stack,
  gates: textured.gates / textured.video,
};
// A delta below zero is noise between runs, not a render that costs less.
for (const k in rates) rates[k] = r2(Math.max(0, rates[k]));

const pkg = path.join(
  dest({ kind: "npm" }),
  "node_modules",
  "hyperframes",
  "package.json",
);
const hyperframes = JSON.parse(fs.readFileSync(pkg, "utf8")).version;
fs.writeFileSync(file, JSON.stringify({ hyperframes, rates }, null, 2) + "\n");
console.log(
  `calibrate-render: HyperFrames ${hyperframes}: ${Object.entries(rates)
    .map(([k, v]) => `${k} ${v}`)
    .join(", ")} render s per video s`,
);
