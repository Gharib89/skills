// The voice stage: narration audio per scene, every word timed, voice QC run.
//
//   node voice.mjs <run-folder>
//
// Reads <run>/script.json: { language, narrator?, scenes: [{ id, narration:
// [sentence, ...] }] }; the narrator defaults to the language's first default
// one in narrators.json. Each scene's audio and timings are cached in
// <run>/.cache/voice/ under the hash of its narration, narrator and language
// (ADR 0016). With no scene cached, the whole narration is one synthesis call,
// split per scene at the aligner's word times; otherwise each uncached scene
// is its own call. A scene failing voice QC is not cached.
// stdout: one line per scene, `voice <id>: voiced|cached · recall · precision ·
//         rate · pass|fail: <why>`, then one summary line
// writes: <run>/voice.json, the word timeline, only when every scene passes
// exit:   0 every scene passes · 1 a scene fails QC, or synthesis or alignment
//         failed · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { loadBackend, skill, toolPaths } from "../lib/tools.mjs";
import {
  FRAME,
  RATE,
  forceAlign,
  logProbs,
  resample,
  transcribe,
} from "./align.mjs";
import { check } from "./qc.mjs";

const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node voice.mjs <run-folder>");
  process.exit(2);
}

// One aligner per language; Arabic arrives with its own row.
const ALIGNERS = { en: "model:wav2vec2-base-960h" };

const script = JSON.parse(
  fs.readFileSync(path.join(run, "script.json"), "utf8"),
);
const language = script.language ?? "en";
const narrators = JSON.parse(
  fs.readFileSync(path.join(skill, "narrators.json"), "utf8"),
).narrators;
const narrator = narrators.find((n) =>
  script.narrator
    ? n.id === script.narrator
    : n.language === language && n.default,
);
if (!narrator) {
  console.error(`no narrator ${script.narrator ?? "default"} for ${language}`);
  process.exit(1);
}
if (!ALIGNERS[language]) {
  console.error(`no aligner for language ${language}`);
  process.exit(1);
}

const tools = toolPaths();
const backend = await loadBackend();
const ctc = await backend.aligner({ language, tools });

const cacheDir = path.join(run, ".cache", "voice");
fs.mkdirSync(cacheDir, { recursive: true });
const scenes = script.scenes.map((s) => {
  const text = s.narration.join(" ");
  const key = crypto
    .createHash("sha256")
    .update(JSON.stringify([text, narrator.id, language]))
    .digest("hex")
    .slice(0, 16);
  const meta = path.join(cacheDir, `${key}.json`);
  return {
    id: s.id,
    text,
    key,
    cached: fs.existsSync(meta)
      ? JSON.parse(fs.readFileSync(meta, "utf8"))
      : null,
  };
});

// Synthesise `group`'s narration in one call, align it, and cut it into one
// result per scene at the midpoints of the gaps between scenes.
async function voice(group) {
  const { samples, sampleRate } = await backend.synthesize({
    text: group.map((s) => s.text).join(" "),
    narrator,
    language,
    tools,
  });
  const em = await logProbs(resample(samples, sampleRate, RATE), ctc.logits);
  const counts = group.map((s) => s.text.split(/\s+/).length);
  const words = forceAlign(
    em,
    group.flatMap((s) => s.text.split(/\s+/)),
    ctc.vocab,
  );
  const total = samples.length / sampleRate;
  let first = 0;
  let cut = 0;
  return group.map((s, i) => {
    const own = words.slice(first, first + counts[i]);
    first += counts[i];
    const next = words[first];
    const end = next ? (own.at(-1).end + next.start) / 2 : total;
    const start = cut;
    cut = end;
    const from = Math.round(start * sampleRate);
    const to = Math.round(end * sampleRate);
    return {
      scene: s,
      samples: samples.subarray(from, to),
      sampleRate,
      words: own.map((w) => ({
        text: w.text,
        start: +(w.start - start).toFixed(3),
        end: +(w.end - start).toFixed(3),
      })),
      qc: check(
        s.text,
        transcribe(
          em,
          ctc.vocab,
          Math.floor(start / FRAME),
          Math.floor(end / FRAME),
        ),
        own.at(-1).end - own[0].start,
      ),
    };
  });
}

// 16-bit PCM mono.
function wav(file, samples, rate) {
  const b = Buffer.alloc(44 + samples.length * 2);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(36 + samples.length * 2, 4);
  b.write("WAVEfmt ", 8, "ascii");
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write("data", 36, "ascii");
  b.writeUInt32LE(samples.length * 2, 40);
  samples.forEach((v, i) =>
    b.writeInt16LE(
      Math.round(Math.max(-1, Math.min(1, v)) * 32767),
      44 + i * 2,
    ),
  );
  fs.writeFileSync(file, b);
}

const missing = scenes.filter((s) => !s.cached);
const groups =
  missing.length === scenes.length ? [missing] : missing.map((s) => [s]);
let failed = 0;
try {
  for (const g of groups)
    for (const v of await voice(g)) {
      const entry = {
        audio: path.join(".cache", "voice", `${v.scene.key}.wav`),
        duration: +(v.samples.length / v.sampleRate).toFixed(3),
        words: v.words,
        qc: v.qc,
      };
      v.scene.voiced = entry;
      if (v.qc.failures.length) continue;
      wav(path.join(run, entry.audio), v.samples, v.sampleRate);
      fs.writeFileSync(
        path.join(cacheDir, `${v.scene.key}.json`),
        JSON.stringify(entry),
      );
    }
} catch (e) {
  console.error(`voice: ${e.message}`);
  process.exit(1);
}

for (const s of scenes) {
  const e = s.cached ?? s.voiced;
  const q = e.qc;
  const verdict = q.failures.length ? `fail: ${q.failures.join("; ")}` : "pass";
  if (q.failures.length) failed++;
  console.log(
    `voice ${s.id}: ${s.cached ? "cached" : "voiced"} · recall ${q.recall} · precision ${q.precision} · rate ${q.rate} chars/s · ${verdict}`,
  );
}
const calls = groups.length;
const summary = `${scenes.length} scene(s), ${missing.length} voiced in ${calls} call(s), ${scenes.length - missing.length} cached`;
if (failed) {
  console.log(`voice QC failed: ${failed} scene(s); ${summary}`);
  process.exit(1);
}
fs.writeFileSync(
  path.join(run, "voice.json"),
  JSON.stringify(
    {
      narrator: narrator.id,
      language,
      scenes: scenes.map((s) => ({ id: s.id, ...(s.cached ?? s.voiced) })),
    },
    null,
    2,
  ) + "\n",
);
console.log(`voice QC pass: ${summary}`);
