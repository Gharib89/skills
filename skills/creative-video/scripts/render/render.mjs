// The render stage: the authored HyperFrames project to a mastered MP4, SRT and
// poster.
//
//   node render.mjs <run-folder> [--estimate]
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
// A timeline with `chapters` renders in chapters instead (render/chapter-
// project.mjs): each chapter, one at a time, from its own folder
// <run>/.cache/render/chapter-<n>/ to the chapter render
// chapter-<n>-<key>.mp4, <key> the hash of everything that folder loads, so a
// chapter unchanged since it was rendered is not rendered again and a changed
// one's stale render is removed. The whole project is rendered once more at
// 1 fps, draft quality (its audio is the 30 fps render's, bit for bit, measured
// on HyperFrames
// 0.8.206) to audio.mp4, its audio mastered to the targets above into audio.wav
// the length of the timeline, and the chapter renders and that mix join into
// out/<slug>.mp4 with a chapter mark each (render/chapters.mjs). The checks add
// `chapters`. Before any chapter renders it prints its estimate from
// render-rates.json; `--estimate` prints that line and exits 0, rendering
// nothing, touching nothing in out/ and not asking for passed gates.
// stdout: in chapters, first `render: <k> of <n> chapter(s) to render, estimate
//         <m:ss>, budget <m:ss>`; then one `delivery <check>: pass|fail:
//         <measured> vs <wanted>` line per
//         check, `measured loudness: <lufs> LUFS integrated, <peak> dBTP
//         true peak`, `delivered: <path>`, then `render: <slug>.mp4 <seconds> s,
//         <n> scene(s)`
// writes: <run>/.cache/render/raw.mp4 (chapter-<n>/, chapter-<n>-<key>.mp4,
//         audio.mp4, audio.wav in chapters), out/<slug>.mp4|.srt, out/poster.png,
//         manifest.json
// exit:   0 delivered · 1 refused or failed, `render: <why>` on stderr, or a
//         delivery check failed · 2 usage
import fs from "node:fs";
import path from "node:path";
import { captionFindings, cuesOf } from "../gates/captions.mjs";
import { inputsHash } from "../gates/inputs.mjs";
import { estimate, loadRates } from "../lib/estimate.mjs";
import { maybeJson } from "../lib/json.mjs";
import { mmss } from "../lib/length.mjs";
import { readTimeline, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend, lockHash } from "../lib/tools.mjs";
import { writeChapter } from "./chapter-project.mjs";
import { chapterCheck, joinChapters } from "./chapters.mjs";
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
const args = process.argv.slice(2);
const estimateOnly = args.includes("--estimate");
const [run, ...rest] = args.filter((a) => a !== "--estimate");
if (!run || rest.length) {
  console.error("usage: node render.mjs <run-folder> [--estimate]");
  process.exit(2);
}
function fail(why) {
  console.error(`render: ${why}`);
  process.exit(1);
}
const slug = path.basename(path.resolve(run));
const project = path.join(path.resolve(run), "project");
const cache = path.resolve(run, ".cache", "render");
const { timeline, voice } = readTimeline(run, fail);
writeIgnore(run);
const chapters = timeline.chapters;
if (estimateOnly && !chapters)
  fail("--estimate is for a video in chapters: this timeline has none");

// A video in chapters: each chapter's folder written and its render's path,
// the render cached when it is there, and the estimate line printed, whose
// rendered seconds are the chapters not cached.
function chapterParts() {
  fs.mkdirSync(cache, { recursive: true });
  const parts = chapters.map(({ n }) => {
    const { dir, key, seconds } = writeChapter(run, { timeline, voice }, n);
    const part = path.join(cache, `chapter-${n}-${key}.mp4`);
    return { n, dir, seconds, part, cached: fs.existsSync(part) };
  });
  let rates;
  try {
    rates = loadRates().rates;
  } catch (e) {
    fail(e.message);
  }
  const todo = parts.filter((p) => !p.cached);
  const { seconds, budget } = estimate(
    todo.reduce((n, p) => n + p.seconds, 0),
    timeline.total,
    rates,
  );
  console.log(
    `render: ${todo.length} of ${parts.length} chapter(s) to render, estimate ${mmss(seconds)}, budget ${mmss(budget)}`,
  );
  return parts;
}
if (estimateOnly) {
  chapterParts();
  process.exit(0);
}
writeRoot(run);
// The gates stage's record must be of this very project and have passed.
const record = maybeJson(run, "gates.json");
if (
  record?.inputs !== inputsHash(run) ||
  Object.values(record.gates).some((g) => g.status !== "pass")
)
  fail("the gates have not passed on this project: run gates/gates.mjs");

const backend = await loadBackend();
const env = hyperframesEnv();
const parts = chapters && chapterParts();
const out = path.join(run, "out");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out);
const raw = path.join(cache, "raw.mp4");
fs.mkdirSync(cache, { recursive: true });
// HyperFrames in `cwd` to `file`: video at `fps`, `more` its further flags.
async function renderTo(cwd, file, fps, more = [], what = "") {
  const code = await backend.hyperframes(
    [
      ...["render", "--strict", "--quiet", "--fps", String(fps), ...more],
      ...["--workers", "3", "-o", file],
    ],
    { cwd, env },
  );
  if (code !== 0) fail(`hyperframes render exited ${code}${what}`);
}
const audio = path.join(cache, "audio.mp4");
const wav = path.join(cache, "audio.wav");
const marks = chapters?.map(({ start, end, title }) => ({
  start,
  end,
  title,
}));
if (parts) {
  // A chapter render is of exactly the folder its key hashes: another key's,
  // and a half-written one a failed render left, are stale.
  const current = new Set(parts.map((p) => path.basename(p.part)));
  for (const f of fs.readdirSync(cache))
    if (/^chapter-\d+-[0-9a-f]{16}(\.part)?\.mp4$/.test(f) && !current.has(f))
      fs.rmSync(path.join(cache, f));
  // One at a time: each render takes every worker and the browser's memory.
  for (const p of parts.filter((p) => !p.cached)) {
    const half = p.part.replace(/\.mp4$/, ".part.mp4");
    await renderTo(p.dir, half, FPS, [], ` on chapter ${p.n}`);
    fs.renameSync(half, p.part);
  }
  await renderTo(
    project,
    audio,
    1,
    ["--quality", "draft"],
    " on the audio pass",
  );
} else await renderTo(project, raw, FPS);

const mp4 = path.join(out, `${slug}.mp4`);
const srt = path.join(out, `${slug}.srt`);
const first = timeline.scenes[0];
let probe;
let loud;
try {
  if (parts) {
    await backend.masterAudio(audio, wav, {
      lufs: LUFS,
      peak: PEAK,
      seconds: timeline.total,
    });
    await joinChapters(backend, {
      parts: parts.map((p) => p.part),
      joined: path.join(cache, "joined.mp4"),
      audio: wav,
      chapters: marks,
      output: mp4,
    });
  } else await backend.loudnorm(raw, mp4, { lufs: LUFS, peak: PEAK });
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
const captionIssues = captionFindings({
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
    captionIssues.length
      ? `${captionIssues.length} finding(s), first: ${captionIssues[0]}`
      : "none",
    "none",
  ],
  ...(marks ? [chapterCheck(marks, probe.chapters)] : []),
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
