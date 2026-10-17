// The maintainer rate calibration through its process door: a copy of
// narrators.json, the canned backend, and the rates it writes back.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "explainer-video");
const calibrate = path.join(skill, "maintainer", "calibrate-rates.mjs");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The fake's frame layout, worked by hand: 10 silent frames lead, a word holds
// 3 frames per letter, then a `|` frame and 2 silent frames, and each sentence
// ends on 10 more. Frames are 20 ms. A sentence's speech runs from its first
// word's first letter to its last `|`; the rest of the audio is silence.
function fakeCalibration(texts) {
  let words = 0;
  let speech = 0;
  let sentences = 0;
  let total = 0;
  for (const text of texts) {
    const ss = text
      .split(/(?<=[.!?])\s+/)
      .map((s) => s.toUpperCase().match(/[A-Z']+/g));
    const ws = ss.flat();
    words += ws.length;
    sentences += ss.length;
    speech +=
      ws.reduce((n, w) => n + 3 * w.length + 1, 0) +
      2 * (ws.length - ss.length);
    total += 10 + ws.reduce((n, w) => n + 3 * w.length + 3, 0) + 10 * ss.length;
  }
  return {
    rate: words / (speech * 0.02),
    pause: ((total - speech) * 0.02) / sentences,
  };
}

// Calibrate `language` on a copy of the shipped narrators.json: the exit, the
// synthesize calls, and the narrators before and after.
function calibrateCopy(language) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-calibrate-"));
  temps.push(tmp);
  const file = path.join(tmp, "narrators.json");
  fs.copyFileSync(path.join(skill, "narrators.json"), file);
  const before = JSON.parse(fs.readFileSync(file, "utf8")).narrators;
  const log = path.join(tmp, "calls.jsonl");
  const r = spawnSync(process.execPath, [calibrate, language, file], {
    env: {
      PATH: process.env.PATH,
      HOME: path.join(tmp, "home"),
      XDG_CACHE_HOME: path.join(tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: log,
    },
    encoding: "utf8",
  });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const calls = fs
    .readFileSync(log, "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l))
    .filter((c) => c.call === "synthesize");
  const after = JSON.parse(fs.readFileSync(file, "utf8")).narrators;
  return { out: r.stdout, calls, before, after };
}

test("calibration measures each English narrator's speech rate and pause a sentence over several texts, printing each text's rate and pause, and leaves the rest of narrators.json alone", () => {
  const { out, calls, before, after } = calibrateCopy("en");
  const texts = [...new Set(calls.map((c) => c.text))];
  assert.ok(texts.length >= 3, `${texts.length} texts`);
  assert.deepEqual(
    calls.map((c) => c.voice),
    ["bf_emma", "am_fenrir", "JBFqnCBsd6RMkjVDRZzb"].flatMap((v) =>
      texts.map(() => v),
    ),
  );
  const want = fakeCalibration(texts);
  for (const n of after.filter((n) => n.language === "en")) {
    assert.ok(
      Math.abs(n.rate - want.rate) / want.rate < 0.02,
      `${n.id} ${n.rate}`,
    );
    // The aligner's word edges sit a frame or two inside the hand count's.
    assert.ok(Math.abs(n.pause - want.pause) < 0.05, `${n.id} ${n.pause}`);
    texts.forEach((_, k) =>
      assert.match(
        out,
        new RegExp(
          `^calibrate ${n.id} text ${k + 1}: \\d+\\.\\d+ words/s, \\d+\\.\\d+ s a sentence$`,
          "m",
        ),
      ),
    );
    assert.match(
      out,
      new RegExp(
        `^calibrate ${n.id}: ${n.rate} words/s, ${n.pause} s a sentence$`,
        "m",
      ),
    );
  }
  assert.deepEqual(
    after.map(({ rate, pause, ...n }) => n),
    before.map(({ rate, pause, ...n }) => n),
  );
  const arabic = before.filter((n) => n.language === "ar");
  assert.ok(arabic.length);
  assert.deepEqual(
    after.filter((n) => n.language === "ar"),
    arabic,
  );
});

test("calibration voices each Arabic text on each Gemini narrator, printing each text's rate and pause, and writes their rates and pauses", () => {
  const { out, calls, before, after } = calibrateCopy("ar");
  const texts = [...new Set(calls.map((c) => c.text))];
  assert.ok(texts.length >= 3, `${texts.length} texts`);
  assert.deepEqual(
    calls.map((c) => [c.backend, c.voice, c.text]),
    ["ar-eg-csagent-2", "ar-eg-commercial-11"].flatMap((v) =>
      texts.map((t) => ["gemini", v, t]),
    ),
  );
  for (const t of texts) assert.ok(t.split(/\s+/).length >= 55, t);
  for (const n of after.filter((n) => n.language === "ar")) {
    assert.ok(n.rate > 1.5 && n.rate < 4.5, `${n.id} ${n.rate}`);
    assert.ok(n.pause > 0 && n.pause < 2, `${n.id} ${n.pause}`);
    texts.forEach((_, k) =>
      assert.match(
        out,
        new RegExp(
          `^calibrate ${n.id} text ${k + 1}: \\d+\\.\\d+ words/s, \\d+\\.\\d+ s a sentence$`,
          "m",
        ),
      ),
    );
    assert.match(
      out,
      new RegExp(
        `^calibrate ${n.id}: ${n.rate} words/s, ${n.pause} s a sentence$`,
        "m",
      ),
    );
  }
  assert.deepEqual(
    after.filter((n) => n.language === "en"),
    before.filter((n) => n.language === "en"),
  );
});
