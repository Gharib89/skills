// The render stage: the voiced script to a captioned MP4, SRT and poster.
//
//   node render.mjs <run-folder> [--stills]
//
// Reads <run>/script.json and <run>/voice.json and the run's style profile
// (lib/style.mjs). Times every scene back to back on the frame grid (render/grid.mjs)
// from its voice duration, the last held 1 s, cues captions from the word
// timings, composes the video in <run>/composition/ with the narration mastered (the score from
// score/score.mjs mixed under it, unless brief.json turns it off), renders a
// still per scene (its fullest moment) and then the video with HyperFrames, each cached in
// <run>/.cache/ by content hash, runs the gates stage (gates/gates.mjs) on
// out/, checks the MP4 with ffprobe, and copies MP4, SRT and poster to the
// videos folder. A red gate or a failed check empties out/ and delivers
// nothing. With `--stills` it stops after the stills: no video, gates,
// delivery or manifest, for the storyboard.
// stdout: the gates stage's lines, one `delivery <check>: pass|fail:
//         <measured> vs <wanted>` line per check, `delivered: <path>`, then
//         `render: <slug>.mp4 <seconds> s, <n> scene(s), stills <hit>/<n>
//         cached, video cached|rendered` (`video <hit>/<n> sections cached`
//         for a video in sections, joined with chapter marks: sections.mjs)
// writes: <run>/style.json, stills.json, timeline.json, score.json,
//         composition/, .cache/stills/, .cache/score/, .cache/render/,
//         out/<slug>.mp4|.srt, out/poster.png, manifest.json,
//         and the gates stage's files; <videos>/explainer-video/<repo>/<slug>/;
//         explainers/.gitignore
//         `--stills`: `render: stills <hit>/<n> cached`, writing only
//         <run>/stills.json (every scene's still, relative to the run), the
//         timeline, composition/ and .cache/stills/
// exit:   0 delivered · 1 refused or failed, `render: <why>` on stderr, a gate
//         red, or a delivery check failed · 2 usage
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { checkScenes } from "../lib/allowed.mjs";
import { HOLD } from "../lib/length.mjs";
import { videosDir } from "../lib/paths.mjs";
import { drawsWebgl } from "../lib/visuals.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { LUFS, floors, loadStyle, typeRoles } from "../lib/style.mjs";
import { writeWav } from "../score/dsp.mjs";
import { ACE_CAPTION, bedLevel, score } from "../score/score.mjs";
import {
  catalogue,
  compositionAssets,
  dest,
  fontGap,
  fontRow,
  gpuRefusal,
  hyperframesEnv,
  loadBackend,
  lockHash,
  renderInputs,
  skill,
  torchDevice,
} from "../lib/tools.mjs";
import { FPS, H, W, sceneFile, stillsPage, videoPage } from "./compose.mjs";
import { captionCues } from "./cues.mjs";
import { gridScenes, written } from "./grid.mjs";
import { joinNarration, wavSeconds } from "./narration.mjs";
import { deliver, srtText, videoFacts, writeManifest } from "./delivery.mjs";
import { seamPlan, slot } from "./seams.mjs";
import {
  chapterCheck,
  chaptersOf,
  joinSections,
  sectionsOf,
  writeSection,
} from "./sections.mjs";

const [run, ...rest] = process.argv.slice(2);
const stillsOnly = rest[0] === "--stills";
if (!run || rest.length > (stillsOnly ? 1 : 0)) {
  console.error("usage: node render.mjs <run-folder> [--stills]");
  process.exit(2);
}
function fail(why) {
  console.error(`render: ${why}`);
  process.exit(1);
}
const slug = path.basename(path.resolve(run));
const r3 = (n) => +n.toFixed(3);
const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts)
    h.update(typeof p === "string" ? p : JSON.stringify(p));
  return h.digest("hex").slice(0, 16);
};
const json = (f) => JSON.parse(fs.readFileSync(f, "utf8"));
if (!fs.existsSync(path.join(run, "script.json")))
  fail("no script.json: run the compile stage first (script/compile.mjs)");
const script = json(path.join(run, "script.json"));
writeIgnore(run);

