// The render stage: the voiced script to a captioned MP4, SRT and poster.
//
//   node render.mjs <run-folder> [--stills]
//
// Reads <run>/script.json and <run>/voice.json and the run's style profile
// (lib/style.mjs). Times every scene back to back at its voice duration, the
// last held 1 s, cues captions from the word timings, composes the video in
// <run>/composition/ with the narration mastered (the score from
// score/score.mjs mixed under it, unless brief.json turns it off), renders a
// settled still per scene and then the video with HyperFrames, each cached in
// <run>/.cache/ by content hash, runs the gates stage (gates/gates.mjs) on
// out/, checks the MP4 with ffprobe, and copies MP4, SRT and poster to the
// videos folder. A red gate or a failed check empties out/ and delivers
// nothing. With `--stills` it stops after the stills: no video, gates,
// delivery or manifest, for the storyboard.
// stdout: the gates stage's lines, one `delivery <check>: pass|fail:
//         <measured> vs <wanted>` line per check, `delivered: <path>`, then
//         `render: <slug>.mp4 <seconds> s, <n> scene(s), stills <hit>/<n>
//         cached, video cached|rendered`
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
import { videosDir } from "../lib/paths.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { LUFS, floors, loadStyle, typeRoles } from "../lib/style.mjs";
import { writeWav } from "../score/dsp.mjs";
import { ACE_CAPTION, bedLevel, score } from "../score/score.mjs";
import {
  aceDevice,
  catalogue,
  compositionAssets,
  dest,
  fontRow,
  hyperframesEnv,
  loadBackend,
  lockHash,
  renderInputs,
  skill,
} from "../lib/tools.mjs";
import {
  CUE_CHARS,
  FPS,
  H,
  W,
  sceneFile,
  stillsPage,
  videoPage,
} from "./compose.mjs";

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
const HOLD = 1.0;
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
} catch (e) {
  fail(e.message);
}
if (profile.layout !== "bands" || profile.motion !== "rise")
  fail(
    `style profile ${profile.name}: this version draws layout bands with motion rise, not ${profile.layout} with ${profile.motion}`,
  );
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
for (const r of [
  ...rows.filter((r) => ["npm", "chrome"].includes(r.kind)),
  ...fontRows,
])
  if (!fs.existsSync(path.join(dest(r), ".stamp")))
    fail(`${r.id} is not installed: run /explainer-video setup`);

// The score the brief asks for: on (synthesised), off, or ace-step, the
// opt-in row setup installs only when asked for.
const briefFile = path.join(run, "brief.json");
const scoreMode = fs.existsSync(briefFile) ? json(briefFile).score : "on";
const ace =
  !stillsOnly && scoreMode === "ace-step"
    ? rows.find((r) => r.id === "ace-step")
    : null;
if (ace && !fs.existsSync(path.join(dest(ace), ".stamp")))
  fail(
    "ace-step is not installed: run /explainer-video setup, asking for ace-step",
  );

// Timeline: scenes back to back, every word and sentence start absolute.
let at = 0;
const scenes = script.scenes.map((s, i) => {
  const v = voice.scenes[i];
  const start = r3(at);
  const duration = r3(v.duration + (i === script.scenes.length - 1 ? HOLD : 0));
  at += duration;
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
  return { id: s.id, start, duration, sentences, words };
});
const total = r3(at);
fs.writeFileSync(
  path.join(run, "timeline.json"),
  JSON.stringify({ total, scenes }, null, 2) + "\n",
);

