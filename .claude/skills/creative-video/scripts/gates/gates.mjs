// The gates stage: the authored project judged on what it renders, before the
// full render (ADR 0019: output and narration, never scene code).
//
//   node gates.mjs <run-folder>
//
// Reads <run>/timeline.json, script.json, brief.json (optional: `must` and
// `avoid` word lists) and <run>/project/. Samples each scene 0.3 s in, at its
// middle and on its last frame (gates/samples.mjs), and measures the samples
// with HyperFrames' check, a text probe (one launch, over the samples and a
// 0.25 s grid) and two snapshot launches. Seven gates judge the project, each a
// hard fail: determinism (the same pixels twice), layout, contrast, reading
// time, the caption band, anchors (an at() naming a word the narration lacks)
// and must and avoid. Length, loudness and voice QC are the voice and render
// stages' own. Advisory warnings never change the exit: effect rate, effect
// onset, scene length, long sentences, pacing, and the clock and random scan.
// stdout: `gate <name>: pass|fail: <measured> vs <floor>` per gate (the rest of
//         a failing gate's findings indented under it), `warn <name>: <detail>`
//         per warning, then `gates: <n> pass, <m> fail`, when red ending `; next:
//         fix attempt <a> of 2` or, past two, `; stop: red after two fix
//         attempts, no video`
// writes: <run>/gates.json (the inputs and script it is of, the attempts, each
//         gate's status, measured, floor and evidence, the warnings),
//         .cache/gates/frames/a and b, and the root again (render/root.mjs)
// exit:   0 every gate passes · 1 a gate fails, or `gates: <why>` on stderr
//         (the render's own refusals: no timeline, an older voice, a missing
//         scene file) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { maybeJson, readJson } from "../lib/json.mjs";
import { sentences } from "../lib/length.mjs";
import { readTimeline, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend } from "../lib/tools.mjs";
import { HEIGHT, WIDTH, writeRoot } from "../render/root.mjs";
import { inputsHash, scriptHash } from "./inputs.mjs";
import { readable, readingFindings } from "./reading.mjs";
import { ceil3, sampleTimes } from "./samples.mjs";

stage("gates");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node gates.mjs <run-folder>");
  process.exit(2);
}
function fail(why) {
  console.error(`gates: ${why}`);
  process.exit(1);
}
async function orFail(call) {
  try {
    return await call();
  } catch (e) {
    return fail(e.message);
  }
}

// The floors: type of at least 18 px inside a margin of 5% of each side, the
// bottom 220 px left to the captions, at most two fix attempts.
const TEXT_PX = 18;
const MX = Math.round(WIDTH * 0.05);
const MY = Math.round(HEIGHT * 0.05);
const BAND = HEIGHT - 220;
const MAX_ATTEMPTS = 2;

const { timeline } = readTimeline(run, fail);
const script = readJson(run, "script.json");
const brief = maybeJson(run, "brief.json");
const record = path.join(run, "gates.json");
const prev = fs.existsSync(record)
  ? JSON.parse(fs.readFileSync(record, "utf8"))
  : null;
writeIgnore(run);
writeRoot(run);
const inputs = inputsHash(run);
const proj = path.join(path.resolve(run), "project");
const backend = await loadBackend();
const env = hyperframesEnv();
const uniq = (ts) => [...new Set(ts)].sort((a, b) => a - b);

// Each scene's sample times, and the probe's 0.25 s grid over its length.
const plan = timeline.scenes.map((sc) => {
  const end = sc.start + sc.duration;
  const grid = [];
  for (let t = sc.start; t < end; t += 0.25) grid.push(ceil3(t));
  return { sc, end, samples: uniq(Object.values(sampleTimes(sc))), grid };
});
const sampled = uniq(plan.flatMap((p) => p.samples));
const sceneAt = (t) =>
  (plan.find((p) => t >= p.sc.start - 1e-6 && t < p.end) ?? plan.at(-1)).sc.id;
