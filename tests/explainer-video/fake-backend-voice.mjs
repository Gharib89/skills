// Canned narration: the fake aligner and the Gemini, ElevenLabs and own-voice
// narrators, speaking text as frames of its letters' ids.
import fs from "node:fs";
import { log } from "./fake-backend-log.mjs";

const HOP = 320;
const VOCAB = Object.fromEntries(
  ["<pad>", "<s>", "</s>", "<unk>", "|", ..."ETAONIHSRDLUMWCFGYPBVK'XJQZ"].map(
    (c, i) => [c, i],
  ),
);
// The Egyptian Arabic aligner's vocabulary as its vocab.json holds it: `|` is
// 0, `[PAD]` (40) the blank, and the model's logits carry two classes more.
const AR_VOCAB = Object.fromEntries([
  ["|", 0],
  ..."ءآأإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيڨیﻻ"
    .split("")
    .map((c, i) => [c, i + 1]),
  ["[UNK]", 39],
  ["[PAD]", 40],
]);
const AR_CLASSES = 43;

// English terms as an Egyptian speaker says them, not as any rule spells them.
const SAID = {
  pull: "بول",
  request: "ريكويست",
  branch: "برانش",
  git: "جيت",
  ci: "سي اي",
  review: "ريفيو",
  merge: "ميرج",
  profile: "بروفايل",
  issue: "ايشو",
  agent: "ايجنت",
  ship: "شيب",
  github: "جيثوب",
  actions: "اكتيونس",
  commit: "كوميت",
  diff: "ديف",
  dry: "دراي",
  run: "رن",
  main: "مين",
  old: "اولد",
  push: "بوش",
  tidy: "تايدي",
  trash: "تراش",
};

const synthCalls = () =>
  fs.existsSync(process.env.EXPLAINER_VIDEO_FAKE_LOG)
    ? fs
        .readFileSync(process.env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
        .split("\n")
        .filter((l) => l.includes('"call":"synthesize"')).length
    : 0;

const toSamples = (frames) => {
  const samples = new Float32Array(frames.length * HOP);
  frames.forEach((id, f) => samples.fill(id / 100, f * HOP, (f + 1) * HOP));
  return { samples, sampleRate: 16000 };
};

// The vendor's quota error once EXPLAINER_VIDEO_FAKE_QUOTA calls are logged.
function quota(vendor, message) {
  const at = process.env.EXPLAINER_VIDEO_FAKE_QUOTA;
  if (at && synthCalls() >= +at)
    throw Object.assign(
      new Error(
        process.env.EXPLAINER_VIDEO_FAKE_CREDITS
          ? `${vendor} answered HTTP 402: credits are depleted`
          : message,
      ),
      { quota: true, vendor },
    );
}

// A Gemini narrator speaks Arabic in the Arabic vocabulary's ids, blanks as
// `[PAD]`; its markers are مشوش (every word ممم), مكرر (the sentence twice) and
// ببطء (each letter held 8 frames).
function gemini(text, entry) {
  quota("Gemini", "Gemini answered HTTP 429: You exceeded your current quota");
  log({ call: "synthesize", ...entry, text });
  const pad = AR_VOCAB["[PAD]"];
  const clean = text.normalize("NFKC").replace(/[ً-ْٰـ]/g, "");
  const frames = new Array(10).fill(pad);
  for (const sentence of clean.split(/(?<=[.!?؟])\s+/)) {
    let words = (sentence.match(/[ء-ي]+|[A-Za-z]+/g) ?? []).flatMap((w) => {
      if (!/[A-Za-z]/.test(w)) return [w];
      if (!SAID[w.toLowerCase()])
        throw new Error(`the fake cannot say ${w}: add it to SAID`);
      return SAID[w.toLowerCase()].split(" ");
    });
    const hold = sentence.includes("ببطء") ? 8 : 2;
    if (sentence.includes("مشوش")) words = words.map(() => "ممم");
    if (sentence.includes("مكرر")) words = [...words, ...words];
    for (const w of words) {
      for (const ch of w)
        frames.push(...new Array(hold).fill(AR_VOCAB[ch]), pad);
      frames.push(AR_VOCAB["|"], pad, pad);
    }
    frames.push(...new Array(10).fill(pad));
  }
  return toSamples(frames);
}

// A key check that spends no TTS request; the key itself is never logged.
export async function geminiKey(key) {
  log({ call: "geminiKey" });
  return key === "bad-key"
    ? { ok: false, reason: "API_KEY_INVALID" }
    : { ok: true };
}

// A key check that spends no credits.
export async function elevenlabsKey(key, voice) {
  log({ call: "elevenlabsKey", voice });
  return key === "bad-key"
    ? { ok: false, reason: "invalid_api_key" }
    : { ok: true };
}

// A 16-bit 24 kHz mono WAV of the clip's length, its samples a function of the
// input file's bytes: two inputs give two clips.
export async function voiceClip(input, output) {
  log({ call: "voiceClip" });
  const bytes = fs.readFileSync(input);
  const n = +(process.env.EXPLAINER_VIDEO_FAKE_CLIP_SECONDS ?? 12) * 24000;
  const b = Buffer.alloc(44 + n * 2);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(36 + n * 2, 4);
  b.write("WAVEfmt ", 8, "ascii");
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(24000, 24);
  b.writeUInt32LE(48000, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write("data", 36, "ascii");
  b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++)
    b.writeInt16LE(
      ((bytes[i % bytes.length] * 131 + i) % 2001) - 1000,
      44 + i * 2,
    );
  fs.writeFileSync(output, b);
}

export async function synthesize({ text, narrator, tools }) {
  if (narrator.backend === "gemini")
    return gemini(text, { backend: "gemini", voice: narrator.voice });
  if (narrator.backend === "own")
    return gemini(text, {
      backend: "own",
      base: narrator.base.id,
      clipHash: narrator.clipHash,
    });
  // ElevenLabs' message for a spent quota (docs changelog 2025-05-05).
  if (narrator.backend === "elevenlabs")
    quota(
      "ElevenLabs",
      "ElevenLabs answered HTTP 401: This request exceeds your quota limit",
    );
  log(
    narrator.backend === "elevenlabs"
      ? {
          call: "synthesize",
          backend: "elevenlabs",
          voice: narrator.voice,
          text,
        }
      : {
          call: "synthesize",
          text,
          voice: narrator.voice,
          model: tools.models["model:kokoro-82m"],
        },
  );
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
  return toSamples(frames);
}

export async function aligner({ language }) {
  const vocab = language === "ar" ? AR_VOCAB : VOCAB;
  const classes = language === "ar" ? AR_CLASSES : Object.keys(VOCAB).length;
  return {
    vocab,
    async logits(x) {
      const frames = Math.floor(x.length / HOP);
      const data = new Float32Array(frames * classes);
      for (let f = 0; f < frames; f++)
        data[f * classes + Math.round(x[f * HOP] * 100)] = 10;
      return { data, frames, classes };
    },
  };
}
