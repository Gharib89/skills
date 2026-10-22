// Maintainer only: render a short fixture with real HyperFrames and prove what
// the fake backend cannot: the frame grid holds (the render has exactly the
// composer's frames), a render is deterministic, and two halves joined by
// stream copy have the whole's frame count.
//
//   node maintainer/real-render.mjs
//
// Needs the render rows installed (`node scripts/setup.mjs install`) and
// ffmpeg. The fixture is FIXTURE in real-render-fixture.mjs, composed as
// render/render.mjs composes a run (the scenes on the frame grid, each scene's
// WAV padded to its frames, the last held HOLD seconds) with a synthetic tone
// for the narration. Its roles give both velocity seams: a zoom-through at the
// beat change out of the hook, a cut on a curve inside the point beat. The
// whole is rendered three times, the style's texture included (a second and a
// third render catch noise that drifts between runs, which two renders can
// match by chance), and the halves split it after `HALF` scenes: the first
// without the hold, the second with it. A three-section fixture
// (real-render-sections.mjs) is rendered whole and by section, joined and muxed
// as render.mjs does. Renders run through a raster-flag headless shell
// (real-render-shell.mjs); a failing determinism row names the differing
// frames and keeps their hash lists (real-render-compare.mjs).
// stdout: `real-render <check>: pass|fail: <detail>` per check
// exit:   0 every check passed · 1 a check failed · 2 a tool row is missing
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { sceneEvents } from "../scripts/gates/events.mjs";
import { readingFindings } from "../scripts/gates/reading.mjs";
import { HOLD } from "../scripts/lib/length.mjs";
import { judge } from "../scripts/lib/layout.mjs";
import { sampleTimes, seamStripStart } from "../scripts/lib/motion.mjs";
import { floors, loadStyle, typeRoles } from "../scripts/lib/style.mjs";
import { VISUALS, drawsWebgl } from "../scripts/lib/visuals.mjs";
import {
  catalogue,
  compositionAssets,
  dest,
  fontGap,
  fontRow,
  hyperframesEnv,
  loadBackend,
  skill,
} from "../scripts/lib/tools.mjs";
import { FPS, sceneFile, videoPage } from "../scripts/render/compose.mjs";
import { gridScenes, written } from "../scripts/render/grid.mjs";
import { joinNarration } from "../scripts/render/narration.mjs";
import { seamPlan, slot } from "../scripts/render/seams.mjs";
import { describe, differing, keepHashLists } from "./real-render-compare.mjs";
import { FIXTURE } from "./real-render-fixture.mjs";
import {
  RASTER_FLAGS,
  headlessShell,
  shellWith,
} from "./real-render-shell.mjs";
import { sectionChecks } from "./real-render-sections.mjs";
import { mapChecks } from "./real-render-map.mjs";
import { cameraLeftOut } from "./real-render-motion.mjs";
import { timeChecks } from "./real-render-time.mjs";

const HALF = 1;
const RATE = 24000;

let failed = 0;
const check = (name, ok, detail) => {
  if (!ok) failed++;
  console.log(`real-render ${name}: ${ok ? "pass" : "fail"}: ${detail}`);
};
const missing = catalogue()
  .filter((r) => ["npm", "chrome"].includes(r.kind))
  .filter((r) => !fs.existsSync(path.join(dest(r), ".stamp")));
if (missing.length || spawnSync("ffmpeg", ["-version"]).error) {
  console.error(
    `real-render: ${missing.map((r) => r.id).join(", ") || "ffmpeg"} not installed: run /explainer-video setup`,
  );
  process.exit(2);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), "real-render-"));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));
const backend = await loadBackend();
const env = hyperframesEnv();
// The renders run through a headless shell with raster flags (#917).
const renderEnv = {
  ...env,
  PRODUCER_HEADLESS_SHELL_PATH: shellWith(
    work,
    RASTER_FLAGS,
    headlessShell(env.HOME),
  ),
};
const profile = loadStyle(work, "claude-code");
const fontRows = [
  ...new Set(typeRoles("ar").map((r) => profile.type[r].font)),
].map((font) => fontRow(profile, font));
const gaps = fontRows.map(fontGap).filter(Boolean);
if (gaps.length) {
  console.error(`real-render: ${gaps.join(", ")}: run /explainer-video setup`);
  process.exit(2);
}