const sceneOf = (f) =>
  f.sourceFile?.match(/^compositions\/(.+)\.html$/)?.[1] ?? sceneAt(f.time);
const quote = (t) => `"${t.length > 40 ? `${t.slice(0, 40)}...` : t}"`;

const checked = await orFail(() => backend.check(proj, sampled, { env }));
// A check that never reached the browser answers {ok: false, error} alone.
for (const k of ["runtime", "layout", "contrast"])
  if (!checked[k])
    fail(`hyperframes check: ${checked.error ?? `no ${k} result`}`);
const { frames, events } = await orFail(() =>
  backend.probe(proj, uniq([...sampled, ...plan.flatMap((p) => p.grid)]), {
    env,
  }),
);
// A scene's own text at a probe time: the captions are drawn over every scene.
const sceneTexts = (f) => f.texts.filter((e) => e.scene !== "captions");
const textsAt = (t) => sceneTexts(frames.find((f) => f.t === t));

// Determinism: the sample frames rendered in two launches, compared by pixels.
fs.rmSync(path.join(run, ".cache", "gates", "frames"), {
  recursive: true,
  force: true,
});
const launch = (d) =>
  orFail(async () => {
    const taken = await backend.snapshot(
      proj,
      sampled,
      path.resolve(run, ".cache", "gates", "frames", d),
      { env },
    );
    return Promise.all(
      taken.map(async (f) => [f.time, await backend.framePixels(f.path)]),
    );
  });
const [a, b] = [await launch("a"), await launch("b")];
if (a.length !== sampled.length || b.length !== sampled.length)
  fail(`snapshot gave ${a.length} and ${b.length} of ${sampled.length} frames`);
const determinism = a.flatMap(([t, pixels], i) =>
  pixels === b[i][1]
    ? []
    : [
        `${t.toFixed(2)} s ${sceneAt(t)}: the frame differs between two launches`,
      ],
);

// One defect held across several samples is one finding: its first time, and
// the number of samples it showed in.
function collect() {
  const seen = new Map();
  return {
    add(t, scene, what) {
      const hit = seen.get(`${scene}: ${what}`);
      if (hit) hit.n++;
      else seen.set(`${scene}: ${what}`, { t, scene, what, n: 1 });
    },
    lines: () =>
      [...seen.values()].map(
        ({ t, scene, what, n }) =>
          `${t.toFixed(2)} s ${scene}: ${what}${n > 1 ? ` (${n} samples)` : ""}`,
      ),
  };
}

// Layout: HyperFrames' errors (it grades a defect seen at one sample only as
// info, a flicker rather than a defect), and the probe's readable text at the
// samples. The caption band is the same text against the bottom 220 px.
const layout = collect();
const band = collect();
for (const f of checked.layout.findings)
  if (f.severity === "error")
    layout.add(
      f.time,
      sceneOf(f),
      `${f.code}${f.text ? `: ${quote(f.text)}` : ""}`,
    );
for (const p of plan)
  for (const t of p.samples)
    for (const e of textsAt(t).filter(readable)) {
      const { left, top, right, bottom } = e.rect;
      if (left < MX || top < MY || right > WIDTH - MX || bottom > HEIGHT - MY)
        layout.add(t, p.sc.id, `${quote(e.text)} is outside the safe margin`);
      if (e.fontPx < TEXT_PX)
        layout.add(
          t,
          p.sc.id,
          `${quote(e.text)} is ${Math.round(e.fontPx)} px, under ${TEXT_PX} px`,
        );
      if (bottom > BAND)
        band.add(
          t,
          p.sc.id,
          `${quote(e.text)} at y ${Math.round(top)}-${Math.round(bottom)}`,
        );
    }

// Contrast: HyperFrames grades a failure a warning, the gate fails on it.
const contrast = collect();
for (const f of checked.contrast.findings)
  if (f.code === "contrast_aa_failure")
    contrast.add(
      f.time,
      sceneOf(f),
      `${quote(f.text)} ${f.ratio}:1 under ${f.requiredRatio}:1`,
    );

