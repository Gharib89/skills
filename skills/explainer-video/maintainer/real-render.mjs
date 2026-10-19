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
// slice adds its own scenes to it. The whole is rendered twice, and the halves
// split it after `HALF` scenes: the first without the hold, the second with it.
// stdout: `real-render <check>: pass|fail: <detail>` per check
// exit:   0 every check passed · 1 a check failed · 2 a tool row is missing
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { HOLD } from "../scripts/lib/length.mjs";
import { loadStyle, typeRoles } from "../scripts/lib/style.mjs";
import {
  catalogue,
  compositionAssets,
  dest,
  fontRow,
  hyperframesEnv,
  loadBackend,
  skill,
} from "../scripts/lib/tools.mjs";
import { FPS, sceneFile, videoPage } from "../scripts/render/compose.mjs";
import { gridScenes, written } from "../scripts/render/grid.mjs";
import { joinNarration } from "../scripts/render/narration.mjs";

// Scene ids and component visuals as the compile stage writes them, each with
// its narration's seconds: not whole frames, so the padding is exercised.
const FIXTURE = [
  {
    scene: {
      id: "hook",
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
      title: "The steps",
      narration: ["It reads the issue.", "Then it ships."],
      visual: {
        component: "cards",
        props: {
          items: [
            { at: 1, label: "Input", value: "issue" },
            { at: 2, label: "Then", value: "pull request" },
          ],
        },
      },
    },
    seconds: 1.91,
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
  ...new Set(typeRoles("en").map((r) => profile.type[r].font)),
].map((font) => fontRow(profile, font));

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
  const scenes = part.map((p, i) => ({
    id: p.scene.id,
    start: written(grid[i].start),
    duration: written(grid[i].frames),
  }));
  for (const [i, p] of part.entries())
    fs.writeFileSync(
      path.join(comp, "scenes", `${p.scene.id}.html`),
      await sceneFile(
        p.scene,
        { duration: scenes[i].duration, sentences: [0.2] },
        profile,
        { backend },
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
  return { comp, frames: grid.total };
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
  ["first", first, "first"],
  ["second", second, "second"],
]) {
  videos[name] = path.join(work, `${name}.mp4`);
  if (!(await render(c.comp, videos[name]))) {
    check("render", false, `${name} (${n}) did not render`);
    process.exit(1);
  }
}

const [a, b] = [framemd5(videos["whole-1"]), framemd5(videos["whole-2"])];
check(
  "frame grid",
  a.length === whole.frames,
  `${a.length} frames rendered, the composer's grid is ${whole.frames}`,
);
const differing =
  a.filter((l, i) => l !== b[i]).length + Math.abs(a.length - b.length);
check(
  "determinism",
  differing === 0,
  `${differing} differing frames of ${a.length}`,
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
