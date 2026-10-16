// narrators.json is a contract the voice and script stages read: every
// narrator carries the same fields, and English ships calibrated.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const file = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "skills",
  "explainer-video",
  "narrators.json",
);
const { narrators } = JSON.parse(fs.readFileSync(file, "utf8"));

test("every narrator carries the contract's fields, and each language has a default", () => {
  for (const n of narrators)
    assert.deepEqual(
      Object.keys(n).sort(),
      [
        "backend",
        "default",
        "gender",
        "id",
        "language",
        "leavesMachine",
        "licence",
        "rate",
        "style",
        "voice",
      ],
      n.id,
    );
  for (const language of new Set(narrators.map((n) => n.language)))
    assert.ok(
      narrators.some((n) => n.language === language && n.default),
      language,
    );
});

test("the English narrators ship with a calibrated rate in words per second", () => {
  const english = narrators.filter(
    (n) => n.language === "en" && n.backend === "kokoro",
  );
  assert.deepEqual(
    english.map((n) => n.id),
    ["bf_emma", "am_fenrir"],
  );
  for (const n of english)
    assert.ok(n.rate > 1.5 && n.rate < 4.5, `${n.id} rate ${n.rate}`);
});

test("the Egyptian Arabic narrators are Gemini voices whose text leaves the machine", () => {
  const arabic = narrators.filter((n) => n.language === "ar");
  assert.deepEqual(
    arabic.map((n) => [n.id, n.gender]),
    [
      ["ar-eg-csagent-2", "female"],
      ["ar-eg-commercial-11", "male"],
    ],
  );
  for (const n of arabic) {
    assert.equal(n.backend, "gemini", n.id);
    assert.equal(n.voice, n.id);
    assert.equal(n.leavesMachine, true, n.id);
    assert.ok(n.rate > 1.5 && n.rate < 4.5, `${n.id} rate ${n.rate}`);
  }
});

test("the ElevenLabs narrator is opt-in: never a default, and its text leaves the machine", () => {
  const eleven = narrators.filter((n) => n.backend === "elevenlabs");
  assert.deepEqual(
    eleven.map((n) => [n.id, n.language, n.voice]),
    [["elevenlabs-george", "en", "JBFqnCBsd6RMkjVDRZzb"]],
  );
  for (const n of eleven) {
    assert.equal(n.default, false, n.id);
    assert.equal(n.leavesMachine, true, n.id);
  }
});