let profile;
try {
  profile = loadStyle(run, script.style);
  checkScenes(profile, script.scenes);
} catch (e) {
  fail(e.message);
}
if (!["en", "ar"].includes(script.language))
  fail(`no render fonts for language ${script.language}`);
// Arabic reads right to left, in the Arabic type roles beside the Latin ones.
const dir = script.language === "ar" ? "rtl" : "ltr";
const roles = typeRoles(script.language);

if (!fs.existsSync(path.join(run, "voice.json")))
  fail("no voice.json: run the voice stage first (voice/voice.mjs)");
const voice = json(path.join(run, "voice.json"));
script.scenes.forEach((s, i) => {
  const v = voice.scenes[i];
  if (
    v?.id !== s.id ||
    v.words.map((w) => w.text).join(" ") !== s.narration.join(" ")
  )
    fail(`voice.json does not match scene ${s.id}: run the voice stage again`);
});
if (voice.scenes.length !== script.scenes.length)
  fail("voice.json does not match script.json: run the voice stage again");
const narrator =
  script.narrator ??
  json(path.join(skill, "narrators.json")).narrators.find(
    (n) => n.language === script.language && n.default,
  )?.id;
if (voice.narrator !== narrator || voice.language !== script.language)
  fail(
    `voice.json holds narrator ${voice.narrator}, the script asks for ${narrator}: run the voice stage again`,
  );

// The rows this stage reads, each installed by setup, or a font by the draft
// that named it.
const rows = catalogue();
const fontRows = [
  ...new Set(
    roles.map(
      (r) =>
        profile.type?.[r]?.font ??
        fail(`style profile ${profile.name} names no ${r} font`),
    ),
  ),
].map(
  (font) =>
    fontRow(profile, font) ??
    fail(
      `style profile ${profile.name} names font ${font}, which no setup row installs`,
    ),
);
for (const r of rows.filter((r) => ["npm", "chrome"].includes(r.kind)))
  if (!fs.existsSync(path.join(dest(r), ".stamp")))
    fail(`${r.id} is not installed: run /explainer-video setup`);
for (const r of fontRows) {
  const gap = fontGap(r);
  if (gap) fail(`${gap}: run /explainer-video setup`);
}

// The score the brief asks for: on (synthesised), off, or ace-step, the
// opt-in row setup installs only when asked for.
const briefFile = path.join(run, "brief.json");
const scoreMode = fs.existsSync(briefFile) ? json(briefFile).score : "on";
const ace =
  !stillsOnly && scoreMode === "ace-step"
    ? rows.find((r) => r.id === "ace-step")
    : null;
const backend = await loadBackend();
// A scene that draws WebGL takes the host GPU: refused here, before any render,
// where the gpu-3d row says no NVIDIA card answers.
const webgl = drawsWebgl(script.scenes);
const noGpu =
  webgl &&
  gpuRefusal(
    rows.find((r) => r.id === "gpu-3d"),
    await backend.computeCapability(),
  );
if (noGpu) fail(`gpu-3d: ${noGpu}`);
const device = ace && torchDevice(await backend.computeCapability());
if (ace && !fs.existsSync(path.join(dest(ace, undefined, device), ".stamp")))
  fail(
    "ace-step is not installed: run /explainer-video setup, asking for ace-step",
  );

// Timeline: scenes back to back on the frame grid, every word and sentence
// start absolute. A scene's `slot` is its duration plus its seam out, which
// runs on over the next scene's start: no start and no word time moves.
const grid = gridScenes(
  voice.scenes.map((v) => wavSeconds(run, v.audio, fail)),
  HOLD,
);
const seams = seamPlan(script.scenes, profile);
const scenes = script.scenes.map((s, i) => {
  const v = voice.scenes[i];
  const start = written(grid[i].start);
  const duration = written(grid[i].frames);
  const words = v.words.map((w) => ({
    text: w.text,
    start: r3(start + w.start),
    end: r3(start + w.end),
  }));
  let first = 0;
  const sentences = s.narration.map((n) => {
    const t = words[first].start;
    first += n.split(/\s+/).length;
    return t;
  });
  return {
    id: s.id,
    start,
    duration,
    slot: slot(grid[i].frames, seams[i]),
    seam: seams[i].out?.move ?? "cut",
    sentences,
    words,
  };
});
const total = written(grid.total);
fs.writeFileSync(
  path.join(run, "timeline.json"),
  JSON.stringify({ total, scenes }, null, 2) + "\n",
);

