// The gates stage: the run's last render judged against the skill's floors.
//
//   node gates.mjs <run-folder>
//
// Reads <run>/script.json, timeline.json, style.json (its floors through
// lib/style.mjs), composition/ and out/<slug>.mp4|.srt. Samples each scene
// every 15 frames from its start and at its settled last frame; HyperFrames'
// check and the layout probe measure the samples of every scene not cached in
// <run>/.cache/gates/, judged here for layout and contrast. Loudness and
// captions are measured on every run. Deletes nothing: the render stage acts
// on the verdict.
// stdout: `gate <name>: pass|fail: <measured> vs <floor>` for layout, contrast,
//         loudness and captions, then `gates: <n> pass, <m> fail`, when red
//         ending `; next: fix attempt <a> of 2` or `; stop: red after two fix
//         attempts, no video`
// writes: <run>/gates.json, gates.md, .cache/gates/
// exit:   0 every gate passes · 1 a gate fails, or `gates: <why>` on stderr ·
//         2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { LUFS, contrast, floors, loadStyle } from "../lib/style.mjs";
import { hyperframesEnv, loadBackend, renderInputs } from "../lib/tools.mjs";
import { CUE_CHARS, FPS, H, W } from "../render/compose.mjs";

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
    fail(e.message);
  }
}
const slug = path.basename(path.resolve(run));
const r3 = (n) => +n.toFixed(3);
const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts)
    h.update(
      typeof p === "string" || Buffer.isBuffer(p) ? p : JSON.stringify(p),
    );
  return h.digest("hex").slice(0, 16);
};
const read = (f) => fs.readFileSync(path.join(run, f), "utf8");
const mp4 = `out/${slug}.mp4`;
const srtFile = `out/${slug}.srt`;
for (const f of [
  "script.json",
  "timeline.json",
  "style.json",
  "composition/index.html",
  mp4,
  srtFile,
])
  if (!fs.existsSync(path.join(run, f)))
    fail(`no ${f}: run the render stage first`);
const script = JSON.parse(read("script.json"));
const timeline = JSON.parse(read("timeline.json"));
let profile, floor;
try {
  profile = loadStyle(run, script.style);
  floor = floors(profile);
} catch (e) {
  fail(e.message);
}
const { textPx, margin } = floor.layout;
const backend = await loadBackend();

const unescape = (s) =>
  s
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&amp;", "&");
const cues = [
  ...read("composition/index.html").matchAll(
    /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
  ),
].map((m) => ({
  start: +m[1],
  end: +m[1] + +m[2],
  text: [...m[3].matchAll(/<span class="w"[^>]*>(.*?)<\/span>/g)]
    .map((w) => unescape(w[1]))
    .join(" "),
}));

// Per scene: its samples, and its layout and contrast evidence, cached by
// everything that draws its frames, every floor that judges them, and the
// code that draws, measures and judges: the root page's composer, this file,
// the probe and the contrast maths.
const inputs = renderInputs([
  ...new Set(["title", "text", "code"].map((r) => profile.type[r].font)),
]);
const source = [
  "../render/compose.mjs",
  "gates.mjs",
  "../lib/backend.mjs",
  "../lib/style.mjs",
].map((f) =>
  fs.readFileSync(fileURLToPath(new URL(f, import.meta.url)), "utf8"),
);
const cacheDir = path.join(run, ".cache", "gates");
fs.mkdirSync(cacheDir, { recursive: true });
const plan = timeline.scenes.map((sc) => {
  const end = sc.start + sc.duration;
  const last = end - 1 / FPS;
  const times = [];
  for (let k = 0; sc.start + (k * 15) / FPS < last - 1e-6; k++)
    times.push(r3(sc.start + (k * 15) / FPS));
  times.push(r3(last));
  const file = path.join(
    cacheDir,
    `${hash(
      read(`composition/scenes/${sc.id}.html`),
      [times, W, H, sc.duration, sc.sentences],
      profile,
      script.title,
      inputs,
      cues.filter((c) => c.start >= sc.start && c.start < end),
      floor,
      source,
    )}.json`,
  );
  const cached = fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : null;
  return { sc, end, times, file, found: cached };
});

