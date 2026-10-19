// The canned backend tests select with EXPLAINER_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $EXPLAINER_VIDEO_FAKE_LOG, so a test asserts on what a stage asked for.
//   EXPLAINER_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
//   EXPLAINER_VIDEO_FAKE_PROBE    JSON fields overriding what ffprobe and
//                                 loudness answer
//   EXPLAINER_VIDEO_FAKE_CHECK    JSON check answers in place of its own
//   EXPLAINER_VIDEO_FAKE_CLIP_BYTES  size of each clip written (default 1000)
//   EXPLAINER_VIDEO_FAKE_CLIP_SECONDS  length of the own-voice clip voiceClip
//                                  writes, its samples a function of the input
//                                  file's bytes (default 12)
//   EXPLAINER_VIDEO_FAKE_ACE_EXIT  ACE-Step's exit code, thrown as the real
//                                  one throws it (unset, it makes the music)
// The family `ubuntu` answers with its real, non-OFL licence; `helvetica-neue`
// and `georgia`, as on the real Fontsource, with no family at all.
//
// Fake audio is 16 kHz and spells its text: each letter holds 3 frames of 320
// samples (2 at the letter's vocabulary id / 100, 1 silent), each word ends on
// a `|` frame and 2 silent frames, each sentence on 10 more. The fake aligner
// reads a frame's id back from its first sample, so word timings come out of
// the real Viterbi pass. A sentence naming a marker word misrenders:
// `garbled` speaks every word as "mumble", `looped` speaks the sentence twice,
// `slowly` holds each letter 8 frames. A `gemini` narrator speaks Arabic the
// same way in the Egyptian aligner's vocabulary (see gemini below), and
//   EXPLAINER_VIDEO_FAKE_QUOTA  a Gemini or ElevenLabs call throws its vendor's
//                               quota error once this many synthesize calls
//                               are in the log; with EXPLAINER_VIDEO_FAKE_CREDITS
//                               set it is the spent-credits 402 instead
// geminiKey refuses the key `bad-key` as API_KEY_INVALID and takes any other;
// elevenlabsKey refuses it as invalid_api_key. An `elevenlabs` narrator speaks
// English like Kokoro, and an `own` one Arabic like its base Gemini narrator.
//
// The gates' measures read the composition: probe reports each text element of
// the scenes mounted at a time, and the caption cue showing then, at 40 px in
// the content band with the palette's text on its bg, all in bounds. An
// element whose text names a marker word misrenders: `clipped` overflows
// (scrollW 4000 in 1600) past its clip box, and check reports it as a layout
// error `text_box_overflow`; `tiny` is 12 px; `dim` is #c8c8c0; `small` is 20 px
// in the palette's accent; `edge` sits at
// left 40, inside the safe margin; `stacked` starts halfway down the element
// before it, so the two overlap; `flaky` renders differently every time frame
// draws it; `fading` is mid-reveal until EXPLAINER_VIDEO_FAKE_FADE_END scene
// seconds. EXPLAINER_VIDEO_FAKE_BLANK=1 makes probe find no text at all, and
// EXPLAINER_VIDEO_FAKE_EVENTS (scene id to {ends, seams, camera}) is what
// events reads off the scenes' timelines.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";
export * from "./fake-backend-voice.mjs";
export * from "./fake-backend-media.mjs";
export * from "./fake-backend-gates.mjs";
export * from "./fake-backend-sources.mjs";

export async function npmCi(dir, env) {
  log({
    call: "npmCi",
    dir,
    onnxruntime: env.ONNXRUNTIME_NODE_INSTALL ?? null,
  });
  fs.mkdirSync(path.join(dir, "node_modules"), { recursive: true });
  fs.writeFileSync(path.join(dir, "node_modules", ".package-lock.json"), "{}");
  return 0;
}

export async function ensureChrome(nodeDir, home) {
  log({ call: "ensureChrome", nodeDir, home });
  fs.mkdirSync(path.join(home, ".cache", "hyperframes", "chrome"), {
    recursive: true,
  });
  fs.writeFileSync(
    path.join(home, ".cache", "hyperframes", "chrome", "chrome-headless-shell"),
    "x".repeat(1000),
  );
  return 0;
}

