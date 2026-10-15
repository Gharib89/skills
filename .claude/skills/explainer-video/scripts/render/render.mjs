// The render stage: the voiced script to a captioned MP4, SRT and poster.
//
//   node render.mjs <run-folder>
//
// Reads <run>/script.json and <run>/voice.json and the run's style profile
// (lib/style.mjs). Times every scene back to back at its voice duration, the
// last held 1 s, cues captions from the word timings, composes the video in
// <run>/composition/, renders a settled still per scene and then the video
// with HyperFrames, each cached in <run>/.cache/ by content hash, checks the
// MP4 with ffprobe, and copies MP4, SRT and poster to the videos folder.
// stdout: one `delivery <check>: pass|fail: <measured> vs <wanted>` line per
//         check, `delivered: <path>`, then
//         `render: <slug>.mp4 <seconds> s, <n> scene(s), stills <hit>/<n>
//         cached, video cached|rendered`
// writes: <run>/style.json, timeline.json, composition/, .cache/stills/,
//         .cache/render/, out/<slug>.mp4|.srt, out/poster.png, manifest.json;
//         <videos>/explainer-video/<repo>/<slug>/; explainers/.gitignore
// exit:   0 delivered · 1 refused or failed, `render: <why>` on stderr, or a
//         delivery check failed · 2 usage
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { videosDir } from "../lib/paths.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { loadStyle } from "../lib/style.mjs";
import {
  catalogue,
  dest,
  loadBackend,
  lockHash,
  skill,
  toolPaths,
} from "../lib/tools.mjs";
import { FPS, H, W, sceneFile, stillsPage, videoPage } from "./compose.mjs";

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
const HOLD = 1.0;
// 40 px Inter fits about 73 characters a line in the 1760 px band: 84 is at
// most two lines.
const CUE_CHARS = 84;
const LATIN = ["title", "text", "code"];
const r3 = (n) => +n.toFixed(3);
const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts)
    h.update(typeof p === "string" ? p : JSON.stringify(p));
  return h.digest("hex").slice(0, 16);
};
const json = (f) => JSON.parse(fs.readFileSync(f, "utf8"));
writeIgnore(run);

if (!fs.existsSync(path.join(run, "script.json")))
  fail("no script.json: run the compile stage first (script/compile.mjs)");
const script = json(path.join(run, "script.json"));

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
if (script.language !== "en")
  fail(`no render fonts for language ${script.language}`);

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

// The rows this stage reads, each installed by setup.
const rows = catalogue();
const fontRows = [...new Set(LATIN.map((r) => profile.type[r].font))].map(
  (font) =>
    rows.find((r) => r.kind === "font" && r.family === font) ??
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
const out = path.join(run, "out");
fs.mkdirSync(out, { recursive: true });
const srt = path.join(out, `${slug}.srt`);
fs.writeFileSync(
  srt,
  cues
    .map(
      (c, i) => `${i + 1}\n${clock(c.start)} --> ${clock(c.end)}\n${c.text}\n`,
    )
    .join("\n"),
);

// The composition: fonts and GSAP copied in from setup's stores, the scenes'
// WAVs joined into one narration with the hold as silence.
const comp = path.join(run, "composition");
fs.rmSync(comp, { recursive: true, force: true });
fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
fs.mkdirSync(path.join(comp, "fonts"));
fs.copyFileSync(
  path.join(toolPaths().node, "node_modules", "gsap", "dist", "gsap.min.js"),
  path.join(comp, "gsap.min.js"),
);
const fonts = [];
for (const r of fontRows)
  for (const f of fs
    .readdirSync(dest(r))
    .filter((f) => f.endsWith(".woff2"))
    .sort()) {
    const file = `${r.family}-${f}`;
    fs.copyFileSync(path.join(dest(r), f), path.join(comp, "fonts", file));
    const m = f.match(/-(\d+)-(normal|italic)\.woff2$/);
    fonts.push({
      family: r.family,
      file,
      weight: m?.[1] ?? 400,
      style: m?.[2] ?? "normal",
    });
  }

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
}
narration(path.join(comp, "narration.wav"));

const timing = (sc) => ({
  duration: sc.duration,
  sentences: sc.sentences.map((t) => r3(t - sc.start)),
});
const files = script.scenes.map((s, i) => {
  const html = sceneFile(s, timing(scenes[i]), profile);
  fs.writeFileSync(path.join(comp, "scenes", `${s.id}.html`), html);
  return html;
});
fs.writeFileSync(
  path.join(comp, "index.html"),
  videoPage({ title: script.title, profile, fonts, scenes, cues, total }),
);

const backend = await loadBackend();
// HyperFrames finds Chrome under its home folder, where setup put it, and
// keeps its own state files there too.
const home = dest({ kind: "chrome" });
const env = {
  ...process.env,
  HYPERFRAMES_NO_TELEMETRY: "1",
  DO_NOT_TRACK: "1",
  HYPERFRAMES_NO_UPDATE_CHECK: "1",
  HOME: home,
  USERPROFILE: home,
};
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

// What draws a frame beyond the composition's own files: the npm install
// (HyperFrames, GSAP) and Chrome by the lock, and each font row's version.
const renderInputs = [
  lockHash,
  ...fontRows.map((r) => `${r.family}@${r.version}`),
];

// Stills: the uncached scenes in one stills page, a frame each.
const stillDir = path.join(run, ".cache", "stills");
fs.mkdirSync(stillDir, { recursive: true });
const stills = script.scenes.map((s, i) =>
  path.join(
    stillDir,
    `${hash(files[i], profile, timing(scenes[i]), script.title, renderInputs)}.png`,
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

// The video, keyed by every file the composition holds.
const listing = (dir) =>
  fs
    .readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(dir, path.join(e.parentPath, e.name)))
    .sort();
const key = crypto.createHash("sha256").update(JSON.stringify(renderInputs));
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
if (failed) process.exit(1);

fs.copyFileSync(video, path.join(out, `${slug}.mp4`));
fs.copyFileSync(stills[0], path.join(out, "poster.png"));

// The videos folder, under the repo's name: a worktree's is its main repo's.
const git = spawnSync(
  "git",
  ["-C", run, "rev-parse", "--path-format=absolute", "--git-common-dir"],
  { encoding: "utf8" },
);
const repo =
  git.status === 0
    ? path.basename(path.dirname(git.stdout.trim()))
    : path.basename(path.dirname(path.dirname(path.resolve(run))));
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