// Reading time, scene by scene on the probe's frames.
const reading = plan.flatMap((p) =>
  readingFindings({
    id: p.sc.id,
    end: p.end,
    frames: frames
      .filter((f) => f.t >= p.sc.start - 1e-6 && f.t < p.end)
      .map((f) => ({ t: f.t, texts: sceneTexts(f) })),
    samples: p.samples,
  }),
);

// Anchors: a scene script's at() threw for a word the alignment lacks.
const anchors = [];
for (const f of checked.runtime.findings) {
  const m = f.message?.match(/at: no word "(.*?)" \(\d+\) in scene (\S+)/);
  const start = timeline.scenes.find((s) => s.id === m?.[2])?.start ?? 0;
  const line = m && `${start.toFixed(2)} s ${m[2]}: at: no word "${m[1]}"`;
  if (line && !anchors.includes(line)) anchors.push(line);
}

// Must and avoid, carried from explainer-video's script check: a whole-word
// match over each scene's narration and the text its samples show.
const has = (corpus, item) =>
  new RegExp(
    `(?<![\\p{L}\\p{N}])${item.toLowerCase().replace(/[.*+?^$|()[\]{}\\]/g, "\\$&")}(?![\\p{L}\\p{N}])`,
    "u",
  ).test(corpus);
const corpus = plan.map((p) => ({
  id: p.sc.id,
  text: [
    ...(script.scenes.find((s) => s.id === p.sc.id)?.narration ?? []),
    ...p.samples.flatMap((t) => textsAt(t).map((e) => e.text)),
  ]
    .join("\n")
    .toLowerCase(),
}));
const coverage = [];
for (const m of brief?.must ?? [])
  if (!corpus.some((c) => has(c.text, m)))
    coverage.push(`must "${m}" is not said or shown`);
for (const x of brief?.avoid ?? []) {
  const hit = corpus.filter((c) => has(c.text, x));
  if (hit.length)
    coverage.push(`avoid "${x}" is in ${hit.map((c) => c.id).join(", ")}`);
}

const summary = (ev) =>
  `${ev.length} finding(s)${ev.length ? `, first: ${ev[0]}` : ""}`;
const judged = {
  determinism: [determinism, "the same pixels twice"],
  layout: [layout.lines(), `none, text >= ${TEXT_PX} px, margin 5%`],
  contrast: [contrast.lines(), "WCAG AA 4.5:1, 3:1 large"],
  reading: [
    reading,
    "each text readable 0.8 s (up to 3 words) or 0.3 s a word, 1.2 s at least",
  ],
  "caption band": [band.lines(), "no readable text in the bottom 220 px"],
  anchors: [anchors, "every anchor names an aligned word"],
  "must and avoid": [
    coverage,
    "every must said or shown, no avoid said or shown",
  ],
};
const gates = Object.fromEntries(
  Object.entries(judged).map(([name, [evidence, floor]]) => [
    name,
    {
      status: evidence.length ? "fail" : "pass",
      measured: summary(evidence),
      floor,
      evidence,
    },
  ]),
);
const red = Object.values(gates).filter((g) => g.status === "fail").length;

// Advisory: reported, never a refusal.
const warnings = new Set();
const warn = (name, detail) => warnings.add(`${name}: ${detail}`);
const mine = (id) => events[id] ?? { tweens: [], sounds: [] };
const sounds = plan.flatMap((p) =>
  mine(p.sc.id).sounds.map((s) => p.sc.start + s),
);
let busiest = { n: 0, t: 0 };
for (const t of sounds) {
  const n = sounds.filter((o) => o >= t && o < t + 60).length;
  if (n > busiest.n) busiest = { n, t };
}
if (busiest.n > 24)
  warn(
    "effect rate",
    `${busiest.n} sounds in the minute from ${busiest.t.toFixed(2)} s, over 24 a minute`,
  );