const todo = plan.filter((p) => !p.found);
if (todo.length) {
  const env = hyperframesEnv();
  const comp = path.join(run, "composition");
  const times = todo.flatMap((p) => p.times);
  const checked = await orFail(() => backend.check(comp, times, { env }));
  // A check that never reached the browser answers {ok: false, error} alone.
  if (!checked.layout || !checked.contrast)
    fail(
      `hyperframes check: ${checked.error ?? "no layout or contrast result"}`,
    );
  const frames = await orFail(() => backend.probe(comp, times, { env }));
  // A scene with no text of its own in any sample is a probe that saw nothing,
  // not a pass: captions and the header draw over every scene.
  for (const p of todo)
    if (
      !frames.some(
        (f) =>
          p.times.includes(f.t) && f.elements.some((e) => e.scene === p.sc.id),
      )
    )
      fail(`layout probe: no text in scene ${p.sc.id}`);
  for (const p of todo) p.found = { layout: [], contrast: [] };
  // One defect held across a scene is one finding: its first time, and the
  // number of samples it showed in.
  const seen = new Map();
  const add = (gate, t, what) => {
    const p = todo.find((p) => t < p.end - 1e-6) ?? todo.at(-1);
    const key = `${gate} ${p.sc.id}: ${what}`;
    const hit = seen.get(key);
    if (hit) return (hit.n += 1);
    seen.set(key, { p, gate, at: p.found[gate].length, t, what, n: 1 });
    p.found[gate].push("");
  };
  const settle = () => {
    for (const { p, gate, at, t, what, n } of seen.values())
      p.found[gate][at] =
        `${t.toFixed(2)} s ${p.sc.id}: ${what}${n > 1 ? ` (${n} samples)` : ""}`;
  };
  for (const f of checked.layout.findings)
    if (f.severity === "error") add("layout", f.time, `${f.code} "${f.text}"`);
  for (const f of checked.contrast.findings)
    if (f.severity === "error")
      add(
        "contrast",
        f.time,
        `${f.code} "${f.text}" ${f.ratio}:1 under ${f.requiredRatio}:1`,
      );
  const safe = {
    left: margin * W,
    top: margin * H,
    right: W * (1 - margin),
    bottom: H * (1 - margin),
  };
  const outside = (r, c, by) =>
    r.left < c.left - by ||
    r.top < c.top - by ||
    r.right > c.right + by ||
    r.bottom > c.bottom + by;
  const overlap = (a, b) =>
    Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
    Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1 &&
    outside(a, b, 0) &&
    outside(b, a, 0);
  for (const { t, elements } of frames) {
    // Mid-reveal text is judged once it settles.
    const shown = elements.filter((e) => e.opacity >= 0.99);
    shown.forEach((e, i) => {
      const bad = (what) => add("layout", t, `${what} "${e.text}"`);
      if (e.fontPx < textPx - 0.5) bad(`small ${e.fontPx} px`);
      if (
        !e.inline &&
        (e.scrollW > e.clientW + 1 || e.scrollH > e.clientH + e.fontPx / 4)
      )
        bad(`overflow ${e.scrollW}x${e.scrollH} in ${e.clientW}x${e.clientH}`);
      if (e.clip && outside(e.rect, e.clip, 1)) bad("clipped");
      if (outside(e.rect, safe, 0)) bad("outside the safe margin");
      for (const o of shown.slice(i + 1))
        if (overlap(e.rect, o.rect))
          add("layout", t, `"${e.text}" overlaps "${o.text}"`);
      const large = e.fontPx >= 24 || (e.fontPx >= 18.66 && e.weight >= 700);
      const need = floor.contrast[large ? "large" : "body"];
      const ratio = contrast(e.color, e.bg);
      if (ratio < need)
        add(
          "contrast",
          t,
          `"${e.text}" ${e.color} on ${e.bg} ${ratio.toFixed(2)}:1 under ${need}:1`,
        );
    });
  }
  settle();
  for (const p of todo) fs.writeFileSync(p.file, JSON.stringify(p.found));
}

// Loudness, on the encoded MP4.
const { lufs, peak } = await orFail(() =>
  backend.loudness(path.join(run, mp4)),
);
const { tolerance, peak: ceiling } = floor.loudness;
const loud = [];
if (Math.abs(lufs - LUFS) > tolerance)
  loud.push(
    `integrated ${lufs.toFixed(1)} LUFS is ${Math.abs(lufs - LUFS).toFixed(1)} LU off ${LUFS}`,
  );
if (peak > ceiling)
  loud.push(`true peak ${peak.toFixed(1)} dBTP over ${ceiling}`);

// Captions: the timeline's words, the composition's cues, and the SRT as the
// cues' copy.
const caps = [];
const eps = 1e-6;
for (const sc of timeline.scenes)
  sc.words.forEach((w, i) => {
    const at = `word ${i + 1} "${w.text}" of ${sc.id}`;
    if (!(w.start < w.end)) caps.push(`${at} does not start before it ends`);
    if (i && w.start < sc.words[i - 1].end - eps)
      caps.push(`${at} starts before the word before it ends`);
    if (w.start < sc.start - eps || w.end > sc.start + sc.duration + eps)
      caps.push(`${at} falls outside its scene`);
  });
cues.forEach((c, i) => {
  const at = `cue ${i + 1}`;
  if (!c.text.trim() || !(c.start < c.end)) caps.push(`${at} is empty`);
  if (c.text.length > CUE_CHARS)
    caps.push(`${at} holds ${c.text.length} characters, over ${CUE_CHARS}`);
  if (i && c.start < cues[i - 1].end - eps)
    caps.push(`${at} starts before cue ${i} ends`);
  if (c.end > timeline.total + 0.001)
    caps.push(`${at} runs past the video's ${timeline.total} s`);
});
const seconds = (t = "") => {
  const m = t.trim().match(/^(\d+):(\d\d):(\d\d)[,.](\d{3})$/);
  return m ? +m[1] * 3600 + +m[2] * 60 + +m[3] + +m[4] / 1000 : NaN;
};
const srt = read(srtFile)
  .trim()
  .split(/\r?\n\r?\n/)
  .filter(Boolean)
  .map((b) => {
    const [, times = "", ...text] = b.split(/\r?\n/);
    const [a, z] = times.split(" --> ");
    return { start: seconds(a), end: seconds(z), text: text.join(" ") };
  });
