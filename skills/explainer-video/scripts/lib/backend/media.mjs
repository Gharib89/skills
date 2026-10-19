// The backend's media tools: frames, clips, loudness, fonts, downloads, models.
import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { CONTENT } from "../../render/compose.mjs";
import { meanDiff, sceneFrames } from "../motion.mjs";
import { ORT_CUDA_LIBS, skill, toolPaths, torchDevice } from "../tools.mjs";
import { fromCache, ffmpeg, quiet, sampleRate, which } from "./common.mjs";

// The SHA-256 of an image's decoded pixels (RGB at full size), never of its
// file, so encoder metadata can neither pass nor fail a comparison.
export async function framePixels(file) {
  const r = spawnSync(
    "ffmpeg",
    [
      ...["-hide_banner", "-v", "error", "-i", file, "-frames:v", "1"],
      ...["-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
    ],
    { maxBuffer: 1 << 28 },
  );
  if (r.status !== 0)
    throw new Error(
      `ffmpeg could not decode ${file}: ${(r.stderr?.toString() || r.error?.message || "").trim().split("\n").pop()}`,
    );
  return crypto.createHash("sha256").update(r.stdout).digest("hex");
}

// One scene's stretch of the delivered video as a small MP4: a board card plays
// its own scene, and 960 wide keeps a 30 s scene well under the 15 MB asset cap.
export async function clip(input, output, { start, duration }) {
  ffmpeg([
    ...["-y", "-ss", String(start), "-t", String(duration), "-i", input],
    ...["-vf", "scale=960:-2", "-c:v", "libx264", "-preset", "veryfast"],
    ...["-crf", "30", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart"],
    output,
  ]);
}

// A scene's contact sheet for the critic: four frames of the encoded video (its
// three quarter marks and its fullest moment, `fullest` a frame index) at half
// size on a 2x2 grid, in that reading order. Cut by ffmpeg, never by
// HyperFrames' snapshot, which sends frames to Gemini.
export async function sheet(input, output, { start, duration, fps, fullest }) {
  const [first, picks] = sheetFrames({ start, duration, fps, fullest });
  const tiles = picks.map((_, i) => String.fromCharCode(97 + i));
  ffmpeg([
    ...["-y", "-ss", String(start), "-t", String(duration), "-i", input],
    "-filter_complex",
    [
      `[0:v]split=4${tiles.map((x) => `[${x}]`).join("")}`,
      // Each branch keeps its one frame, restamped to 0 so the stack pairs them.
      ...picks.map(
        (f, i) =>
          `[${tiles[i]}]select='eq(n,${f - first})',setpts=0,scale=960:540[${tiles[i]}1]`,
      ),
      `${tiles.map((x) => `[${x}1]`).join("")}xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0`,
    ].join(";"),
    ...["-frames:v", "1", output],
  ]);
}

// A scene's motion strip for the critic: 12 consecutive frames of the encoded
// video from frame `first`, 320x180 a tile, tiled 6x2 in reading order.
export async function strip(input, output, { first, fps }) {
  ffmpeg([
    // Half a frame early, so the seek lands on frame `first` and not after it.
    ...["-y", "-ss", String(Math.max(0, (first - 0.5) / fps)), "-i", input],
    ...["-vf", "scale=320:180,tile=6x2", "-frames:v", "1", output],
  ]);
}

// The mean absolute difference between each frame of a scene and the one
// before it, over the content band alone (the caption words recolour at every
// word, so the whole frame would peak on a caption): the band downscaled to
// 420x172 grey, frame by frame off ffmpeg's pipe so a long scene never sits in
// memory whole. Entry k compares frame first+k+1 with frame first+k.
export async function bandMotion(input, { start, duration, fps }) {
  const { first, n } = sceneFrames({ start, duration, fps });
  const { left, top, width, height } = CONTENT;
  const [w, h] = [width / 4, Math.floor(height / 4)];
  const child = spawn(
    "ffmpeg",
    [
      ...["-hide_banner", "-v", "error", "-ss", String(start), "-i", input],
      ...["-frames:v", String(n), "-fps_mode", "passthrough"],
      ...[
        "-vf",
        `crop=${width}:${height}:${left}:${top},scale=${w}:${h}:flags=area,format=gray`,
      ],
      ...["-f", "rawvideo", "-"],
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  const diffs = [];
  let before = null;
  let pending = Buffer.alloc(0);
  let err = "";
  child.stderr.on("data", (d) => (err += d));
  child.stdout.on("data", (d) => {
    pending = Buffer.concat([pending, d]);
    while (pending.length >= w * h) {
      const f = Buffer.from(pending.subarray(0, w * h));
      pending = pending.subarray(w * h);
      if (before) diffs.push(meanDiff(before, f));
      before = f;
    }
  });
  const code = await new Promise((done) => child.on("close", done));
  if (code !== 0 || diffs.length !== n - 1)
    throw new Error(
      `ffmpeg read ${diffs.length + 1} of ${n} frame(s) of ${input} from ${start} s${err.trim() ? `: ${err.trim().split("\n").pop()}` : ""}`,
    );
  return diffs;
}

// The scene's first frame and the four a sheet shows, as indices into the
// video: the quarter marks, then `fullest`.
export function sheetFrames({ fullest, ...scene }) {
  const { first, n } = sceneFrames(scene);
  return [
    first,
    [...[n / 4, n / 2, (3 * n) / 4].map((f) => first + Math.floor(f)), fullest],
  ];
}

// A scene's narration WAV as audio-only WebM (Opus): the artifact asset upload
// takes video types but no audio type, and a card's <audio> plays it as is.
export async function narration(input, output) {
  ffmpeg(["-y", "-i", input, "-vn", "-c:a", "libopus", "-b:a", "64k", output]);
}

// Integrated loudness (LUFS) and true peak (dBTP) of a file's audio, as
// ffmpeg's ebur128 summary prints them.
export async function loudness(file) {
  const err = ffmpeg([
    "-i",
    file,
    "-af",
    "ebur128=peak=true",
    "-f",
    "null",
    "-",
  ]);
  const summary = err.slice(err.lastIndexOf("Summary:"));
  const lufs = summary.match(/\n\s*I:\s*(-?[\d.]+|-inf) LUFS/)?.[1];
  const peak = summary.match(
    /True peak:[\s\S]*?Peak:\s*(-?[\d.]+|-inf) dBFS/,
  )?.[1];
  if (lufs === undefined || peak === undefined || lufs === "-inf")
    throw new Error(`ffmpeg ebur128 gave no loudness for ${file}`);
  return { lufs: +lufs, peak: +peak };
}

// Two-pass loudnorm to `lufs` integrated and `peak` true peak (LRA 11), as
// 16-bit stereo PCM WAV at the input's rate. Pass 2 is linear from pass 1's
// measurements, so speech keeps its dynamics. Mastered as stereo, both
// channels the source's: HyperFrames upmixes a mono track at full level into
// each channel (pan FL=FL+FC), which reads 3 LU louder than the mono master.
// A `bed` (a stereo WAV, the score) is summed under the narration before the
// loudnorm, and the master then takes the bed's 48 kHz.
export async function master(input, output, { lufs, peak, bed }) {
  const loud = `loudnorm=I=${lufs}:TP=${peak}:LRA=11`;
  const target = bed
    ? `[0:a]pan=stereo|c0=c0|c1=c0[v];[v][1:a]amix=inputs=2:duration=first:normalize=0,${loud}`
    : `pan=stereo|c0=c0|c1=c0,${loud}`;
  const inputs = ["-i", input, ...(bed ? ["-i", bed] : [])];
  const filter = bed ? "-filter_complex" : "-af";
  const err = ffmpeg([
    ...inputs,
    filter,
    `${target}:print_format=json`,
    "-f",
    "null",
    "-",
  ]);
  const m = err.match(/\{[^{}]*"input_i"[^{}]*\}/)?.[0];
  if (!m)
    throw new Error(`loudnorm pass 1 printed no measurements for ${input}`);
  const j = JSON.parse(m);
  // With a score, its rate; without, the narration's own.
  const rate = bed ? 48000 : sampleRate(input);
  ffmpeg([
    "-y",
    ...inputs,
    filter,
    `${target}:measured_I=${j.input_i}:measured_TP=${j.input_tp}:measured_LRA=${j.input_lra}:measured_thresh=${j.input_thresh}:offset=${j.target_offset}:linear=true`,
    "-ar",
    String(rate),
    "-c:a",
    "pcm_s16le",
    output,
  ]);
}

export async function ffprobe(file) {
  const r = spawnSync(
    "ffprobe",
    ["-v", "error", "-show_streams", "-show_format", "-of", "json", file],
    { encoding: "utf8" },
  );
  if (r.status !== 0)
    throw new Error(`ffprobe ${file}: ${r.stderr.trim() || r.error?.message}`);
  return JSON.parse(r.stdout);
}

// A Fontsource family's metadata, or null for a family it does not hold.
export async function fontMeta(id) {
  const r = await fetch(
    `https://api.fontsource.org/v1/fonts/${encodeURIComponent(id)}`,
  );
  if (r.status === 404) return null;
  if (!r.ok)
    throw new Error(`Fontsource has no family ${id} (HTTP ${r.status})`);
  return r.json();
}

// Streamed to disk: a checkpoint can outgrow what one buffer holds.
export async function download(url, file) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  await pipeline(Readable.fromWeb(r.body), fs.createWriteStream(file));
}

// A GitHub source archive into `dir`, its one top folder stripped.
export async function extract(zip, dir) {
  const JSZip = fromCache(toolPaths().node)("jszip");
  const archive = await JSZip.loadAsync(fs.readFileSync(zip));
  for (const f of Object.values(archive.files)) {
    const rel = f.name.split("/").slice(1).join("/");
    if (!rel || f.dir) continue;
    const out = path.join(dir, ...rel.split("/"));
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, await f.async("nodebuffer"));
  }
}

// onnxruntime's CUDA provider files from its NuGet package into `dir`, the
// folder onnxruntime-node loads them from.
export async function extractOrtCuda(nupkg, dir) {
  const JSZip = fromCache(toolPaths().node)("jszip");
  const archive = await JSZip.loadAsync(fs.readFileSync(nupkg));
  fs.mkdirSync(dir, { recursive: true });
  for (const name of ORT_CUDA_LIBS) {
    const f = archive.file(`runtimes/linux-x64/native/${name}`);
    if (!f) throw new Error(`the package holds no ${name}`);
    fs.writeFileSync(path.join(dir, name), await f.async("nodebuffer"));
  }
}

// A one-node Conv model (a 1x1 kernel of 1.0 over a 1x1x1x1 input), the
// smallest model that needs cuDNN: an Identity model runs on the CUDA provider
// without it (measured on onnxruntime-node 1.30.0), a Conv one fails with "cuDNN
// is unavailable" at its first run.
const CONV_ONNX =
  "08084202100d3a630a0f0a01780a01771201792204436f6e761201672a13080108010801080110014201774a040000803f5a1b0a017812160a14080112100a0208010a0208010a0208010a020801621b0a017912160a14080112100a0208010a0208010a0208010a020801";

// Why onnxruntime-node's CUDA provider does not run here, or null where it does:
// the Conv model run on it in a child process, since a library that fails to
// load can take the process down with it. The reason names the library where
// the loader or onnxruntime does.
export async function cudaProbe(nodeDir) {
  const script = `
    const ort = require(process.argv[1] + "/node_modules/onnxruntime-node");
    (async () => {
      const s = await ort.InferenceSession.create(Buffer.from("${CONV_ONNX}", "hex"), { executionProviders: ["cuda"] });
      await s.run({ x: new ort.Tensor("float32", [3], [1, 1, 1, 1]) });
    })().catch((e) => { console.log(e.message); process.exit(1); });`;
  const r = spawnSync(process.execPath, ["-e", script, nodeDir], {
    encoding: "utf8",
    timeout: 120000,
  });
  if (r.status === 0) return null;
  const said =
    r.stdout || r.stderr || `the probe exited ${r.status ?? r.signal}`;
  const lib = said.match(/(lib[\w.+-]+\.so[\w.]*): cannot open shared object/);
  if (lib) return `${lib[1]} is not found by the dynamic loader`;
  if (/cuDNN is unavailable/.test(said))
    return "libcudnn.so.9 is not found by the dynamic loader";
  const cuda = said.match(/CUDA failure \d+: ([^;]+)/);
  return cuda ? cuda[1].trim() : said.trim().split("\n")[0].slice(0, 160);
}

// A uv project's .venv from its own lockfile, exactly.
export async function uvSync(dir) {
  return (
    spawnSync("uv", ["sync", "--frozen", "--no-dev"], {
      cwd: dir,
      stdio: quiet,
    }).status ?? 1
  );
}

// The first NVIDIA card's compute capability, as nvidia-smi reports it; null
// with no nvidia-smi (no card); undefined when nvidia-smi fails or answers no
// number (a driver mismatch after an update), which may hide a card.
export async function computeCapability() {
  const r = spawnSync(
    "nvidia-smi",
    ["--query-gpu=compute_cap", "--format=csv,noheader"],
    { encoding: "utf8" },
  );
  if (r.error?.code === "ENOENT") return null;
  const cap = parseFloat(r.stdout ?? "");
  return r.status === 0 && cap ? cap : undefined;
}

// Whether ffmpeg can encode one frame on NVENC here: false with no ffmpeg, no
// NVIDIA card or a driver too old for it. HyperFrames' `--gpu` falls back from
// its own probe silently, so the render cache keys on this stand-in for it; the
// two can disagree on an edge case (timeout, frame size, which ffmpeg binary).
export async function nvenc() {
  const r = spawnSync(
    "ffmpeg",
    [
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "color=s=256x256:d=0.1",
      "-frames:v",
      "1",
      "-c:v",
      "h264_nvenc",
      "-f",
      "null",
      "-",
    ],
    { encoding: "utf8", timeout: 10000 },
  );
  return r.status === 0;
}

export const memory = () => os.totalmem();

// The OS and CPU, as Node names them, and macOS's version from sw_vers (null
// elsewhere, or when sw_vers fails), which a row's `unavailable` entries match.
export function platform() {
  const version =
    process.platform === "darwin"
      ? spawnSync("sw_vers", ["-productVersion"], {
          encoding: "utf8",
        }).stdout?.trim() || null
      : null;
  return { os: process.platform, arch: process.arch, version };
}

// ACE-Step's music: scripts/score/ace.py under uv in the ace-step row's folder
// `dir`, as a 48 kHz stereo buffer exactly `seconds` long.
export async function aceStep({ dir, device, seconds, seed, caption }) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ace-step-"));
  try {
    const wav = path.join(tmp, "music.wav");
    const script = path.join(skill, "scripts", "score", "ace.py");
    const args = [
      path.join(dir, "checkpoints"),
      device,
      seconds,
      seed,
      caption,
    ];
    const r = spawnSync(
      "uv",
      [
        "run",
        "--frozen",
        "--no-sync",
        "python",
        script,
        ...args.map(String),
        wav,
      ],
      { cwd: path.join(dir, "src"), stdio: quiet },
    );
    if (r.status !== 0)
      throw new Error(`ace-step exited ${r.status ?? r.error?.message}`);
    const raw = path.join(tmp, "music.f32");
    ffmpeg(["-y", "-i", wav, "-ar", "48000", "-ac", "2", "-f", "f32le", raw]);
    const b = fs.readFileSync(raw);
    const x = new Float32Array(b.buffer, b.byteOffset, b.length / 4);
    const n = Math.round(seconds * 48000);
    const out = { L: new Float32Array(n), R: new Float32Array(n) };
    for (let i = 0; i < Math.min(n, x.length / 2); i++) {
      out.L[i] = x[2 * i];
      out.R[i] = x[2 * i + 1];
    }
    return out;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}
