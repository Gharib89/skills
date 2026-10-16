// The voice stage: narration audio per scene, every word timed, voice QC run.
//
//   node voice.mjs <run-folder>
//
// Reads <run>/script.json: { language, narrator?, scenes: [{ id, narration:
// [sentence, ...] }] }; the narrator defaults to the language's first default
// one in narrators.json; `own:<name>` is an own voice enrolled with
// own-voice.mjs. Each scene's audio and timings are cached in
// <run>/.cache/voice/ under the hash of its narration, narrator and language
// (ADR 0016), an own voice's also under its clip's hash. With no scene cached,
// the whole narration is one synthesis call, split per scene at the aligner's
// word times; otherwise each uncached scene is its own call. A scene failing
// voice QC is not cached. With <run>/brief.json, the voiced scenes and the
// render's closing hold must land within 10 percent of the brief's `length`.
// stdout: one line per scene, `voice <id>: voiced|cached · recall · precision ·
//         rate · pass|fail: <why>`, with a brief and every scene passing
//         `voice length: pass|fail: <measured> vs <wanted> ±10%`, then one
//         summary line
// writes: <run>/voice.json, the word timeline, only when every scene and the
//         length pass
// stderr: a Gemini or ElevenLabs narrator with no key (an own voice speaks
//         through Gemini), or an own voice with no consent record, is refused
//         before any synthesis; a quota stop counts the scenes kept
// exit:   0 every scene passes · 1 refused for its input or a missing key, a
//         scene fails QC, the length fails, a quota stop, or synthesis or
//         alignment failed ·
//         2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { OWN_PREFIX, narrator as findNarrator } from "../lib/narrators.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { catalogue, loadBackend, toolPaths } from "../lib/tools.mjs";
import { HOLD } from "../render/compose.mjs";
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
const narrator = findNarrator(script.narrator, language);
if (!narrator) {
  console.error(
    script.narrator?.startsWith(OWN_PREFIX)
      ? `voice: own voice ${script.narrator.slice(OWN_PREFIX.length)} is not enrolled with a consent record for its clip: enroll it (own-voice.mjs enroll) or choose another narrator in the brief`
      : `voice: no narrator ${script.narrator ?? "default"} for ${language}`,
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
    .update(
      JSON.stringify(
        narrator.clipHash
          ? [text, narrator.id, language, narrator.clipHash]
          : [text, narrator.id, language],
      ),
    )
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
// A Gemini or ElevenLabs narrator speaks only on the user's own key, its
// backend's key row in setup/rows.json: no other narrator stands in, since the
// brief chose this voice. An own voice speaks through its base narrator's.
const keyRow = catalogue().find(
  (r) =>
    r.kind === "key" &&
    r.backend === (narrator.base?.backend ?? narrator.backend),
);
if (missing.length && keyRow && !process.env[keyRow.env]) {
  console.error(
    `voice: narrator ${narrator.id} needs ${keyRow.env}: get a free key at ${keyRow.get}, or choose another narrator in the brief`,
  );
  process.exit(1);
}
// A repeat of a missing scene's narration takes its entry rather than a call
// of its own, which on Gemini is a request off the quota.
const groups =
  missing.length === scenes.length
    ? [missing]
    : missing
        .filter((s, i) => missing.findIndex((m) => m.key === s.key) === i)
        .map((s) => [s]);
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
  for (const s of missing) s.voiced ??= byKey.get(s.key);
} catch (e) {
  // Each group is cached as it passes, so a rerun voices only what is missing.
  if (e.quota)
    console.error(
      `voice: ${e.vendor} quota reached (${e.message}); ${kept} scene(s) voiced before it are kept. Voice again once the quota resets (tomorrow, for a daily quota), which voices only the missing scenes; use a paid key; or choose another narrator in the brief`,
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
// length: with a brief, the voiced scenes and the render's closing hold within
// 10 percent of the brief's length, which the script's budget only predicts.
const briefFile = path.join(run, "brief.json");
if (fs.existsSync(briefFile)) {
  const want = JSON.parse(fs.readFileSync(briefFile, "utf8")).length * 60;
  const voiced = scenes.reduce(
    (a, s) => a + (s.cached ?? s.voiced).duration,
    0,
  );
  const ok = Math.abs(voiced + HOLD - want) <= want * 0.1;
  console.log(
    `voice length: ${ok ? "pass" : `fail: the scenes voice ${voiced.toFixed(1)} s and the ${HOLD} s hold vs the brief's ${want} s ±10%`}`,
  );
  if (!ok) {
    console.log(`voice length failed; ${summary}`);
    process.exit(1);
  }
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