// A mono 16-bit tone of `seconds`, the narration stand-in.
const tone = (seconds) => {
  const pcm = Buffer.alloc(Math.round(seconds * RATE) * 2);
  for (let i = 0; i < pcm.length / 2; i++)
    pcm.writeInt16LE(
      Math.round(3000 * Math.sin((2 * Math.PI * 220 * i) / RATE)),
      i * 2,
    );
  const h = Buffer.alloc(44);
  h.write("RIFF", 0, "ascii");
  h.writeUInt32LE(36 + pcm.length, 4);
  h.write("WAVEfmt ", 8, "ascii");
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(RATE, 24);
  h.writeUInt32LE(RATE * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write("data", 36, "ascii");
  h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
};

// The composition for `part` of FIXTURE, the hold on its last scene if `hold`;
// returns its frames. The scenes go into `<work>/<name>/` as render.mjs does.
// `page(scenes)` adds to the video page's options: the sections checks' cues
// and their video-only parts.
async function compose(
  name,
  part,
  hold,
  { prof = profile, dir, page = () => ({}) } = {},
) {
  const run = path.join(work, name);
  const comp = path.join(run, "composition");
  fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
  const webgl = drawsWebgl(part.map((p) => p.scene));
  const fonts = compositionAssets(fontRows, comp, { webgl });
  const voice = {
    scenes: part.map((p) => {
      const audio = `${p.scene.id}.wav`;
      fs.writeFileSync(path.join(run, audio), tone(p.seconds));
      return { audio };
    }),
  };
  const grid = gridScenes(
    part.map((p) => p.seconds),
    hold ? HOLD : 0,
  );
  joinNarration({
    run,
    voice,
    frames: grid.map((g) => g.frames),
    file: path.join(comp, "narration.wav"),
    fail: (why) => {
      throw new Error(why);
    },
  });
  // The seams the style draws between the part's scenes: the hook to the
  // steps is a zoom-through, the steps to the merge a cut on a curve.
  const seams = seamPlan(
    part.map((p) => p.scene),
    prof,
  );
  const scenes = part.map((p, i) => ({
    id: p.scene.id,
    start: written(grid[i].start),
    duration: written(grid[i].frames),
    slot: slot(grid[i].frames, seams[i]),
  }));
  for (const [i, p] of part.entries())
    fs.writeFileSync(
      path.join(comp, "scenes", `${p.scene.id}.html`),
      await sceneFile(
        p.scene,
        // a sentence every 0.8 s from 0.2 and a word every 0.3 s, so each
        // cue has a time
        {
          ...scenes[i],
          sentences: p.scene.narration.map((_, k) => 0.2 + 0.8 * k),
          words: p.scene.narration
            .join(" ")
            .split(/\s+/)
            .map((_, k) => 0.2 + 0.3 * k),
        },
        prof,
        { backend, seam: seams[i], dir: p.dir },
      ),
    );
  fs.writeFileSync(
    path.join(comp, "index.html"),
    videoPage({
      title: "Real render fixture",
      profile: prof,
      fonts,
      scenes,
      cues: [],
      total: written(grid.total),
      webgl,
      ...page(scenes),
      dir,
    }),
  );
  return { comp, frames: grid.total, scenes };
}

// Renders a composition to `out`; true on a clean exit. Every render runs on
// SwiftShader (`--no-browser-gpu`): a host GPU's frames are not bit-stable, and
// the determinism checks compare renders.
const render = async (comp, out) =>
  (await backend.hyperframes(
    [
      ...["render", "--strict", "--quiet", "--no-browser-gpu"],
      ...["--fps", String(FPS)],
      ...["--workers", "3", "--quality", "looks", "-o", out],
    ],
    { cwd: comp, env: renderEnv },
  )) === 0;

// The video stream's frames as `framemd5` lists them, one line a frame.
const framemd5 = (file) =>
  spawnSync(
    "ffmpeg",
    ["-v", "error", "-i", file, "-map", "0:v", "-f", "framemd5", "-"],
    { encoding: "utf8", maxBuffer: 1 << 28 },
  )
    .stdout.split("\n")
    .filter((l) => l && !l.startsWith("#"));

const whole = await compose("whole", FIXTURE, true);
const first = await compose("first", FIXTURE.slice(0, HALF), false);
const second = await compose("second", FIXTURE.slice(HALF), true);
const videos = {};
for (const [name, c, n] of [
  ["whole-1", whole, "whole"],
  ["whole-2", whole, "whole"],
  ["whole-3", whole, "whole"],
  ["first", first, "first"],
  ["second", second, "second"],
]) {
  videos[name] = path.join(work, `${name}.mp4`);
  if (!(await render(c.comp, videos[name]))) {
    check("render", false, `${name} (${n}) did not render`);
    process.exit(1);
  }
}

const wholes = ["whole-1", "whole-2", "whole-3"];
const hashLists = wholes.map((n) => framemd5(videos[n]));
const [a, ...others] = hashLists;
check(
  "frame grid",
  a.length === whole.frames,
  `${a.length} frames rendered, the composer's grid is ${whole.frames}`,
);
const differs = differing(a, others);
// A failing row keeps the renders' hash lists in REAL_RENDER_FRAMES, else the
// temp folder.
const kept = differs.every(({ n }) => n === 0)
  ? ""
  : keepHashLists(
      Object.fromEntries(wholes.map((n, i) => [n, hashLists[i]])),
      process.env.REAL_RENDER_FRAMES ?? os.tmpdir(),
    ).join(", ");
check(
  "determinism",
  differs.every(({ n }) => n === 0),
  `${describe(differs)} differing frames of ${a.length} against the first, in two more renders${kept && `; hash lists: ${kept}`}`,
);

// Each seam window's first, middle and last frames, seeked twice in browsers
// of their own: the PNGs match byte for byte. The hook's zoom-through (out) and
// the steps' cut on a curve (out) each have an exit window and the scene after
// it an entry window, and the seams into the Arabic and the read-along scenes
// the same, and so does each scene after: an exit and an entry window for each
// of the fixture's scene changes.
const raw = await backend.events(whole.comp, { env });
// A frame of a WebGL scene is seeked on SwiftShader, as the gate does; every
// other scene's, as before.
const seek = async (t, n, software = false, comp = whole.comp) => {
  const png = path.join(work, `seam-${t}-${n}.png`);
  await backend.frame(comp, t, png, { env, software });
  return fs.readFileSync(png);
};
// Each window of `kind` (`seams` or `camera`) in video seconds: its first,
// middle and last frames seeked twice, and how many differ between the seeks
// (`apart`) or leave the window's three frames alike (`still`).
async function sweep(kind) {
  const windows = whole.scenes.flatMap((s) =>
    (raw[s.id]?.[kind] ?? []).map(([from, to]) =>
      [from, (from + to) / 2, to - 1 / FPS].map(
        (t) => +(s.start + t).toFixed(3),
      ),
    ),
  );
  let apart = 0;
  let still = 0;
  for (const w of windows) {
    const seen = new Set();
    for (const t of w) {
      const png = await seek(t, "a");
      if (!png.equals(await seek(t, "b"))) apart++;
      seen.add(png.toString("base64"));
    }
    // a window that draws nothing leaves its three frames alike
    if (seen.size < w.length) still++;
  }
  return { count: windows.length, apart, still };
}
const windows = (FIXTURE.length - 1) * 2;
const seams = await sweep("seams");
check(
  "seams",
  seams.count === windows && seams.apart === 0 && seams.still === 0,
  `${seams.apart} of ${seams.count * 3} seam frames differ between two seeks, ${seams.still} windows draw no motion, in ${seams.count} windows (${windows} expected)`,
);
// Every scene but the rich ones (`ownCamera`) composes a push-in under the
// default camera: one window each. A canvas scene's camera travels to each of
// its items after the first and then to the overview: one window per item.
const pushes = FIXTURE.filter(
  (p) => !VISUALS[p.scene.visual.component].ownCamera,
).length;
const tours = FIXTURE.map((p) => p.scene).filter(
  (s) => s.visual.component === "canvas",
);
const travels = tours.reduce((n, s) => n + s.visual.props.items.length, 0);
const push = await sweep("camera");
check(
  "camera",
  push.count === pushes + travels && push.apart === 0 && push.still === 0,
  `${push.apart} of ${push.count * 3} camera frames differ between two seeks, ${push.still} windows draw no motion, in ${push.count} windows (${pushes} push-ins and ${travels} canvas travels expected)`,
);

// A number counts up as a function of time: each stat scene's frame 0.45 s into
// the first count, seeked twice, matches byte for byte, differs from the frame
// once the count has settled, and the same frame at the same time is saved for
// a look (`REAL_RENDER_FRAMES=<dir>` keeps the settled and mid-count frames).
const counting = [];
for (const id of ["numbers", "arabic-stat", "bars", "arabic-line"]) {
  const start = whole.scenes.find((s) => s.id === id).start;
  const mid = +(start + 1.0 + 0.45).toFixed(3);
  const done = +(start + 3.0).toFixed(3);
  const a = await seek(mid, "count-a");
  const b = await seek(mid, "count-b");
  const settled = await seek(done, "count-done");
  counting.push([id, a.equals(b), !a.equals(settled)]);
  if (process.env.REAL_RENDER_FRAMES) {
    fs.mkdirSync(process.env.REAL_RENDER_FRAMES, { recursive: true });
    fs.writeFileSync(
      path.join(process.env.REAL_RENDER_FRAMES, `${id}.png`),
      settled,
    );
  }
}
check(
  "count-up",
  counting.every(([, same, moved]) => same && moved),
  counting
    .map(
      ([id, same, moved]) =>
        `${id}: ${same ? "equal" : "DIFFERENT"} on two seeks, ${moved ? "differs" : "SAME"} from settled`,
    )
    .join("; "),
);
// A packet's place is a function of time: each diagram scene's frame 2 s in,
// packets mid-run, seeked twice, matches byte for byte and differs from the
// frame 0.2 s later.
const diagrams = FIXTURE.map((p) => p.scene).filter(
  (s) => s.visual.component === "diagram",
);
const flowing = [];
for (const { id } of diagrams) {
  const start = whole.scenes.find((s) => s.id === id).start;
  const at = +(start + 2.0).toFixed(3);
  const a = await seek(at, "packets-a");
  const b = await seek(at, "packets-b");
  const later = await seek(+(at + 0.2).toFixed(3), "packets-later");
  flowing.push([id, a.equals(b), !a.equals(later)]);
}
check(
  "packets",
  flowing.every(([, same, moved]) => same && moved),
  flowing
    .map(
      ([id, same, moved]) =>
        `${id}: ${same ? "equal" : "DIFFERENT"} on two seeks, ${moved ? "moves" : "STILL"} 0.2 s later`,
    )
    .join("; "),
);

// A browser's cursor, an excerpt's lit sentence and a stack3d scene's WebGL
// canvas are each a function of time (checks `cursor`, `lit`, `webgl`).
const sceneOf = (component) =>
  FIXTURE.map((p) => p.scene).filter((s) => s.visual.component === component);
const browsers = sceneOf("browser");
const excerpts = sceneOf("excerpt");
const stacks = sceneOf("stack3d");
await timeChecks({ whole, seek, check, browsers, excerpts, stacks });

// The layout gate over the largest diagram's samples, each browser page's, each
// excerpt's (the longest one's reading is what the sizes were set for) and each
// stack3d scene's, as the gates stage takes them: its text inside the safe
// area, none clipped, small or stacked.
const largest = diagrams.toSorted(
  (a, b) => b.visual.props.nodes.length - a.visual.props.nodes.length,
)[0].id;
const { times: eventTimes, moving } = sceneEvents(raw, whole.scenes);
const laid = [];
const reads = [];
for (const id of [
  largest,
  ...browsers.map((s) => s.id),
  ...excerpts.map((s) => s.id),
  ...stacks.map((s) => s.id),
  ...tours.map((s) => s.id),
]) {
  const sc = whole.scenes.find((s) => s.id === id);
  const times = sampleTimes({ ...sc, fps: FPS, events: eventTimes });
  const findings = [];
  const frames = await backend.probe(whole.comp, times, { env });
  judge(
    await backend.check(whole.comp, times, { env }),
    frames,
    floors(profile),
    // a finding is the scene's while its time is, as the gates stage files it
    (gate, t, what) => {
      if (
        gate === "layout" &&
        t >= sc.start - 1e-6 &&
        t < sc.start + sc.duration - 1e-6
      )
        findings.push(`${t.toFixed(2)} s: ${what}`);
    },
    moving,
  );
  laid.push([id, times.length, [...new Set(findings)]]);
  // Each sentence of an excerpt is one reading box (`data-line`), judged on its
  // words as the gates stage judges a scene's text.
  if (excerpts.some((s) => s.id === id))
    reads.push([
      id,
      readingFindings(
        { sc, times, end: sc.start + sc.duration },
        frames,
        moving,
      ),
    ]);
}
check(
  "layout",
  laid.every(([, , found]) => found.length === 0),
  laid
    .map(
      ([id, n, found]) =>
        `${id}, ${n} samples: ${found.join("; ") || "no finding"}`,
    )
    .join(" | "),
);
check(
  "reading",
  excerpts.length > 0 && reads.every(([, found]) => !found.length),
  reads
    .map(([id, found]) => `${id}: ${found.join("; ") || "no finding"}`)
    .join(" | "),
);

// With REAL_RENDER_FRAMES set, save each timeline, compare, diagram, browser and
// excerpt scene's settled frame (3 s in) for a human to check the reading order;
// nothing asserts it.
if (process.env.REAL_RENDER_FRAMES)
  for (const id of [
    "timeline",
    "arabic-timeline",
    "arabic-compare",
    ...diagrams.map((s) => s.id),
    ...browsers.map((s) => s.id),
    ...excerpts.map((s) => s.id),
    ...stacks.map((s) => s.id),
    ...tours.map((s) => s.id),
  ]) {
    const start = whole.scenes.find((s) => s.id === id).start;
    fs.writeFileSync(
      path.join(process.env.REAL_RENDER_FRAMES, `${id}.png`),
      await seek(
        +(start + 3.0).toFixed(3),
        id,
        stacks.some((s) => s.id === id),
      ),
    );
  }

// What the critic reads of motion, off the real timeline and the real video:
// every scene's tweens, the push-in's or the tour's among them and exactly one
// per camera window left out of what a dead beat is read against (a card the
// canvas dims over the same window stays in), and the hook's seam strip, 6x2
// tiles of 320x180.
const { moves } = sceneEvents(raw, whole.scenes);
const pushed = whole.scenes.filter((s) => moves[s.id].camera.length);
const hook = whole.scenes[0];
const [exit] = moves.hook.seams.filter(
  ([a]) => a >= hook.start + hook.duration - 1e-3,
);
const stripPng = path.join(work, "hook.seam.png");
await backend.strip(videos["whole-1"], stripPng, {
  first: seamStripStart(exit, FPS),
  fps: FPS,
});
const stripBytes = fs.readFileSync(stripPng);
const size = [stripBytes.readUInt32BE(16), stripBytes.readUInt32BE(20)];
check(
  "critic motion",
  whole.scenes.every((s) => raw[s.id]?.tweens?.length) &&
    pushed.length === pushes + tours.length &&
    pushed.every((s) => cameraLeftOut(raw[s.id], moves[s.id])) &&
    size.join("x") === "1920x360",
  `${whole.scenes.filter((s) => raw[s.id]?.tweens?.length).length} of ${whole.scenes.length} scenes list their tweens, ${pushed.length} of ${pushes + tours.length} camera scenes left out of them, the hook's seam strip is ${size.join("x")} (1920x360 expected)`,
);

await mapChecks({
  FIXTURE,
  profile,
  work,
  compose,
  render,
  framemd5,
  seek,
  check,
});

const list = path.join(work, "halves.txt");
fs.writeFileSync(
  list,
  [videos.first, videos.second].map((f) => `file '${f}'`).join("\n"),
);
const joined = path.join(work, "joined.mp4");
const cat = spawnSync("ffmpeg", [
  ...["-v", "error", "-f", "concat", "-safe", "0", "-i", list],
  ...["-c", "copy", joined],
]);
const parts = cat.status === 0 ? framemd5(joined).length : -1;
check(
  "halves",
  parts === a.length,
  `${parts} frames joined, ${a.length} in the whole (${first.frames} + ${second.frames})`,
);

await sectionChecks({
  compose,
  render,
  framemd5,
  check,
  backend,
  work,
  env,
});

process.exit(failed ? 1 : 0);
