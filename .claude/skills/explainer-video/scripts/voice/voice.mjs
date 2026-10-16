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
// stderr: a Gemini narrator with no GEMINI_API_KEY is refused before any
//         synthesis; a Gemini quota stop (HTTP 429) names the scenes kept
// exit:   0 every scene passes · 1 refused for its input or a missing key, a
//         scene fails QC, a quota stop, or synthesis or alignment failed ·
//         2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";
import { loadBackend, skill, toolPaths } from "../lib/tools.mjs";
import { FRAME, align, transcribe } from "./align.mjs";
import { check } from "./qc.mjs";

const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node voice.mjs <run-folder>");
  process.exit(2);
}
// The last pass's timeline no longer describes this script until it passes.
fs.rmSync(path.join(run, "voice.json"), { force: true });
if (!fs.existsSync(path.join(run, "script.json"))) {
  console.error(
    "voice: no script.json: run the compile stage first (script/compile.mjs)",
  );
  process.exit(1);
}
const script = JSON.parse(
  fs.readFileSync(path.join(run, "script.json"), "utf8"),
);
writeIgnore(run);
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
  console.error(
    `voice: no narrator ${script.narrator ?? "default"} for ${language}`,
  );
  process.exit(1);
}
const empty = script.scenes.find((s) => !s.narration?.join("").trim());
if (empty) {
  console.error(`voice: scene ${empty.id} has no narration`);
  process.exit(1);
}

const tools = toolPaths();
const backend = await loadBackend();

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
  // The WAV is written before its metadata, but either can be deleted by hand.
  const hit =
    fs.existsSync(meta) && fs.existsSync(path.join(cacheDir, `${key}.wav`));
  return {
    id: s.id,
    text,
    words: text.split(/\s+/),
    key,
    cached: hit ? JSON.parse(fs.readFileSync(meta, "utf8")) : null,
  };
});

// Synthesise `group`'s narration in one call, align it, and cut it into one
// result per scene at the midpoints of the gaps between scenes.
async function voice(group, ctc) {
  const { samples, sampleRate } = await backend.synthesize({
    text: group.map((s) => s.text).join(" "),
    narrator,
    language,
    tools,
  });
  const { em, words } = await align(
    samples,
    sampleRate,
    group.flatMap((s) => s.words),
    ctc,
  );
  const total = samples.length / sampleRate;
  let first = 0;
  let cut = 0;
  return group.map((s) => {
    const own = words.slice(first, first + s.words.length);
    first += s.words.length;
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
        language,
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
// A Gemini narrator speaks only on the user's own key: no other narrator
// stands in, since the brief chose this voice.
if (
  missing.length &&
  narrator.backend === "gemini" &&
  !process.env.GEMINI_API_KEY
) {
  console.error(
    `voice: narrator ${narrator.id} needs GEMINI_API_KEY: get a free key at https://aistudio.google.com/apikey, or choose another narrator in the brief`,
  );
  process.exit(1);
}
const groups =
  missing.length === scenes.length ? [missing] : missing.map((s) => [s]);
let failed = 0;
// Scenes with the same narration share a cache key and so one WAV: the first
// slice voiced is the one written, and a repeat takes its entry.
const byKey = new Map();
let kept = 0;
try {
  // Every scene cached needs no model.
  const ctc = groups.length ? await backend.aligner({ language, tools }) : null;
  for (const g of groups)
    for (const v of await voice(g, ctc)) {
      if (byKey.has(v.scene.key)) {
        v.scene.voiced = byKey.get(v.scene.key);
        continue;
      }
      const entry = {
        audio: path.join(".cache", "voice", `${v.scene.key}.wav`),
        duration: +(v.samples.length / v.sampleRate).toFixed(3),
        words: v.words,
        qc: v.qc,
      };
      v.scene.voiced = entry;
      byKey.set(v.scene.key, entry);
      if (v.qc.failures.length) continue;
      wav(path.join(run, entry.audio), v.samples, v.sampleRate);
      fs.writeFileSync(
        path.join(cacheDir, `${v.scene.key}.json`),
        JSON.stringify(entry),
      );
      kept++;
    }
} catch (e) {
  // Each group is cached as it passes, so a rerun voices only what is missing.
  if (e.quota)
    console.error(
      `voice: Gemini quota reached (HTTP 429); ${kept} scene(s) voiced before it are kept. Resume tomorrow (voicing again voices only the missing scenes), use a paid key, or choose another narrator in the brief`,
    );
  else console.error(`voice: ${e.message}`);
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