let starts = 0;
const dead = [];
for (const p of plan) {
  const { tweens, sounds: own } = mine(p.sc.id);
  starts += tweens.length;
  for (const s of own) {
    const gap = Math.min(...tweens.map(([from]) => Math.abs(s - from)));
    if (tweens.length && gap > 0.15 + 1e-6)
      warn(
        "effect onset",
        `${p.sc.id}: the sound at ${s.toFixed(2)} s is ${gap.toFixed(2)} s from the nearest tween start`,
      );
  }
  if (p.sc.duration > 30)
    warn(
      "scene length",
      `${p.sc.id}: ${p.sc.duration.toFixed(1)} s, over 30 s`,
    );
  // A dead stretch: 2 s or more with no tween running.
  let at = 0;
  for (const [from, to] of [...tweens]
    .sort((x, y) => x[0] - y[0])
    .concat([[p.sc.duration, p.sc.duration]])) {
    if (from - at >= 2)
      dead.push(
        `dead ${(p.sc.start + at).toFixed(2)}-${(p.sc.start + from).toFixed(2)} s in ${p.sc.id}`,
      );
    at = Math.max(at, to);
  }
}
for (const s of script.scenes)
  for (const line of s.narration)
    for (const sentence of sentences(line)) {
      const words = sentence.split(/\s+/).filter(Boolean);
      if (words.length > 25)
        warn(
          "sentences",
          `${s.id}: "${words.slice(0, 5).join(" ")}..." is ${words.length} words, over 25`,
        );
    }
warn(
  "pacing",
  `${((starts + sounds.length) / (timeline.total / 60)).toFixed(1)} change events a minute; ${dead.join("; ") || "no dead stretch"}`,
);
// The one place a gate reads scene code (ADR 0019): a clock or random read may
// break determinism, which the frames judge, so it is named, never refused.
const CLOCK = [
  ["Math.random", /Math\.random\b/],
  ["Date.now", /Date\.now\b/],
  ["new Date", /new Date\b/],
  ["performance.now", /performance\.now\b/],
  ["setTimeout", /\bsetTimeout\b/],
  ["setInterval", /\bsetInterval\b/],
  ["requestAnimationFrame", /\brequestAnimationFrame\b/],
];
const listed = (dir) =>
  fs.existsSync(path.join(proj, dir))
    ? fs
        .readdirSync(path.join(proj, dir), { withFileTypes: true })
        .filter((e) => e.isFile() && e.name !== "captions.html")
        .map((e) => `${dir}/${e.name}`)
        .sort()
    : [];
for (const f of [...listed("compositions"), ...listed("kit")]) {
  const code = fs.readFileSync(path.join(proj, f), "utf8");
  const found = CLOCK.filter(([, re]) => re.test(code)).map(([name]) => name);
  if (found.length) warn("clock", `${f} reads ${found.join(", ")}`);
}

// The fix cap: a red run on one script is one fix attempt, the same inputs
// judged again are none, and a pass or a changed script starts the count again.
const scriptKey = scriptHash(script);
const same = prev?.script === scriptKey;
const attempts = !red
  ? 0
  : same && prev.inputs === inputs
    ? Math.max(prev.attempts ?? 0, 1)
    : (same ? (prev.attempts ?? 0) : 0) + 1;
fs.writeFileSync(
  record,
  JSON.stringify(
    { inputs, script: scriptKey, attempts, gates, warnings: [...warnings] },
    null,
    2,
  ) + "\n",
);

for (const [name, g] of Object.entries(gates)) {
  console.log(`gate ${name}: ${g.status}: ${g.measured} vs ${g.floor}`);
  for (const e of g.evidence.slice(1)) console.log(`  ${e}`);
}
for (const w of warnings) console.log(`warn ${w}`);
console.log(
  `gates: ${Object.keys(gates).length - red} pass, ${red} fail${
    red
      ? attempts > MAX_ATTEMPTS
        ? "; stop: red after two fix attempts, no video"
        : `; next: fix attempt ${attempts} of ${MAX_ATTEMPTS}`
      : ""
  }`,
);
process.exit(red ? 1 : 0);
