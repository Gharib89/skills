// The backend's voice tools: the narration engines and the aligners.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { sentences } from "../length.mjs";
import { skill, toolPaths, torchDevice } from "../tools.mjs";
import { fromCache, ffmpeg, quiet, sampleRate, which } from "./common.mjs";

const GEMINI = "https://generativelanguage.googleapis.com/v1beta";
const GEMINI_TTS = "gemini-3.8-flash-tts";

// A Gemini answer's error message: its JSON's, else its text. A rate or daily
// limit answers 429; spent prepaid credits answer 402
// (https://ai.google.dev/gemini-api/docs/troubleshooting) with `error.status:
// "RESOURCE_EXHAUSTED"`, a body seen live but not in the docs.
async function geminiError(r) {
  const body = await r.text();
  let error = {};
  try {
    error = JSON.parse(body).error ?? {};
  } catch {}
  return Object.assign(
    new Error(`Gemini answered HTTP ${r.status}: ${error.message ?? body}`),
    {
      quota:
        r.status === 429 ||
        (r.status === 402 && error.status === "RESOURCE_EXHAUSTED"),
      vendor: "Gemini",
    },
  );
}

// Gemini TTS on the user's key, the whole text in one Interactions call; its
// audio is 16-bit little-endian PCM, mono, 24 kHz, split across content items.
async function gemini(text, narrator) {
  const r = await fetch(`${GEMINI}/interactions`, {
    method: "POST",
    headers: {
      "x-goog-api-key": process.env.GEMINI_API_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: GEMINI_TTS,
      input: [
        {
          type: "user_input",
          content: [
            {
              type: "text",
              text,
              annotations: [{ type: "speech_metadata", style: narrator.style }],
            },
          ],
        },
      ],
      response_format: {
        type: "audio",
        mime_type: "audio/l16",
        sample_rate: 24000,
      },
      generation_config: { speech_config: [{ voice: narrator.voice }] },
    }),
  });
  if (r.status !== 200) throw await geminiError(r);
  const pcm = Buffer.concat(
    (await r.json()).steps
      .flatMap((s) => s.content ?? [])
      .filter((c) => c.type === "audio")
      .map((c) => Buffer.from(c.data, "base64")),
  );
  const samples = new Float32Array(pcm.length >> 1);
  for (let i = 0; i < samples.length; i++)
    samples[i] = pcm.readInt16LE(2 * i) / 32768;
  return { samples, sampleRate: 24000 };
}

// Whether Google takes `key`, read from the TTS model's metadata so no TTS
// request is spent. Nothing tells a free-tier key from a paid one.
export async function geminiKey(key) {
  const r = await fetch(`${GEMINI}/models/${GEMINI_TTS}`, {
    headers: { "x-goog-api-key": key },
  });
  if (r.status === 200) return { ok: true };
  const error = (await r.json().catch(() => ({}))).error;
  return {
    ok: false,
    reason: error?.details?.[0]?.reason ?? error?.status ?? `HTTP ${r.status}`,
  };
}

const ELEVENLABS = "https://api.elevenlabs.io/v1";

// An ElevenLabs answer's error message: its JSON's detail, else its text. Spent
// credits answer 402 with `detail.code: "insufficient_credits"`
// (https://elevenlabs.io/docs/eleven-api/resources/errors); the legacy answer,
// 400 or 401 with `detail.status: "quota_exceeded"`, is still read
// (https://elevenlabs.io/docs/help-center/technical/api-error-code-400-or-401).
async function elevenlabsError(r) {
  const body = await r.text();
  let detail = {};
  try {
    detail = JSON.parse(body).detail ?? {};
  } catch {}
  return Object.assign(
    new Error(
      `ElevenLabs answered HTTP ${r.status}: ${detail.message ?? body}`,
    ),
    {
      quota:
        detail.code === "insufficient_credits" ||
        detail.status === "quota_exceeded",
      vendor: "ElevenLabs",
    },
  );
}

