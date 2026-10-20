// Maintainer only: render a short fixture with real HyperFrames and prove what
// the fake backend cannot: the frame grid holds (the render has exactly the
// composer's frames), a render is deterministic, and two halves joined by
// stream copy have the whole's frame count.
//
//   node maintainer/real-render.mjs
//
// Needs the render rows installed (`node scripts/setup.mjs install`) and
// ffmpeg. The fixture is FIXTURE below, composed as render/render.mjs composes
// a run (the scenes on the frame grid, each scene's WAV padded to its frames,
// the last held HOLD seconds) with a synthetic tone for the narration; a later
// slice adds its own scenes to it. Its roles give both velocity seams: a
// zoom-through at the beat change out of the hook, a cut on a curve inside the
// point beat. The whole is rendered three times, the
// style's texture included (a second and a third render catch noise that
// drifts between runs, which two renders can match by chance), and the halves
// split it after `HALF` scenes: the
// first without the hold, the second with it.
// stdout: `real-render <check>: pass|fail: <detail>` per check
// exit:   0 every check passed · 1 a check failed · 2 a tool row is missing
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { sceneEvents } from "../scripts/gates/events.mjs";
import { HOLD } from "../scripts/lib/length.mjs";
import { seamStripStart } from "../scripts/lib/motion.mjs";
import { loadStyle, typeRoles } from "../scripts/lib/style.mjs";
import { VISUALS } from "../scripts/lib/visuals.mjs";
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

