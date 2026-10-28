// The canned backend tests select with CREATIVE_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $CREATIVE_VIDEO_FAKE_LOG, so a test asserts on what a stage asked for.
//   CREATIVE_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
//   CREATIVE_VIDEO_FAKE_PROBE    JSON fields overriding what ffprobe answers
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
// same way in the Egyptian aligner's vocabulary (see gemini in
// fake-backend-voice.mjs), and
//   CREATIVE_VIDEO_FAKE_QUOTA  a Gemini or ElevenLabs call throws its vendor's
//                              quota error once this many synthesize calls
//                              are in the log; with CREATIVE_VIDEO_FAKE_CREDITS
//                              set it is the spent-credits 402 instead
// geminiKey refuses the key `bad-key` as API_KEY_INVALID and takes any other;
// elevenlabsKey refuses it as invalid_api_key. An `elevenlabs` narrator speaks
// English like Kokoro.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";
export * from "./fake-backend-voice.mjs";
export * from "./fake-backend-media.mjs";
export * from "./fake-backend-sources.mjs";
export * from "./fake-backend-gates.mjs";
export * from "./fake-backend-sound.mjs";

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

// A URL under /dead/ answers HTTP 404, as the real download throws.
export async function download(url, file) {
  log({ call: "download", url });
  if (url.includes("/dead/")) throw new Error(`${url}: HTTP 404`);
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

// CREATIVE_VIDEO_FAKE_CUDA the reason the provider does not run (unset, it
// does).
export async function cudaProbe() {
  return process.env.CREATIVE_VIDEO_FAKE_CUDA ?? null;
}

// The machine: CREATIVE_VIDEO_FAKE_GPU a compute capability (unset, no NVIDIA
// card; `failed`, a probe that failed).
export async function computeCapability() {
  const cap = process.env.CREATIVE_VIDEO_FAKE_GPU;
  if (cap === "failed") return undefined;
  return cap ? +cap : null;
}

// CREATIVE_VIDEO_FAKE_PLATFORM `<os>/<arch>` (default linux/x64).
export function platform() {
  const [os, arch] = (
    process.env.CREATIVE_VIDEO_FAKE_PLATFORM ?? "linux/x64"
  ).split("/");
  return { os, arch };
}

export function which(cmd) {
  return (process.env.CREATIVE_VIDEO_FAKE_PRESENT ?? "")
    .split(",")
    .includes(cmd)
    ? `/usr/bin/${cmd}`
    : null;
}
