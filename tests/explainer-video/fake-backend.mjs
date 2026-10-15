// The canned backend tests select with EXPLAINER_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $EXPLAINER_VIDEO_FAKE_LOG, so a test asserts on what setup asked for.
//   EXPLAINER_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
// The family `ubuntu` answers with its real, non-OFL licence.
//
// Fake audio is 16 kHz and spells its text: each letter holds 3 frames of 320
// samples (2 at the letter's vocabulary id / 100, 1 silent), each word ends on
// a `|` frame and 2 silent frames, each sentence on 10 more. The fake aligner
// reads a frame's id back from its first sample, so word timings come out of
// the real Viterbi pass. A sentence naming a marker word misrenders:
// `garbled` speaks every word as "mumble", `looped` speaks the sentence twice,
// `slowly` holds each letter 8 frames.
import fs from "node:fs";
import path from "node:path";

const log = (call) =>
  fs.appendFileSync(
    process.env.EXPLAINER_VIDEO_FAKE_LOG,
    JSON.stringify(call) + "\n",
  );

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

export async function fontMeta(id) {
  log({ call: "fontMeta", id });
  return {
    id,
    license: id === "ubuntu" ? "UFL-1.0" : "OFL-1.1",
    weights: [400, 600],
    subsets: ["latin"],
    styles: ["normal"],
  };
}

export async function download(url, file) {
  log({ call: "download", url });
  fs.writeFileSync(file, "woff2");
}

export function which(cmd) {
  return (process.env.EXPLAINER_VIDEO_FAKE_PRESENT ?? "")
    .split(",")
    .includes(cmd)
    ? `/usr/bin/${cmd}`
    : null;
}

const HOP = 320;
const VOCAB = Object.fromEntries(
  ["<pad>", "<s>", "</s>", "<unk>", "|", ..."ETAONIHSRDLUMWCFGYPBVK'XJQZ"].map(
    (c, i) => [c, i],
  ),
);

export async function synthesize({ text, narrator }) {
  log({ call: "synthesize", text, voice: narrator.voice });
  const frames = new Array(10).fill(0);
  for (const sentence of text.split(/(?<=[.!?])\s+/)) {
    let words = sentence.toUpperCase().match(/[A-Z']+/g) ?? [];
    const hold = /\bslowly\b/i.test(sentence) ? 8 : 2;
    if (/\bgarbled\b/i.test(sentence)) words = words.map(() => "MUMBLE");
    if (/\blooped\b/i.test(sentence)) words = [...words, ...words];
    for (const w of words) {
      for (const ch of w) frames.push(...new Array(hold).fill(VOCAB[ch]), 0);
      frames.push(VOCAB["|"], 0, 0);
    }
    frames.push(...new Array(10).fill(0));
  }
  const samples = new Float32Array(frames.length * HOP);
  frames.forEach((id, f) => samples.fill(id / 100, f * HOP, (f + 1) * HOP));
  return { samples, sampleRate: 16000 };
}

export async function aligner() {
  const classes = Object.keys(VOCAB).length;
  return {
    vocab: VOCAB,
    async logits(x) {
      const frames = Math.floor(x.length / HOP);
      const data = new Float32Array(frames * classes);
      for (let f = 0; f < frames; f++)
        data[f * classes + Math.round(x[f * HOP] * 100)] = 10;
      return { data, frames, classes };
    },
  };
}