const cues = captionCues(script.scenes, scenes);
// The composition: fonts and GSAP copied in from setup's stores, the scenes'
// WAVs joined into one narration with the hold as silence.
const comp = path.join(run, "composition");
fs.rmSync(comp, { recursive: true, force: true });
fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
const fonts = compositionAssets(fontRows, comp, { webgl });

const raw = path.join(run, ".cache", "narration.wav");
fs.mkdirSync(path.dirname(raw), { recursive: true });
const voiced = joinNarration({
  run,
  voice,
  frames: grid.map((g) => g.frames),
  file: raw,
  fail,
});

// The score, unless the brief turns it off or only stills are wanted: cached
// in .cache/score/ by the timings, roles, seed, level, sfx floor and the
// engine's code, since a 2-minute score takes seconds to synthesise; an
// ACE-Step score also by its row's pins and its device, and takes minutes.
const scored = !stillsOnly && scoreMode !== "off";
let bed;
if (scored) {
  const roles = script.scenes.map((s) => s.role);
  const seed = parseInt(hash(slug).slice(0, 8), 16);
  const level = r3(bedLevel(voiced.pcm, voiced.rate, scenes));
  const { perMinute } = floors(profile).sfx;
  const engine = path.join(skill, "scripts", "score");
  const code = fs
    .readdirSync(engine)
    .filter((f) => /\.(mjs|py)$/.test(f))
    .sort()
    .map((f) => fs.readFileSync(path.join(engine, f), "utf8"));
  const key = hash(
    scenes.map((s) => [s.start, s.words]),
    total,
    roles,
    seed,
    level,
    perMinute,
    ...code,
    ...(ace ? [ace.source.revision, ace.revision, device] : []),
  );
  const dir = path.join(run, ".cache", "score");
  bed = path.join(dir, `${key}.wav`);
  if (!fs.existsSync(bed)) {
    let music;
    try {
      music =
        ace &&
        (await backend.aceStep({
          dir: dest(ace, undefined, device),
          device,
          seconds: total,
          seed,
          caption: ACE_CAPTION,
        }));
    } catch (e) {
      fail(e.message);
    }
    const s = score({ scenes, roles, total, seed, level, perMinute, music });
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, `${key}.json`),
      JSON.stringify(
        ace
          ? { seed, device, cues: s.cues }
          : { preset: s.spec.preset, seed, cues: s.cues },
      ),
    );
    writeWav(`${bed}.part`, s.buf);
    fs.renameSync(`${bed}.part`, bed);
  }
  fs.writeFileSync(
    path.join(run, "score.json"),
    JSON.stringify(
      { score: scoreMode, ...json(path.join(dir, `${key}.json`)) },
      null,
      2,
    ) + "\n",
  );
} else if (!stillsOnly)
  fs.writeFileSync(
    path.join(run, "score.json"),
    JSON.stringify({ score: "off", cues: [] }, null, 2) + "\n",
  );

// The narration, the score mixed under it, mastered to -14 LUFS, its peak half
// a dB under the loudness gate's ceiling.
try {
  await backend.master(raw, path.join(comp, "narration.wav"), {
    lufs: LUFS,
    peak: floors(profile).loudness.peak - 0.5,
    bed,
  });
} catch (e) {
  fail(e.message);
}
fs.rmSync(raw);

const timing = (sc) => ({
  duration: sc.duration,
  slot: sc.slot,
  sentences: sc.sentences.map((t) => r3(t - sc.start)),
  words: sc.words.map((w) => r3(w.start - sc.start)),
});
const files = [];
for (const [i, s] of script.scenes.entries()) {
  let html;
  try {
    html = await sceneFile(s, timing(scenes[i]), profile, {
      backend,
      dir,
      seam: seams[i],
    });
  } catch (e) {
    fail(`scene ${s.id}: ${e.message}`);
  }
  fs.writeFileSync(path.join(comp, "scenes", `${s.id}.html`), html);
  files.push(html);
}
fs.writeFileSync(
  path.join(comp, "index.html"),
  videoPage({
    title: script.title,
    profile,
    fonts,
    scenes,
    cues,
    total,
    webgl,
    dir,
  }),
);

