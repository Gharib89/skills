// The render stage: the authored HyperFrames project to a mastered MP4, SRT and
// poster.
//
//   node render.mjs <run-folder>
//
// Reads <run>/timeline.json and <run>/project/ (render/timing.mjs wrote both,
// and the agent has authored a compositions/<id>.html per scene), and writes
// the root again (render/root.mjs) so it names the project as it stands. It
// refuses unless <run>/gates.json (gates/gates.mjs) passed for this very
// project, and a refusal leaves out/ as it was. Renders the
// project with HyperFrames to <run>/.cache/render/raw.mp4, normalises its
// audio to -14 LUFS with a true peak of -1.5 dBTP into out/<slug>.mp4, writes
// out/<slug>.srt from the timeline's cues and out/poster.png from the middle of
// the first scene, and checks the MP4 against the delivery contract. A failed
// check empties out/ and delivers nothing.
// stdout: one `delivery <check>: pass|fail: <measured> vs <wanted>` line per
//         check, `measured loudness: <lufs> LUFS integrated, <peak> dBTP
//         true peak`, `delivered: <path>`, then `render: <slug>.mp4 <seconds> s,
//         <n> scene(s)`
// writes: <run>/.cache/render/raw.mp4, out/<slug>.mp4|.srt, out/poster.png,
//         manifest.json
// exit:   0 delivered · 1 refused or failed, `render: <why>` on stderr, or a
//         delivery check failed · 2 usage
import fs from "node:fs";
import path from "node:path";
import { captionFindings, cuesOf } from "../gates/captions.mjs";
import { inputsHash } from "../gates/inputs.mjs";
import { readTimeline, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend, lockHash } from "../lib/tools.mjs";
import { videoFacts, srtText, writeManifest } from "./delivery.mjs";
import { FPS } from "./grid.mjs";
import { HEIGHT, WIDTH, writeRoot } from "./root.mjs";

// The mastering targets: the loudness gate's integrated level, held within
// 1 LU, and a true peak half a dB under its -1.0 dBTP ceiling.
const LUFS = -14;
const LU_WINDOW = 1;
const PEAK = -1.5;
const CEILING = -1.0;

stage("render");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node render.mjs <run-folder>");
  process.exit(2);
}
function fail(why) {
  console.error(`render: ${why}`);
  process.exit(1);
}
const slug = path.basename(path.resolve(run));
const project = path.join(path.resolve(run), "project");
const { timeline, voice } = readTimeline(run, fail);
writeIgnore(run);
writeRoot(run);
// The gates stage's record must be of this very project and have passed.
const record = fs.existsSync(path.join(run, "gates.json"))
  ? JSON.parse(fs.readFileSync(path.join(run, "gates.json"), "utf8"))
  : null;
if (
  record?.inputs !== inputsHash(run) ||
  Object.values(record.gates).some((g) => g.status !== "pass")
)
  fail("the gates have not passed on this project: run gates/gates.mjs");

const backend = await loadBackend();
const out = path.join(run, "out");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out);
const raw = path.resolve(run, ".cache", "render", "raw.mp4");
fs.mkdirSync(path.dirname(raw), { recursive: true });
const code = await backend.hyperframes(
  [
    ...["render", "--strict", "--quiet", "--fps", String(FPS)],
    ...["--workers", "3", "-o", raw],
  ],
  { cwd: project, env: hyperframesEnv() },
);
if (code !== 0) fail(`hyperframes render exited ${code}`);

const mp4 = path.join(out, `${slug}.mp4`);
const srt = path.join(out, `${slug}.srt`);
const first = timeline.scenes[0];
let probe;
let loud;
try {
  await backend.loudnorm(raw, mp4, { lufs: LUFS, peak: PEAK });
  fs.writeFileSync(srt, srtText(timeline.cues));
  await backend.poster(
    mp4,
    +(first.start + first.duration / 2).toFixed(3),
    path.join(out, "poster.png"),
  );
  probe = await backend.ffprobe(mp4);
  loud = await backend.loudness(mp4);
} catch (e) {
  fs.rmSync(out, { recursive: true, force: true });
  fail(e.message);
}

// Delivery checks, every one printed before any verdict.
const { size, fps, ratio } = videoFacts(probe);
const seconds = +probe.format.duration;
// The captions the video draws (the composition's cues) against the timeline's
// words and the SRT delivered beside it.
const caps = captionFindings({
  timeline,
  cues: cuesOf(
    fs.readFileSync(
      path.join(project, "compositions", "captions.html"),
      "utf8",
    ),
  ),
  srtText: fs.readFileSync(srt, "utf8"),
});
const checks = [
  ["resolution", size, `${WIDTH}x${HEIGHT}`],
  ["frame rate", fps, FPS],
  ["aspect", ratio, "16:9"],
  [
    "duration",
    `${seconds.toFixed(2)} s`,
    `${timeline.total.toFixed(2)} s within 0.25 s`,
    Math.abs(seconds - timeline.total) <= 0.25,
  ],
  [
    "audio",
    probe.streams.some((s) => s.codec_type === "audio") ? "a stream" : "none",
    "a stream",
  ],
  [
    "captions",
    caps.length ? `${caps.length} finding(s), first: ${caps[0]}` : "none",
    "none",
  ],
  [
    "loudness",
    `${loud.lufs} LUFS`,
    `${LUFS} LUFS within ${LU_WINDOW} LU`,
    Math.abs(loud.lufs - LUFS) <= LU_WINDOW,
  ],
  [
    "true peak",
    `${loud.peak} dBTP`,
    `at most ${CEILING} dBTP`,
    loud.peak <= CEILING,
  ],
];
let failed = 0;
for (const [name, got, want, ok = got === want] of checks) {
  if (!ok) failed++;
  console.log(`delivery ${name}: ${ok ? "pass" : `fail: ${got} vs ${want}`}`);
}
console.log(
  `measured loudness: ${loud.lufs} LUFS integrated, ${loud.peak} dBTP true peak`,
);
if (failed) {
  fs.rmSync(out, { recursive: true, force: true });
  process.exit(1);
}

writeManifest(run, {
  lock: lockHash,
  narrator: voice.narrator,
  lufs: LUFS,
  peak: PEAK,
});
console.log(`delivered: ${mp4}`);
console.log(
  `render: ${slug}.mp4 ${seconds.toFixed(2)} s, ${timeline.scenes.length} scene(s)`,
);
