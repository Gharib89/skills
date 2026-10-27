// The backend's media tools: the join and mux, ffprobe, fonts, downloads, the
// CUDA provider and the machine.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { ORT_CUDA_LIBS, toolPaths } from "../tools.mjs";
import { fromCache, ffmpeg } from "./common.mjs";

// The video-only `parts` joined at hard cuts by stream copy: no frame is
// re-encoded, so each part must start on a keyframe, as every render does. The
// list lives in a temp folder and ffmpeg reads a relative entry against that
// folder, so each part goes in as an absolute path.
export async function concat(parts, output) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-concat-"));
  try {
    const list = path.join(dir, "parts.txt");
    fs.writeFileSync(
      list,
      parts
        .map((p) => `file '${path.resolve(p).replaceAll("'", "'\\''")}'\n`)
        .join(""),
    );
    ffmpeg([
      "-y",
      ...["-f", "concat", "-safe", "0", "-i", list],
      "-c",
      "copy",
      output,
    ]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// `video` with `audio` encoded to AAC once and `chapters` (`{ start, end,
// title }`, seconds) written as MP4 chapter marks; the video stream is copied.
export async function mux({ video, audio, chapters, output }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-mux-"));
  try {
    const meta = path.join(dir, "chapters.txt");
    const esc = (t) => t.replace(/[=;#\\\n]/g, "\\$&");
    const ms = (t) => Math.round(t * 1000);
    fs.writeFileSync(
      meta,
      ";FFMETADATA1\n" +
        chapters
          .map(
            (c) =>
              `[CHAPTER]\nTIMEBASE=1/1000\nSTART=${ms(c.start)}\nEND=${ms(c.end)}\ntitle=${esc(c.title)}\n`,
          )
          .join(""),
    );
    ffmpeg([
      ...["-y", "-i", video, "-i", audio, "-i", meta],
      ...["-map", "0:v", "-map", "1:a", "-map_chapters", "2"],
      ...["-c:v", "copy", "-c:a", "aac", "-b:a", "192k"],
      ...["-movflags", "+faststart", output],
    ]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

export async function ffprobe(file) {
  const r = spawnSync(
    "ffprobe",
    [
      ...["-v", "error", "-show_streams", "-show_format", "-show_chapters"],
      ...["-of", "json", file],
    ],
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

// Streamed to disk: a model file can outgrow what one buffer holds.
export async function download(url, file) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  await pipeline(Readable.fromWeb(r.body), fs.createWriteStream(file));
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

// The OS and CPU, as Node names them, which the CUDA provider row's `os` and
// `arch` match.
export function platform() {
  return { os: process.platform, arch: process.arch };
}
