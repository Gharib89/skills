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

// The fake's frame layout, worked by hand: a word holds 3 frames per letter,
// then a `|` frame; words are 2 silent frames apart, sentences 12. Frames are
// 20 ms. The span runs from the first word's first letter to the last `|`.
function fakeRate(text) {
  const sentences = text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.toUpperCase().match(/[A-Z']+/g));
  const words = sentences.flat();
  const frames =
    words.reduce((n, w) => n + 3 * w.length + 1, 0) +
    2 * (words.length - sentences.length) +
    12 * (sentences.length - 1);
  return words.length / (frames * 0.02);
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

test("calibration measures each English narrator's rate in words per second and leaves the rest of narrators.json alone", () => {
  const { out, calls, before, after } = calibrateCopy("en");
  assert.deepEqual(
    calls.map((c) => c.voice),
    ["bf_emma", "am_fenrir", "JBFqnCBsd6RMkjVDRZzb"],
  );
  const want = fakeRate(calls[0].text);
  for (const n of after.filter((n) => n.language === "en")) {
    assert.ok(Math.abs(n.rate - want) / want < 0.02, `${n.id} ${n.rate}`);
    assert.match(out, new RegExp(`^calibrate ${n.id}: ${n.rate} words/s`, "m"));
  }
  assert.deepEqual(
    after.map(({ rate, ...n }) => n),
    before.map(({ rate, ...n }) => n),
  );
  const arabic = before.filter((n) => n.language === "ar");
  assert.ok(arabic.length);
  assert.deepEqual(
    after.filter((n) => n.language === "ar"),
    arabic,
  );
});

test("calibration on the Arabic text voices it on each Gemini narrator and writes their rates", () => {
  const { out, calls, before, after } = calibrateCopy("ar");
  assert.deepEqual(
    calls.map((c) => [c.backend, c.voice]),
    [
      ["gemini", "ar-eg-csagent-2"],
      ["gemini", "ar-eg-commercial-11"],
    ],
  );
  assert.ok(calls[0].text.split(/\s+/).length >= 55, calls[0].text);
  for (const n of after.filter((n) => n.language === "ar")) {
    assert.ok(n.rate > 1.5 && n.rate < 4.5, `${n.id} ${n.rate}`);
    assert.match(out, new RegExp(`^calibrate ${n.id}: ${n.rate} words/s`, "m"));
  }
  assert.deepEqual(
    after.filter((n) => n.language === "en"),
    before.filter((n) => n.language === "en"),
  );
});