const env = hyperframesEnv();
async function hyperframes(what, args, cwd) {
  const code = await backend.hyperframes(
    [
      "render",
      "--strict",
      "--quiet",
      "--fps",
      String(FPS),
      "--workers",
      "3",
      ...(webgl ? ["--browser-gpu"] : []),
      ...args,
    ],
    { cwd, env },
  );
  if (code !== 0) fail(`hyperframes render of the ${what} exited ${code}`);
}

const inputs = renderInputs(
  fontRows.map((r) => r.family),
  profile,
  webgl,
);

// Stills: the uncached scenes in one stills page, a frame each.
const stillDir = path.join(run, ".cache", "stills");
fs.mkdirSync(stillDir, { recursive: true });
const stills = script.scenes.map((s, i) =>
  path.join(
    stillDir,
    `${hash(files[i], profile, timing(scenes[i]), script.title, inputs)}.png`,
  ),
);
const missing = script.scenes.filter((s, i) => !fs.existsSync(stills[i]));
if (missing.length) {
  const work = path.join(stillDir, "work");
  fs.rmSync(work, { recursive: true, force: true });
  fs.mkdirSync(path.join(work, "scenes"), { recursive: true });
  fs.cpSync(path.join(comp, "fonts"), path.join(work, "fonts"), {
    recursive: true,
  });
  for (const f of ["gsap.min.js", ...(webgl ? ["three.min.js"] : [])])
    fs.copyFileSync(path.join(comp, f), path.join(work, f));
  for (const s of missing)
    fs.copyFileSync(
      path.join(comp, "scenes", `${s.id}.html`),
      path.join(work, "scenes", `${s.id}.html`),
    );
  fs.writeFileSync(
    path.join(work, "index.html"),
    stillsPage({
      title: script.title,
      profile,
      fonts,
      ids: missing.map((s) => s.id),
      webgl,
      dir,
    }),
  );
  const frames = path.join(work, "frames");
  await hyperframes(
    "stills",
    ["--format", "png-sequence", "-o", path.resolve(frames)],
    work,
  );
  const pngs = fs
    .readdirSync(frames)
    .filter((f) => /^frame_\d+\.png$/.test(f))
    .sort();
  if (pngs.length !== missing.length)
    fail(
      `the stills render wrote ${pngs.length} frame(s) for ${missing.length} scene(s)`,
    );
  missing.forEach((s, k) =>
    fs.copyFileSync(
      path.join(frames, pngs[k]),
      stills[script.scenes.indexOf(s)],
    ),
  );
  fs.rmSync(work, { recursive: true, force: true });
}

// Every scene's still, at its fullest moment, for the storyboard (path relative to the run).
fs.writeFileSync(
  path.join(run, "stills.json"),
  JSON.stringify(
    {
      scenes: script.scenes.map((s, i) => ({
        id: s.id,
        still: path.relative(run, stills[i]),
      })),
    },
    null,
    2,
  ) + "\n",
);
if (stillsOnly) {
  console.log(
    `render: stills ${scenes.length - missing.length}/${scenes.length} cached`,
  );
  process.exit(0);
}

// out/ holds one render's files or none: cleared now, and again on a failed check.
const out = path.join(run, "out");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out);
const srt = path.join(out, `${slug}.srt`);
fs.writeFileSync(srt, srtText(cues));

// The video, keyed by every file the composition holds.
const listing = (dir) =>
  fs
    .readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(dir, path.join(e.parentPath, e.name)))
    .sort();
// GPU and software encodes of one composition differ, so the encode mode keys
// the cached video. `--gpu` is passed only where NVENC probes usable: HyperFrames
// would otherwise pick another GPU encoder this key does not name.
const nvenc = await backend.nvenc();
const renderDir = path.join(run, ".cache", "render");
fs.mkdirSync(renderDir, { recursive: true });
// `d`'s video from the cache, or rendered into it.
async function cachedVideo(d) {
  const key = crypto
    .createHash("sha256")
    .update(JSON.stringify([...inputs, nvenc ? "nvenc" : "x264"]));
  for (const f of listing(d))
    key.update(f).update(fs.readFileSync(path.join(d, f)));
  const video = path.join(renderDir, `${key.digest("hex").slice(0, 16)}.mp4`);
  const cached = fs.existsSync(video);
  if (!cached) {
    const part = video.replace(/\.mp4$/, ".part.mp4");
    await hyperframes(
      "video",
      [
        "--quality",
        "looks",
        ...(nvenc ? ["--gpu"] : []),
        "-o",
        path.resolve(part),
      ],
      d,
    );
    fs.renameSync(part, video);
  }
  return { video, cached };
}

