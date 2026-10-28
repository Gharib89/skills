// The voice stage: narration audio per scene, every word timed, voice QC run.
//
//   node voice.mjs <run-folder>
//
// Reads <run>/script.json: { language, narrator?, scenes: [{ id, narration:
// [sentence, ...], roles? }] }, and <run>/project/kit/cast.json when the
// script names roles (lib/kit.mjs); the narrator defaults to the language's
// first default one in narrators.json. Each scene's audio and timings are
// cached in <run>/.cache/voice/ under the hash of its narration, each run's
// voice and style, and language (ADR 0016). With no scene cached, the whole
// narration is voiced at once, otherwise each uncached scene alone: one
// synthesis call per run of consecutive sentences one role speaks, the calls
// joined in order, aligned once and split per scene at the aligner's word
// times. A scene failing
// voice QC is not cached. Once every scene passes, with <run>/brief.json, the
// voiced scenes and the render's closing hold must land within 10 percent of
// the brief's `length`.
// stdout: one line per scene, `voice <id>: voiced|cached · recall · precision ·
//         rate · pass` or `... · fail: <why>; heard: <file>`, that file
//         (relative to the run folder) holding what the aligner heard; once
//         every scene passes, with a brief,
//         `voice length: pass|fail: the scenes voice <s> s (<id> <s> s, ...)
//         and the <hold> s hold vs the brief's <s> s ±10%`; then one summary
//         line
// writes: <run>/voice.json, the word timeline with each sentence's speaker,
//         only when every scene and the
//         length pass; <run>/.cache/voice/<key>.heard.txt per voiced scene
// stderr: a narrator with no calibrated rate, or a Gemini or ElevenLabs
//         narrator with no key, is refused before any synthesis; a quota stop
//         counts the scenes kept
// exit:   0 every scene and the length pass · 1 refused for its input or a
//         missing key, a scene fails QC, the length fails, a quota stop, or
//         synthesis or alignment failed · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { maybeJson, readJson } from "../lib/json.mjs";
import { speakers, voices, voicesOf } from "../lib/kit.mjs";
import { HOLD, fitsLength } from "../lib/length.mjs";
import { narrator as findNarrator } from "../lib/narrators.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { catalogue, loadBackend, toolPaths } from "../lib/tools.mjs";
import { FRAME, align, transcribe } from "./align.mjs";
import { check } from "./qc.mjs";

