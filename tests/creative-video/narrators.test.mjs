// narrators.json is a contract the voice stage and setup read: every
// narrator, as narrators() merges it over its backend's defaults, carries the
// same fields, and English ships calibrated.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseNarrators } from "../../skills/creative-video/scripts/lib/narrators.mjs";
import { SCENES, fixture, run, synths, write } from "./voice-lib.mjs";

const file = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "skills",
  "creative-video",
  "narrators.json",
);
const body = fs.readFileSync(file, "utf8");
const narrators = parseNarrators(body);

test("an entry's own fields win over its backend's defaults, and its voice is its id unless it names one", () => {
  const merged = parseNarrators(
    JSON.stringify({
      defaults: {
        kokoro: { language: "en", style: null, rate: null, default: false },
      },
      narrators: [
        { id: "a", gender: "male", backend: "kokoro" },
        { id: "b", gender: "male", backend: "kokoro", voice: "v", rate: 9.5 },
        { id: "c", gender: "male", backend: "kokoro", language: "ar" },
      ],
    }),
  );
  assert.deepEqual(
    merged.map((n) => [n.id, n.voice, n.language, n.rate, n.default]),
    [
      ["a", "a", "en", null, false],
      ["b", "v", "en", 9.5, false],
      ["c", "c", "ar", null, false],
    ],
  );
});

test("narrators.json holds the backends' shared fields once, each entry only what is its own", () => {
  const { defaults, narrators: raw } = JSON.parse(body);
  assert.deepEqual(Object.keys(defaults).sort(), [
    "elevenlabs",
    "gemini",
    "kokoro",
  ]);
  for (const n of raw) {
    assert.ok(n.id && n.gender && defaults[n.backend], n.id);
    for (const k of ["language", "style", "licence", "leavesMachine"])
      assert.ok(!(k in n), `${n.id} repeats ${k}`);
  }
});

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

// The Kokoro voices installed with the English rows, gender in the first two
// letters' second one (af_ female, bm_ male).
const KOKORO =
  `af_alloy af_aoede af_bella af_heart af_jessica af_kore af_nicole af_nova af_river af_sarah af_sky am_adam am_echo am_eric am_fenrir am_liam am_michael am_onyx am_puck am_santa bf_alice bf_emma bf_isabella bf_lily bm_daniel bm_fable bm_george bm_lewis`.split(
    " ",
  );

test("every installed Kokoro voice is an English narrator whose gender is its prefix's, af_heart the one default, and the first three keep their calibrated pause", () => {
  const english = narrators.filter(
    (n) => n.language === "en" && n.backend === "kokoro",
  );
  assert.deepEqual(english.map((n) => n.id).slice(0, 3), [
    "bf_emma",
    "am_fenrir",
    "af_heart",
  ]);
  assert.deepEqual(english.map((n) => n.id).sort(), [...KOKORO].sort());
  for (const n of english) {
    assert.equal(n.voice, n.id);
    assert.equal(n.gender, n.id[1] === "f" ? "female" : "male", n.id);
    assert.equal(n.default, n.id === "af_heart", n.id);
  }
  for (const n of english.slice(0, 3))
    assert.ok(n.pause > 0.3 && n.pause < 2, `${n.id} pause ${n.pause}`);
});

// #783: a narrator still in words a second (2 to 4) budgets about a quarter of
// the characters a script carries. A narrator not yet calibrated carries a null
// rate and pause, both, and every default is calibrated.
test("every calibrated narrator's rate is in spoken characters a second, none left in words a second, and an uncalibrated one has no pause either", () => {
  for (const n of narrators) {
    if (n.rate === null) {
      assert.equal(n.pause, null, n.id);
      assert.equal(n.default, false, n.id);
    } else assert.ok(n.rate > 8 && n.rate < 25, `${n.id} rate ${n.rate}`);
  }
});

test("the Egyptian Arabic narrators are Gemini voices whose text leaves the machine, the two first the defaults and the rest Gemini's other Egyptian voices", () => {
  const arabic = narrators.filter((n) => n.language === "ar");
  assert.deepEqual(
    arabic.slice(0, 2).map((n) => [n.id, n.gender, n.default]),
    [
      ["ar-eg-csagent-2", "female", true],
      ["ar-eg-commercial-11", "male", true],
    ],
  );
  // The 92 voices Gemini listed for ar-EG on 2026-10-28
  // (maintainer/calibrate-rates.mjs).
  assert.equal(arabic.length, 92);
  assert.equal(new Set(arabic.map((n) => n.id)).size, 92);
  for (const n of arabic) {
    assert.match(n.id, /^ar-eg-/);
    assert.ok(["female", "male", "neutral"].includes(n.gender), n.id);
    assert.equal(n.backend, "gemini", n.id);
    assert.equal(n.voice, n.id);
    assert.equal(n.leavesMachine, true, n.id);
  }
  for (const n of arabic.slice(2)) assert.equal(n.default, false, n.id);
});

test("the voice stage refuses a narrator with no calibrated rate, naming the calibration, before any synthesis", () => {
  const uncalibrated = narrators.find((n) => n.rate === null);
  assert.ok(uncalibrated);
  const fx = fixture();
  write(fx, SCENES, uncalibrated.language, { narrator: uncalibrated.id });
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    new RegExp(
      `^voice: narrator ${uncalibrated.id} has no calibrated rate; run maintainer/calibrate-rates.mjs ${uncalibrated.language} ${uncalibrated.id}$`,
      "m",
    ),
  );
  assert.equal(synths(fx).length, 0);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
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
