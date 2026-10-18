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
        "pause",
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

test("the English narrators ship with a calibrated pause a sentence", () => {
  const english = narrators.filter(
    (n) => n.language === "en" && n.backend === "kokoro",
  );
  assert.deepEqual(
    english.map((n) => n.id),
    ["bf_emma", "am_fenrir"],
  );
  for (const n of english)
    assert.ok(n.pause > 0.3 && n.pause < 2, `${n.id} pause ${n.pause}`);
});

// #783: a narrator still in words a second (2 to 4) budgets about a quarter of
// the characters the script gate counts.
test("every narrator's rate is in spoken characters a second, none left in words a second", () => {
  for (const n of narrators)
    assert.ok(n.rate > 8 && n.rate < 25, `${n.id} rate ${n.rate}`);
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