// A video in sections renders each section on its own (render/sections.mjs),
// joins the parts and muxes the audio once; any other renders whole.
const mp4 = path.join(out, `${slug}.mp4`);
const sectionDir = path.join(run, ".cache", "sections");
fs.rmSync(sectionDir, { recursive: true, force: true });
const sections = sectionsOf(script.scenes);
const built = [];
let chapters = null;
let hits = 0;
for (const sec of sections.length ? sections : [null]) {
  const d = sec ? path.join(sectionDir, String(sec.number)) : comp;
  if (sec)
    writeSection(d, {
      sec,
      comp,
      script,
      timeline: scenes,
      profile,
      fonts,
      webgl,
      dir,
    });
  const { video, cached } = await cachedVideo(d);
  built.push(video);
  hits += +cached;
}
if (!sections.length) fs.copyFileSync(built[0], mp4);
else {
  chapters = chaptersOf(sections, script.scenes, scenes, total);
  try {
    await joinSections(backend, {
      parts: built,
      joined: path.join(renderDir, "joined.mp4"),
      audio: path.join(comp, "narration.wav"),
      chapters,
      output: mp4,
    });
  } catch (e) {
    fail(e.message);
  }
}
fs.copyFileSync(stills[0], path.join(out, "poster.png"));

// The gates judge out/; a red one leaves no video. The cached render stays: a
// red gate is deterministic, so rendering it again would change nothing.
const gates = spawnSync(
  process.execPath,
  [path.join(skill, "scripts", "gates", "gates.mjs"), run],
  { stdio: "inherit" },
);
if (gates.status !== 0) {
  fs.rmSync(out, { recursive: true, force: true });
  fail("the gates did not pass: nothing delivered");
}

// Delivery checks, every one printed before any verdict.
let probe;
try {
  probe = await backend.ffprobe(mp4);
} catch (e) {
  fail(e.message);
}
const { size, fps, ratio } = videoFacts(probe);
const seconds = +probe.format.duration;
const srtCues = (fs.readFileSync(srt, "utf8").match(/^\d+\n.+ --> .+$/gm) ?? [])
  .length;
const checks = [
  ["resolution", size, `${W}x${H}`],
  ["frame rate", fps, FPS],
  ["aspect", ratio, "16:9"],
  [
    "duration",
    `${seconds.toFixed(2)} s`,
    `${total.toFixed(2)} s within 0.25 s`,
    Math.abs(seconds - total) <= 0.25,
  ],
  [
    "audio",
    probe.streams.some((s) => s.codec_type === "audio") ? "a stream" : "none",
    "a stream",
  ],
  ["srt", `${srtCues} cue(s)`, `${cues.length} cue(s)`],
];
if (chapters) checks.push(chapterCheck(chapters, probe.chapters));
let failed = 0;
for (const [name, got, want, ok = got === want] of checks) {
  if (!ok) failed++;
  console.log(`delivery ${name}: ${ok ? "pass" : `fail: ${got} vs ${want}`}`);
}
if (failed) {
  fs.rmSync(out, { recursive: true, force: true });
  // A failed video never stands in the cache as a later run's hit.
  for (const v of built) fs.rmSync(v, { force: true });
  process.exit(1);
}

const delivered = deliver(run, out, slug, videosDir());
console.log(`delivered: ${delivered}`);

writeManifest(run, {
  lock: lockHash,
  profile: profile.name,
  narrator: voice.narrator,
  delivered,
});
console.log(
  `render: ${slug}.mp4 ${seconds.toFixed(2)} s, ${scenes.length} scene(s), stills ${scenes.length - missing.length}/${scenes.length} cached, video ${
    sections.length
      ? `${hits}/${sections.length} sections cached`
      : hits
        ? "cached"
        : "rendered"
  }`,
);
