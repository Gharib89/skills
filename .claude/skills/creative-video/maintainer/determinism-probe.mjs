// Maintainer only: probe the determinism gate's flake (#1165). Takes a run
// folder that reached the gates, snapshots the gate's sample frames in `--launches`
// launches (the gate takes two) exactly as gates.mjs does (same times, same backend call, same
// pixel hash), and reports which frame differed, where it sits against its
// scene's cut, and how many pixels moved. Runs alternate idle and loaded
// (`--load` busy loops on every core) so the two conditions share the drift of
// the machine, and each run prints the load average it started under.
//
//   node maintainer/determinism-probe.mjs <run-folder> [--runs 5] [--load 12]
//        [--launches 2] [--out <dir>] [--times t1,t2,...]
//
// The run folder is copied into a temp folder first, so the probe never writes
// into it. `--times` replaces the gate's sample times (a second-level probe of
// one frame). Heavy: run it under a systemd memory cap, e.g.
//   systemd-run --user --scope -q -p MemoryMax=10G -p MemorySwapMax=0 node ...
// stdout: one `run <n> <idle|loaded> load=<1 min> ...` line per run (`same` or
//         the differing frames with scene, offset to its scene's end in
//         frames, differing pixels and their bounding box), then a summary per
//         condition. A differing frame names how the launches grouped (`aba`: the
//         third matched the first, the second differed). Every launch's frames of
//         a run with a difference are kept under `--out/run-<n>-<condition>/<a|b|..>/`.
// exit:   0 the probe ran (a flake is a finding, not a failure) · 1 a stage or
//         tool failed · 2 usage
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { readTimeline } from "../scripts/lib/runfolder.mjs";
import { stage } from "../scripts/lib/stage.mjs";
import { hyperframesEnv, loadBackend } from "../scripts/lib/tools.mjs";
import { FPS } from "../scripts/render/grid.mjs";
import { sampleTimes } from "../scripts/gates/samples.mjs";
import { HEIGHT, WIDTH } from "../scripts/render/root.mjs";

stage("determinism-probe");
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i < 0 ? fallback : argv[i + 1];
};
const src = argv.find(
  (a, i) => !a.startsWith("--") && !argv[i - 1]?.startsWith("--"),
);
if (!src) {
  console.error(
    "usage: determinism-probe.mjs <run-folder> [--runs N] [--load K] [--out dir] [--times t,t]",
  );
  process.exit(2);
}
// A count flag is a whole number of at least `min`; anything else is usage.
const count = (name, fallback, min) => {
  const n = Number(flag(name, fallback));
  if (!Number.isInteger(n) || n < min) {
    console.error(
      `determinism-probe: --${name} wants a whole number >= ${min}`,
    );
    process.exit(2);
  }
  return n;
};
const runs = count("runs", 5, 1);
const launches = count("launches", 2, 2);
const load = count("load", os.cpus().length, 0);
const outRoot = path.resolve(
  flag("out", fs.mkdtempSync(path.join(os.tmpdir(), "determinism-probe-"))),
);

const work = fs.mkdtempSync(path.join(os.tmpdir(), "determinism-copy-"));
process.on("exit", () => fs.rmSync(work, { recursive: true, force: true }));
fs.cpSync(src, work, {
  recursive: true,
  filter: (f) =>
    !/[\\/]\.cache([\\/]|$)/.test(f) && !/[\\/]out([\\/]|$)/.test(f),
});

const { timeline } = readTimeline(work, (m) => {
  throw new Error(m);
});
const uniq = (ts) => [...new Set(ts)].sort((a, b) => a - b);
const sampled = flag("times")
  ? flag("times")
      .split(",")
      .map((t) => {
        if (!t.trim() || !Number.isFinite(Number(t))) {
          console.error(`determinism-probe: --times wants seconds, got "${t}"`);
          process.exit(2);
        }
        return Number(t);
      })
  : uniq(timeline.scenes.flatMap((sc) => Object.values(sampleTimes(sc))));
const sceneAt = (t) =>
  timeline.scenes.find(
    (s) => t >= s.start - 1e-6 && t < s.start + s.duration,
  ) ?? timeline.scenes.at(-1);