// Scene ids and component visuals as the compile stage writes them, each with
// its narration's seconds: not whole frames, so the padding is exercised.
const FIXTURE = [
  {
    scene: {
      id: "hook",
      role: "hook",
      title: "The promise",
      narration: ["One run, one merge."],
      visual: {
        component: "title",
        props: { kicker: "Ship", title: "Issue to pull request" },
      },
    },
    seconds: 2.37,
  },
  {
    scene: {
      id: "steps",
      role: "point",
      title: "The steps",
      narration: ["It reads the issue.", "Then it ships."],
      visual: {
        component: "cards",
        props: {
          items: [
            { at: 1, label: "Input", value: "issue" },
            { at: 2, label: "Then", value: "pull request" },
          ],
          emphasis: { target: "Input", at: 1 },
        },
      },
    },
    seconds: 1.91,
  },
  {
    scene: {
      id: "merge",
      role: "point",
      title: "The merge",
      narration: ["Then it merges."],
      visual: {
        component: "title",
        props: { kicker: "Ship", title: "Merged" },
      },
    },
    seconds: 1.43,
  },
  // Right to left: the type family `words` rises it by whole words, an English
  // term one unit, and the determinism check holds its frames.
  {
    dir: "rtl",
    scene: {
      id: "arabic",
      role: "point",
      title: "العربي",
      narration: ["بعد كده بيعمل merge."],
      visual: {
        component: "title",
        props: { title: "من issue لحد pull request", subtitle: "تشغيل واحد" },
      },
    },
    seconds: 1.67,
  },
  // Kinetic type read along: each word rises on its own spoken word, and the
  // rich component draws no push-in of the composer's.
  {
    scene: {
      id: "along",
      role: "point",
      title: "Read along",
      narration: ["Read the issue, ship it, merge it."],
      visual: {
        component: "words",
        props: {
          lines: [
            { at: 1, on: "Read the issue", text: "Read the issue" },
            { at: 1, on: "ship it", text: "ship it" },
          ],
        },
      },
    },
    seconds: 2.6,
  },
  // Numbers that count up: bars and stats, then the same right to left (a line
  // chart and a stat). Each number cues on a sentence after the scene's entry
  // seam, so a frame during the count is outside any seam.
  {
    scene: {
      id: "bars",
      role: "point",
      title: "Bars",
      narration: ["Latency was 900.", "Then it fell to 240.", "Quite a drop."],
      visual: {
        component: "chart",
        props: {
          kind: "bar",
          unit: "ms",
          items: [
            { at: 2, label: "Before", value: "900" },
            { at: 3, label: "After", value: "240" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    scene: {
      id: "numbers",
      role: "point",
      title: "Numbers",
      narration: ["Two numbers.", "It holds 1,200 requests.", "In 40 ms."],
      visual: {
        component: "stat",
        props: {
          items: [
            { at: 2, value: "1,200", label: "requests a second" },
            { at: 3, value: "40", label: "milliseconds" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-line",
      role: "point",
      title: "خط",
      narration: ["الأرقام بتنزل.", "كانت 900.", "بقت 240."],
      visual: {
        component: "chart",
        props: {
          kind: "line",
          items: [
            { at: 2, label: "قبل", value: "900" },
            { at: 3, label: "بعد", value: "240" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
  {
    dir: "rtl",
    scene: {
      id: "arabic-stat",
      role: "point",
      title: "أرقام",
      narration: ["رقمين.", "فيه 1,200 طلب.", "في 40 ثانية."],
      visual: {
        component: "stat",
        props: {
          items: [
            { at: 2, value: "1,200", label: "طلب" },
            { at: 3, value: "40", label: "ثانية" },
          ],
        },
      },
    },
    seconds: 3.4,
  },
];
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
async function compose(name, part, hold) {
  const run = path.join(work, name);
  const comp = path.join(run, "composition");
  fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
  const fonts = compositionAssets(fontRows, comp);
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
    profile,
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
        profile,
        { backend, seam: seams[i], dir: p.dir },
      ),
    );
  fs.writeFileSync(
    path.join(comp, "index.html"),
    videoPage({
      title: "Real render fixture",
      profile,
      fonts,
      scenes,
      cues: [],
      total: written(grid.total),
    }),
  );
  return { comp, frames: grid.total, scenes };
}

// Renders a composition to `out`; true on a clean exit.
const render = async (comp, out) =>
  (await backend.hyperframes(
    [
      ...["render", "--strict", "--quiet", "--fps", String(FPS)],
      ...["--workers", "3", "--quality", "looks", "-o", out],
    ],
    { cwd: comp, env },
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

const [a, ...others] = ["whole-1", "whole-2", "whole-3"].map((n) =>
  framemd5(videos[n]),
);
check(
  "frame grid",
  a.length === whole.frames,
  `${a.length} frames rendered, the composer's grid is ${whole.frames}`,
);
const differing = others.map(
  (b) => a.filter((l, i) => l !== b[i]).length + Math.abs(a.length - b.length),
);
check(
  "determinism",
  differing.every((n) => n === 0),
  `${differing.join(" and ")} differing frames of ${a.length} against the first, in two more renders`,
);

// Each seam window's first, middle and last frames, seeked twice in browsers
// of their own: the PNGs match byte for byte. The hook's zoom-through (out) and
// the steps' cut on a curve (out) each have an exit window and the scene after
// it an entry window, and the seams into the Arabic and the read-along scenes
// the same, and so does each scene after: an exit and an entry window for each
// of the fixture's scene changes.
const raw = await backend.events(whole.comp, { env });
const seek = async (t, n) => {
  const png = path.join(work, `seam-${t}-${n}.png`);
  await backend.frame(whole.comp, t, png, { env });
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
// default camera: one window each.
const pushes = FIXTURE.filter(
  (p) => !VISUALS[p.scene.visual.component].ownCamera,
).length;
const push = await sweep("camera");
check(
  "camera",
  push.count === pushes && push.apart === 0 && push.still === 0,
  `${push.apart} of ${push.count * 3} push-in frames differ between two seeks, ${push.still} windows draw no motion, in ${push.count} windows (${pushes} expected)`,
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

// What the critic reads of motion, off the real timeline and the real video:
// every scene's tweens, the push-in's among them and left out of the windows a
// dead beat is read against, and the hook's seam strip, 6x2 tiles of 320x180.
const { moves } = sceneEvents(raw, whole.scenes);
const same = ([a, b], [x, y]) =>
  Math.abs(a - x) < 1e-3 && Math.abs(b - y) < 1e-3;
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
    pushed.length === pushes &&
    pushed.every(
      (s) =>
        raw[s.id].camera.every((c) =>
          raw[s.id].tweens.some((t) => same(t, c)),
        ) &&
        !moves[s.id].tweens.some((t) =>
          moves[s.id].camera.some((c) => same(t, c)),
        ),
    ) &&
    size.join("x") === "1920x360",
  `${whole.scenes.filter((s) => raw[s.id]?.tweens?.length).length} of ${whole.scenes.length} scenes list their tweens, ${pushed.length} of ${pushes} push-ins left out of them, the hook's seam strip is ${size.join("x")} (1920x360 expected)`,
);

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

process.exit(failed ? 1 : 0);
