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

const ARABIC = {
  id: "ar-eg-csagent-2",
  language: "ar",
  gender: "female",
  backend: "gemini",
  voice: "ar-eg-csagent-2",
  style: "warm",
  licence: "Gemini API terms",
  leavesMachine: true,
  rate: 2.1,
  default: true,
};

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

test("calibration measures each English narrator's rate in words per second and leaves the rest of narrators.json alone", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-calibrate-"));
  temps.push(tmp);
  const file = path.join(tmp, "narrators.json");
  const before = JSON.parse(
    fs.readFileSync(path.join(skill, "narrators.json"), "utf8"),
  );
  before.narrators.push(ARABIC);
  fs.writeFileSync(file, JSON.stringify(before));
  const log = path.join(tmp, "calls.jsonl");
  const r = spawnSync(process.execPath, [calibrate, "en", file], {
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
  assert.deepEqual(
    calls.map((c) => c.voice),
    ["bf_emma", "am_fenrir"],
  );
  const want = fakeRate(calls[0].text);
  const after = JSON.parse(fs.readFileSync(file, "utf8")).narrators;
  for (const n of after.filter((n) => n.language === "en")) {
    assert.ok(Math.abs(n.rate - want) / want < 0.02, `${n.id} ${n.rate}`);
    assert.match(
      r.stdout,
      new RegExp(`^calibrate ${n.id}: ${n.rate} words/s`, "m"),
    );
  }
  assert.deepEqual(
    after.map(({ rate, ...n }) => n),
    before.narrators.map(({ rate, ...n }) => n),
  );
  assert.deepEqual(after.at(-1), ARABIC);
});