// ElevenLabs TTS on the user's key; the audio is raw 16-bit little-endian PCM,
// mono, 24 kHz.
async function elevenlabs(text, narrator) {
  const r = await fetch(
    `${ELEVENLABS}/text-to-speech/${narrator.voice}?output_format=pcm_24000`,
    {
      method: "POST",
      headers: {
        "xi-api-key": process.env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({ text, model_id: "eleven_multilingual_v2" }),
    },
  );
  if (r.status !== 200) throw await elevenlabsError(r);
  const pcm = Buffer.from(await r.arrayBuffer());
  const samples = new Float32Array(pcm.length >> 1);
  for (let i = 0; i < samples.length; i++)
    samples[i] = pcm.readInt16LE(2 * i) / 32768;
  return { samples, sampleRate: 24000 };
}

// Whether ElevenLabs takes `key`, read from the narrator's voice metadata so no
// credits are spent; a bad key answers `detail.code` (legacy `detail.status`)
// `invalid_api_key`.
export async function elevenlabsKey(key, voice) {
  const r = await fetch(`${ELEVENLABS}/voices/${voice}`, {
    headers: { "xi-api-key": key },
  });
  if (r.status === 200) return { ok: true };
  if (r.status === 401 || r.status === 403) {
    const detail = (await r.json().catch(() => ({}))).detail;
    return {
      ok: false,
      reason: detail?.code ?? detail?.status ?? `HTTP ${r.status}`,
    };
  }
  throw await elevenlabsError(r);
}

// An enrolled clip as 16-bit PCM, 24 kHz, mono WAV, whatever ffmpeg reads.
export async function voiceClip(input, output) {
  ffmpeg([
    "-y",
    "-i",
    input,
    "-ac",
    "1",
    "-ar",
    "24000",
    "-c:a",
    "pcm_s16le",
    "-f",
    "wav",
    output,
  ]);
}

// A narrator's render converted to an own voice's clip by Chatterbox VC:
// scripts/voice/vc/vc.py under uv in the own-voice row's folder.
async function ownVoice(text, narrator, tools) {
  const { samples, sampleRate } = await synthesize({
    text,
    narrator: narrator.base,
    tools,
  });
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "own-voice-"));
  try {
    const inRaw = path.join(tmp, "in.f32");
    const inWav = path.join(tmp, "in.wav");
    const outWav = path.join(tmp, "out.wav");
    fs.writeFileSync(
      inRaw,
      Buffer.from(samples.buffer, samples.byteOffset, samples.byteLength),
    );
    ffmpeg([
      "-y",
      "-f",
      "f32le",
      "-ar",
      String(sampleRate),
      "-ac",
      "1",
      "-i",
      inRaw,
      inWav,
    ]);
    const dir = tools.ownVoice;
    const device = torchDevice(await computeCapability());
    const r = spawnSync(
      "uv",
      [
        "run",
        "--frozen",
        "--no-sync",
        "python",
        path.join(skill, "scripts", "voice", "vc", "vc.py"),
        path.join(dir, "checkpoints"),
        device,
        inWav,
        narrator.clip,
        outWav,
      ],
      { cwd: path.join(dir, "src"), stdio: quiet },
    );
    if (r.status !== 0)
      throw new Error(`chatterbox exited ${r.status ?? r.error?.message}`);
    const raw = path.join(tmp, "out.f32");
    ffmpeg([
      "-y",
      "-i",
      outWav,
      "-ar",
      "24000",
      "-ac",
      "1",
      "-f",
      "f32le",
      raw,
    ]);
    const f = fs.readFileSync(raw);
    return {
      samples: new Float32Array(
        f.buffer.slice(f.byteOffset, f.byteOffset + f.length),
      ),
      sampleRate: 24000,
    };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// Kokoro reads at most 510 phoneme tokens a call, and kokoro-js truncates past
// that without a word, so the adapter packs whole sentences into each call
// under this budget, counted with kokoro-js's own phonemizer; the headroom
// covers the normalisation kokoro-js applies before it phonemizes.
const KOKORO_TOKENS = 400;

// A narrator adapter: text in, audio out, never timings (ADR 0016). Kokoro
// voices each call's lead and tail silence, so one call per sentence paces
// narration slower than the voice speaks.
let kokoro;
export async function synthesize({ text, narrator, tools }) {
  if (narrator.backend === "gemini") return gemini(text, narrator);
  if (narrator.backend === "elevenlabs") return elevenlabs(text, narrator);
  if (narrator.backend === "own") return ownVoice(text, narrator, tools);
  if (narrator.backend !== "kokoro")
    throw new Error(`no adapter for backend ${narrator.backend}`);
  const req = fromCache(tools.node);
  const { KokoroTTS } = req("kokoro-js");
  if (!kokoro) {
    // kokoro-js's own dependency, pinned by the lock: requiring it from the same
    // install yields the instance kokoro-js reads its settings from.
    const { env } = req("@huggingface/transformers");
    env.allowRemoteModels = false;
    // An absolute path is read as a folder; a name under localModelPath must
    // pass the hub's model-id check, which the `@` in the cache name fails.
    kokoro = await KokoroTTS.from_pretrained(tools.models["model:kokoro-82m"], {
      dtype: "fp32",
      device: "cpu",
    });
  }
  // kokoro-js's dependency again, phonemizing as it does: American voices
  // (`a…`) in en-us, British ones in en.
  const { phonemize } = req("phonemizer");
  const lang = narrator.voice.startsWith("a") ? "en-us" : "en";
  const count = async (s) => (await phonemize(s, lang)).join(" ").length;
  // A sentence over the budget breaks between words, at the last that fits.
  const units = [];
  for (const s of sentences(text.trim())) {
    if ((await count(s)) <= KOKORO_TOKENS) {
      units.push(s);
      continue;
    }
    let piece = "";
    for (const w of s.split(/\s+/)) {
      const next = piece ? `${piece} ${w}` : w;
      if (piece && (await count(next)) > KOKORO_TOKENS) {
        units.push(piece);
        piece = w;
      } else piece = next;
    }
    units.push(piece);
  }
  const calls = [];
  for (const u of units) {
    const n = await count(u);
    const last = calls.at(-1);
    if (last && last.n + 1 + n <= KOKORO_TOKENS)
      Object.assign(last, { text: `${last.text} ${u}`, n: last.n + 1 + n });
    else calls.push({ text: u, n });
  }
  const parts = [];
  for (const c of calls)
    parts.push(
      (await kokoro.generate(c.text, { voice: narrator.voice })).audio,
    );
  const samples = new Float32Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((o, p) => (samples.set(p, o), o + p.length), 0);
  return { samples, sampleRate: 24000 };
}

// One CTC model per language (ADR 0016).
const ALIGNERS = {
  en: "model:wav2vec2-base-960h",
  ar: "model:egyptian-arabic-wav2vec2",
};

// A language's CTC model: its vocabulary, and its logits for 16 kHz audio,
// normalised as its feature extractor does.
export async function aligner({ language, tools }) {
  if (!ALIGNERS[language])
    throw new Error(`no aligner for language ${language}`);
  const dir = tools.models[ALIGNERS[language]];
  const ort = fromCache(tools.node)("onnxruntime-node");
  const session = await ort.InferenceSession.create(
    path.join(dir, "onnx", "model_int8.onnx"),
  );
  const vocab = JSON.parse(
    fs.readFileSync(path.join(dir, "vocab.json"), "utf8"),
  );
  async function logits(x) {
    let mean = 0;
    for (const v of x) mean += v;
    mean /= x.length;
    let sq = 0;
    for (const v of x) sq += (v - mean) ** 2;
    const sd = Math.sqrt(sq / x.length + 1e-7);
    const input = new ort.Tensor(
      "float32",
      x.map((v) => (v - mean) / sd),
      [1, x.length],
    );
    const out = (await session.run({ [session.inputNames[0]]: input }))[
      session.outputNames[0]
    ];
    return { data: out.data, frames: out.dims[1], classes: out.dims[2] };
  }
  return { vocab, logits };
}