if (srt.length !== cues.length)
  caps.push(
    `the SRT holds ${srt.length} cue(s), the composition ${cues.length}`,
  );
else
  srt.forEach((s, i) => {
    const c = cues[i];
    if (s.text !== c.text)
      caps.push(
        `SRT cue ${i + 1} reads "${s.text}", the composition "${c.text}"`,
      );
    if (!(
      Math.abs(s.start - c.start) <= 0.001 + eps &&
      Math.abs(s.end - c.end) <= 0.001 + eps
    ))
      caps.push(
        `SRT cue ${i + 1} runs ${s.start}-${s.end} s, the composition ${r3(c.start)}-${r3(c.end)} s`,
      );
  });

// The verdicts. A gate's attempts count its consecutive red renders of this
// script, and the run's attempts every red render of it since the last green
// one, so a red that moves between gates still stops: a pass, or a changed
// script, starts a count again, and the same render judged again is no new
// attempt.
const summary = (ev) =>
  `${ev.length} finding(s)${ev.length ? `, first: ${ev[0]}` : ""}`;
const layoutFindings = plan.flatMap((p) => p.found.layout);
const contrastFindings = plan.flatMap((p) => p.found.contrast);
const judged = {
  layout: [
    layoutFindings,
    summary(layoutFindings),
    `none, text >= ${textPx} px, margin ${r3(margin * 100)}%`,
  ],
  contrast: [
    contrastFindings,
    summary(contrastFindings),
    `body ${floor.contrast.body}:1, large ${floor.contrast.large}:1`,
  ],
  loudness: [
    loud,
    `${lufs.toFixed(1)} LUFS, peak ${peak.toFixed(1)} dBTP`,
    `${LUFS} +-${tolerance} LUFS, peak <= ${ceiling} dBTP`,
  ],
  captions: [caps, `${cues.length} cue(s), ${summary(caps)}`, "none"],
};
const scriptHash = hash(script.scenes.map((s) => [s.id, s.narration]));
const renderHash = hash(
  read("composition/index.html"),
  ...fs
    .readdirSync(path.join(run, "composition", "scenes"))
    .filter((f) => f.endsWith(".html"))
    .sort()
    .map((f) => read(`composition/scenes/${f}`)),
  fs.readFileSync(path.join(run, mp4)),
  read(srtFile),
);
const recordFile = path.join(run, "gates.json");
const prev = fs.existsSync(recordFile)
  ? JSON.parse(fs.readFileSync(recordFile, "utf8"))
  : null;
const same = prev?.script === scriptHash;
const again = same && prev.render === renderHash;
const count = (failing, before) =>
  !failing ? 0 : again ? before || 1 : before + 1;
const gates = {};
for (const [name, [evidence, measured, wanted]] of Object.entries(judged))
  gates[name] = {
    status: evidence.length ? "fail" : "pass",
    measured,
    floor: wanted,
    attempts: count(evidence.length, same ? prev.gates[name].attempts : 0),
    evidence,
  };
const red = Object.entries(gates).filter(([, g]) => g.status === "fail");
const attempts = count(red.length, same ? prev.attempts : 0);
fs.writeFileSync(
  recordFile,
  JSON.stringify(
    { script: scriptHash, render: renderHash, attempts, gates },
    null,
    2,
  ) + "\n",
);

const cell = (s) => String(s).replaceAll("|", "\\|");
fs.writeFileSync(
  path.join(run, "gates.md"),
  [
    "# Video gates",
    "",
    "| gate | status | measured | floor | attempts |",
    "| --- | --- | --- | --- | --- |",
    ...Object.entries(gates).map(
      ([n, g]) =>
        `| ${n} | ${g.status} | ${cell(g.measured)} | ${cell(g.floor)} | ${g.attempts} |`,
    ),
    ...red.flatMap(([n, g]) => [
      "",
      `## ${n}`,
      "",
      ...g.evidence.map((e) => `- ${e}`),
    ]),
  ].join("\n") + "\n",
);
for (const [name, g] of Object.entries(gates))
  console.log(`gate ${name}: ${g.status}: ${g.measured} vs ${g.floor}`);
console.log(
  `gates: ${Object.keys(gates).length - red.length} pass, ${red.length} fail${
    !red.length
      ? ""
      : attempts >= 3
        ? "; stop: red after two fix attempts, no video"
        : `; next: fix attempt ${attempts} of 2`
  }`,
);
process.exit(red.length ? 1 : 0);