// Fontsource holds every family but `helvetica-neue` and `georgia`; a
// family's category is its entry in CATEGORY, else sans-serif.
const CATEGORY = {
  "source-serif-4": "serif",
  "noto-serif": "serif",
  "jetbrains-mono": "monospace",
};
export async function fontMeta(id) {
  log({ call: "fontMeta", id });
  if (["helvetica-neue", "georgia"].includes(id)) return null;
  return {
    id,
    category: CATEGORY[id] ?? "sans-serif",
    license: id === "ubuntu" ? "UFL-1.0" : "OFL-1.1",
    npmVersion: "5.3.0",
    weights: [400, 600],
    subsets: ["latin"],
    styles: ["normal"],
  };
}

export async function download(url, file) {
  log({ call: "download", url });
  fs.writeFileSync(file, "woff2");
}

// The CUDA provider's package extracts to its two library files.
export async function extractOrtCuda(nupkg, dir) {
  log({ call: "extractOrtCuda", nupkg, dir });
  fs.mkdirSync(dir, { recursive: true });
  for (const f of [
    "libonnxruntime_providers_cuda.so",
    "libonnxruntime_providers_shared.so",
  ])
    fs.writeFileSync(path.join(dir, f), "");
}

// EXPLAINER_VIDEO_FAKE_CUDA the reason the provider does not run (unset, it
// does).
export async function cudaProbe() {
  return process.env.EXPLAINER_VIDEO_FAKE_CUDA ?? null;
}

// A source archive extracts to a pyproject; uv sync leaves a .venv beside it.
export async function extract(zip, dir) {
  log({ call: "extract", zip, dir });
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "pyproject.toml"), "[project]\n");
}

export async function uvSync(dir) {
  log({ call: "uvSync", dir });
  fs.mkdirSync(path.join(dir, ".venv"), { recursive: true });
  return 0;
}

// ACE-Step's music: a tone the seed tunes, 48 kHz stereo, `seconds` long.
export async function aceStep({ dir, device, seconds, seed, caption }) {
  log({ call: "aceStep", dir, device, seconds, seed, caption });
  const exit = process.env.EXPLAINER_VIDEO_FAKE_ACE_EXIT;
  if (exit) throw new Error(`ace-step exited ${exit}`);
  const n = Math.round(seconds * 48000);
  const hz = 110 + (seed % 200);
  const L = Float32Array.from({ length: n }, (_, i) =>
    Math.sin((2 * Math.PI * hz * i) / 48000),
  );
  return { L, R: Float32Array.from(L) };
}

// The machine: EXPLAINER_VIDEO_FAKE_GPU a compute capability (unset, no NVIDIA
// card; `failed`, a probe that failed), EXPLAINER_VIDEO_FAKE_RAM its bytes of
// RAM (default 64 GB).
export async function computeCapability() {
  const cap = process.env.EXPLAINER_VIDEO_FAKE_GPU;
  if (cap === "failed") return undefined;
  return cap ? +cap : null;
}

// EXPLAINER_VIDEO_FAKE_NVENC `1`: ffmpeg encodes on NVENC (unset, it cannot).
export async function nvenc() {
  return process.env.EXPLAINER_VIDEO_FAKE_NVENC === "1";
}

export function memory() {
  return +(process.env.EXPLAINER_VIDEO_FAKE_RAM ?? 64e9);
}

// EXPLAINER_VIDEO_FAKE_PLATFORM `<os>/<arch>[/<macOS version>]` (default
// linux/x64).
export function platform() {
  const [os, arch, version = null] = (
    process.env.EXPLAINER_VIDEO_FAKE_PLATFORM ?? "linux/x64"
  ).split("/");
  return { os, arch, version };
}

export function which(cmd) {
  return (process.env.EXPLAINER_VIDEO_FAKE_PRESENT ?? "")
    .split(",")
    .includes(cmd)
    ? `/usr/bin/${cmd}`
    : null;
}