const backend = await loadBackend();
const env = hyperframesEnv();
const proj = path.join(work, "project");

// One launch's frames: `[time, pixel hash, file]` per sample, as the gate takes.
const launch = async (dir) =>
  Promise.all(
    (await backend.snapshot(proj, sampled, dir, { env })).map(async (f) => [
      f.time,
      await backend.framePixels(f.path),
      f.path,
    ]),
  );

// RGB bytes of a PNG, for counting the pixels that moved.
const rgb = (file) => {
  const r = spawnSync(
    "ffmpeg",
    ["-v", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
    { maxBuffer: 1 << 28 },
  );
  if (r.status !== 0)
    throw new Error(
      `ffmpeg could not decode ${file}: ${r.error?.message ?? r.stderr}`,
    );
  return r.stdout;
};
function moved(fa, fb) {
  const [x, y] = [rgb(fa), rgb(fb)];
  let n = 0;
  let max = 0;
  const box = [WIDTH, HEIGHT, -1, -1];
  for (let i = 0; i < x.length; i += 3) {
    const d = Math.max(
      Math.abs(x[i] - y[i]),
      Math.abs(x[i + 1] - y[i + 1]),
      Math.abs(x[i + 2] - y[i + 2]),
    );
    if (!d) continue;
    n++;
    max = Math.max(max, d);
    const p = i / 3;
    const [px, py] = [p % WIDTH, Math.floor(p / WIDTH)];
    box[0] = Math.min(box[0], px);
    box[1] = Math.min(box[1], py);
    box[2] = Math.max(box[2], px);
    box[3] = Math.max(box[3], py);
  }
  return `${n} px, max channel delta ${max}, box ${box.join(",")}`;
}

const spin = () =>
  Array.from({ length: load }, () =>
    spawn(process.execPath, ["-e", "for(;;);"], { stdio: "ignore" }),
  );

const tally = { idle: [], loaded: [] };
for (let n = 1; n <= runs * 2; n++) {
  const cond = n % 2 ? "idle" : "loaded";
  const burners = cond === "loaded" ? spin() : [];
  const dir = path.join(outRoot, `run-${n}-${cond}`);
  const t0 = Date.now();
  const l1 = os.loadavg()[0].toFixed(1);
  const ls = [];
  try {
    for (let k = 0; k < launches; k++)
      ls.push(await launch(path.join(dir, String.fromCharCode(97 + k))));
  } finally {
    for (const p of burners) p.kill("SIGKILL");
  }
  const diffs = ls[0].flatMap(([t, h], i) => {
    if (ls.every((l) => l[i][1] === h)) return [];
    const sc = sceneAt(t);
    const toEnd = Math.round((sc.start + sc.duration - t) * FPS * 100) / 100;
    const odd = ls.findIndex((l) => l[i][1] !== h);
    const groups = ls
      .map((l) =>
        String.fromCharCode(97 + ls.findIndex((m) => m[i][1] === l[i][1])),
      )
      .join("");
    return [
      `${t.toFixed(3)} s ${sc.id} (${toEnd} frames before its end, ${((t - sc.start) * FPS).toFixed(1)} after its start), launches grouped ${groups}: ${moved(ls[0][i][2], ls[odd][i][2])}`,
    ];
  });
  tally[cond].push(diffs.length);
  console.log(
    `run ${n} ${cond} load=${l1} ${((Date.now() - t0) / 1000).toFixed(0)}s ${sampled.length} frames: ${diffs.length ? `${diffs.length} differ\n  ${diffs.join("\n  ")}` : "same"}`,
  );
  if (!diffs.length) fs.rmSync(dir, { recursive: true, force: true });
}
for (const [cond, counts] of Object.entries(tally)) {
  const s = [...counts].sort((x, y) => x - y);
  console.log(
    `${cond}: ${counts.filter(Boolean).length} of ${counts.length} runs flaked, differing frames per run median ${s[Math.floor(s.length / 2)]}, range ${s[0]}..${s.at(-1)}`,
  );
}