// Captions: a cue breaks at a sentence end, or before a token that would take
// it past CUE_CHARS; it shows until the next cue in its scene starts.
const cues = [];
script.scenes.forEach((s, i) => {
  const sc = scenes[i];
  const own = [];
  let w = 0;
  for (const tokens of s.captions) {
    let cue = null;
    for (const t of tokens) {
      const token = {
        text: t.text,
        start: sc.words[w].start,
        end: sc.words[w + t.words - 1].end,
      };
      w += t.words;
      if (cue && `${cue.text} ${t.text}`.length > CUE_CHARS) cue = null;
      if (cue) {
        cue.text += ` ${t.text}`;
        cue.tokens.push(token);
      } else {
        cue = { text: t.text, tokens: [token] };
        own.push(cue);
      }
    }
  }
  own.forEach((c, k) => {
    c.start = c.tokens[0].start;
    c.end =
      own[k + 1]?.tokens[0].start ??
      r3(Math.min(c.tokens.at(-1).end + 0.3, sc.start + sc.duration));
  });
  cues.push(...own);
});
const clock = (t) => {
  const ms = Math.round(t * 1000);
  const pad = (n, w = 2) => String(n).padStart(w, "0");
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms / 60000) % 60)}:${pad(Math.floor(ms / 1000) % 60)},${pad(ms % 1000, 3)}`;
};
// The composition: fonts and GSAP copied in from setup's stores, the scenes'
// WAVs joined into one narration with the hold as silence.
const comp = path.join(run, "composition");
fs.rmSync(comp, { recursive: true, force: true });
fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
const fonts = compositionAssets(fontRows, comp);

function narration(file) {
  const parts = voice.scenes.map((v) => {
    const b = fs.readFileSync(path.join(run, v.audio));
    if (
      b.toString("ascii", 0, 4) !== "RIFF" ||
      b.readUInt16LE(22) !== 1 ||
      b.readUInt16LE(34) !== 16
    )
      fail(`${v.audio} is not 16-bit mono PCM: run the voice stage again`);
    return {
      rate: b.readUInt32LE(24),
      data: b.subarray(44, 44 + b.readUInt32LE(40)),
    };
  });
  const rate = parts[0].rate;
  if (parts.some((p) => p.rate !== rate))
    fail("the scenes' WAVs differ in sample rate: run the voice stage again");
  const data = Buffer.concat([
    ...parts.map((p) => p.data),
    Buffer.alloc(Math.round(HOLD * rate) * 2),
  ]);
  const h = Buffer.alloc(44);
  h.write("RIFF", 0, "ascii");
  h.writeUInt32LE(36 + data.length, 4);
  h.write("WAVEfmt ", 8, "ascii");
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write("data", 36, "ascii");
  h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, data]));
  return {
    rate,
    pcm: new Int16Array(data.buffer, data.byteOffset, data.length / 2),
  };
}
const backend = await loadBackend();
const raw = path.join(run, ".cache", "narration.wav");
fs.mkdirSync(path.dirname(raw), { recursive: true });
const voiced = narration(raw);

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
  const device = ace && aceDevice(await backend.computeCapability());
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
          dir: dest(ace),
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
  sentences: sc.sentences.map((t) => r3(t - sc.start)),
});
const files = [];
for (const [i, s] of script.scenes.entries()) {
  let html;
  try {
    html = await sceneFile(s, timing(scenes[i]), profile, { backend, dir });
  } catch (e) {
    fail(`scene ${s.id}: ${e.message}`);
  }
  fs.writeFileSync(path.join(comp, "scenes", `${s.id}.html`), html);
  files.push(html);
}
fs.writeFileSync(
  path.join(comp, "index.html"),
  videoPage({ title: script.title, profile, fonts, scenes, cues, total, dir }),
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
      ...args,
    ],
    { cwd, env },
  );
  if (code !== 0) fail(`hyperframes render of the ${what} exited ${code}`);
}

const inputs = renderInputs(
  fontRows.map((r) => r.family),
  profile,
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
  fs.copyFileSync(
    path.join(comp, "gsap.min.js"),
    path.join(work, "gsap.min.js"),
  );
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

// Every scene's settled still, for the storyboard (path relative to the run).
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
fs.writeFileSync(
  srt,
  cues
    .map(
      (c, i) => `${i + 1}\n${clock(c.start)} --> ${clock(c.end)}\n${c.text}\n`,
    )
    .join("\n"),
);

// The video, keyed by every file the composition holds.
const listing = (dir) =>
  fs
    .readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(dir, path.join(e.parentPath, e.name)))
    .sort();
const key = crypto.createHash("sha256").update(JSON.stringify(inputs));
for (const f of listing(comp))
  key.update(f).update(fs.readFileSync(path.join(comp, f)));
const renderDir = path.join(run, ".cache", "render");
fs.mkdirSync(renderDir, { recursive: true });
const video = path.join(renderDir, `${key.digest("hex").slice(0, 16)}.mp4`);
const cached = fs.existsSync(video);
if (!cached) {
  const part = video.replace(/\.mp4$/, ".part.mp4");
  await hyperframes(
    "video",
    ["--quality", "looks", "-o", path.resolve(part)],
    comp,
  );
  fs.renameSync(part, video);
}
fs.copyFileSync(video, path.join(out, `${slug}.mp4`));
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
  probe = await backend.ffprobe(video);
} catch (e) {
  fail(e.message);
}
const vs = probe.streams.find((s) => s.codec_type === "video") ?? {};
const [num, den = 1] = String(vs.r_frame_rate ?? "0/1")
  .split("/")
  .map(Number);
const fps = +(num / den).toFixed(3);
const gcd = (a, b) => (b ? gcd(b, a % b) : a);
const ratio =
  vs.display_aspect_ratio && vs.display_aspect_ratio !== "0:1"
    ? vs.display_aspect_ratio
    : `${vs.width / gcd(vs.width, vs.height)}:${vs.height / gcd(vs.width, vs.height)}`;
const seconds = +probe.format.duration;
const srtCues = (fs.readFileSync(srt, "utf8").match(/^\d+\n.+ --> .+$/gm) ?? [])
  .length;
const checks = [
  ["resolution", `${vs.width}x${vs.height}`, `${W}x${H}`],
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
let failed = 0;
for (const [name, got, want, ok = got === want] of checks) {
  if (!ok) failed++;
  console.log(`delivery ${name}: ${ok ? "pass" : `fail: ${got} vs ${want}`}`);
}
if (failed) {
  fs.rmSync(out, { recursive: true, force: true });
  // A failed video never stands in the cache as a later run's hit.
  fs.rmSync(video, { force: true });
  process.exit(1);
}

// The videos folder, under the repo's name: a worktree's is its main repo's.
// A submodule's or a separate git dir's common dir is no `<repo>/.git`, so
// those take their top level's name.
const git = spawnSync(
  "git",
  [
    ...["-C", run, "rev-parse", "--path-format=absolute"],
    ...["--git-common-dir", "--show-toplevel"],
  ],
  { encoding: "utf8" },
);
const [common, top] = git.stdout.trim().split("\n");
const repo =
  git.status !== 0
    ? path.basename(path.dirname(path.dirname(path.resolve(run))))
    : path.basename(common) === ".git"
      ? path.basename(path.dirname(common))
      : path.basename(top);
const delivered = path.join(videosDir(), "explainer-video", repo, slug);
fs.mkdirSync(delivered, { recursive: true });
for (const f of [`${slug}.mp4`, `${slug}.srt`, "poster.png"])
  fs.copyFileSync(path.join(out, f), path.join(delivered, f));
console.log(`delivered: ${delivered}`);

const manifestFile = path.join(run, "manifest.json");
const manifest = fs.existsSync(manifestFile) ? json(manifestFile) : {};
fs.writeFileSync(
  manifestFile,
  JSON.stringify(
    {
      board: manifest.board ?? null,
      skill: fs
        .readFileSync(path.join(skill, "SKILL.md"), "utf8")
        .match(/^ {2}version: (\S+)$/m)[1],
      lock: lockHash,
      profile: profile.name,
      narrator: voice.narrator,
      delivered,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `render: ${slug}.mp4 ${seconds.toFixed(2)} s, ${scenes.length} scene(s), stills ${scenes.length - missing.length}/${scenes.length} cached, video ${cached ? "cached" : "rendered"}`,
);