stage("voice");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node voice.mjs <run-folder>");
  process.exit(2);
}
// The last pass's timeline no longer describes this script until it passes.
fs.rmSync(path.join(run, "voice.json"), { force: true });
if (!fs.existsSync(path.join(run, "script.json"))) {
  console.error(
    "voice: no script.json: write it first (reference/voice.md gives its shape)",
  );
  process.exit(1);
}
const script = readJson(run, "script.json");
// Read before any synthesis, so a malformed brief costs no voicing.
const brief = maybeJson(run, "brief.json");
writeIgnore(run);
const { language } = script;
// Each role's narrator, the narrator role's first.
const cast = voices(run, script);
const narrator = cast.narrator;
// A narrator new to narrators.json carries a null rate until calibrated, and a
// script budgeted at none would be cut to NaN.
for (const n of Object.values(cast))
  if (!Number.isFinite(n.rate)) {
    console.error(
      `voice: narrator ${n.id} has no calibrated rate; run maintainer/calibrate-rates.mjs ${language} ${n.id}`,
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
// What the aligner heard of a voiced scene, kept pass or fail, so a QC failure
// can be read word by word against the narration.
const heardFile = (key) => path.join(cacheDir, `${key}.heard.txt`);
// `sentences` ({ role, text }) as runs: consecutive sentences of one role
// joined, each one synthesis call in its role's voice.
const runsOf = (sentences) =>
  sentences.reduce((runs, { role, text }) => {
    const last = runs.at(-1);
    if (last?.role === role) last.text += ` ${text}`;
    else runs.push({ role, text });
    return runs;
  }, []);
const scenes = script.scenes.map((s) => {
  const text = s.narration.join(" ");
  const roles = speakers(s);
  const sentences = s.narration.map((t, i) => ({ role: roles[i], text: t }));
  const runs = runsOf(sentences).map((r) => ({ ...r, n: cast[r.role] }));
  // A scene one voice speaks in its narrators.json style keys as it did before
  // the cast, so a cache voiced then stays a hit.
  const plain =
    runs.length === 1 &&
    runs[0].n.style === findNarrator(runs[0].n.id, language).style;
  const key = crypto
    .createHash("sha256")
    .update(
      JSON.stringify(
        plain
          ? [text, runs[0].n.id, language]
          : [runs.map((r) => [r.text, r.n.id, r.n.style]), language],
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
    roles,
    sentences,
    key,
    cached: hit ? JSON.parse(fs.readFileSync(meta, "utf8")) : null,
  };
});

// Synthesise `group`'s narration one run at a time, the runs joined end to end
// so no two lines overlap, align it once, and cut it into one result per scene
// at the midpoints of the gaps between scenes.
async function voice(group, ctc) {
  const parts = [];
  for (const r of runsOf(group.flatMap((s) => s.sentences)))
    parts.push(
      await backend.synthesize({
        text: r.text,
        narrator: cast[r.role],
        language,
        tools,
      }),
    );
  calls += parts.length;
  // Every backend answers at one rate (24 kHz).
  const { sampleRate } = parts[0];
  const samples = new Float32Array(
    parts.reduce((n, p) => n + p.samples.length, 0),
  );
  let at = 0;
  for (const p of parts) {
    samples.set(p.samples, at);
    at += p.samples.length;
  }
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
    const heard = transcribe(
      em,
      ctc.vocab,
      Math.floor(start / FRAME),
      Math.floor(end / FRAME),
    );
    return {
      scene: s,
      samples: samples.subarray(from, to),
      sampleRate,
      words: own.map((w) => ({
        text: w.text,
        start: +(w.start - start).toFixed(3),
        end: +(w.end - start).toFixed(3),
      })),
      heard,
      qc: check(s.text, heard, own.at(-1).end - own[0].start, language),
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
// backend's key row in setup/rows.json: no other narrator stands in, since
// script.json or the cast names this narrator.
for (const n of Object.values(cast)) {
  const keyRow = catalogue().find(
    (r) => r.kind === "key" && r.backend === n.backend,
  );
  if (missing.length && keyRow && !process.env[keyRow.env]) {
    console.error(
      `voice: narrator ${n.id} needs ${keyRow.env}: get a free key at ${keyRow.get}, or choose another narrator in script.json`,
    );
    process.exit(1);
  }
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
let calls = 0;
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
      fs.writeFileSync(heardFile(v.scene.key), v.heard + "\n");
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
      `voice: ${e.vendor} quota reached (${e.message}); ${kept} scene(s) voiced before it are kept. Voice again once the quota resets (tomorrow, for a daily quota) or the credits are topped up, which voices only the missing scenes; set another key (a paid one, for a free-tier limit); or choose another narrator in script.json`,
    );
  else console.error(`voice: ${e.message}`);
  process.exit(1);
}

for (const s of scenes) {
  const e = s.cached ?? s.voiced;
  const q = e.qc;
  const verdict = q.failures.length
    ? `fail: ${q.failures.join("; ")}; heard: ${path.relative(run, heardFile(s.key))}`
    : "pass";
  if (q.failures.length) failed++;
  console.log(
    `voice ${s.id}: ${s.cached ? "cached" : "voiced"} · recall ${q.recall} · precision ${q.precision} · rate ${q.rate} chars/s · ${verdict}`,
  );
}
const summary = `${scenes.length} scene(s), ${missing.length} voiced in ${calls} call(s), ${scenes.length - missing.length} cached`;
if (failed) {
  console.log(`voice QC failed: ${failed} scene(s); ${summary}`);
  process.exit(1);
}
// length: with a brief, the voiced scenes and the render's closing hold within
// 10 percent of the brief's length, which the script's budget only predicts.
if (brief) {
  const { length } = brief;
  const durations = scenes.map((s) => (s.cached ?? s.voiced).duration);
  const voiced = durations.reduce((a, d) => a + d, 0);
  const ok = fitsLength(voiced, length);
  const each = scenes.map((s, i) => `${s.id} ${durations[i].toFixed(1)} s`);
  console.log(
    `voice length: ${ok ? "pass" : "fail"}: the scenes voice ${voiced.toFixed(1)} s (${each.join(", ")}) and the ${HOLD} s hold vs the brief's ${length * 60} s ±10%`,
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
      voices: voicesOf(cast),
      scenes: scenes.map((s) => ({
        id: s.id,
        ...(s.cached ?? s.voiced),
        speakers: s.roles,
      })),
    },
    null,
    2,
  ) + "\n",
);
console.log(`voice QC pass: ${summary}`);
