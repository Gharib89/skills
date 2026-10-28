// The maintainer rate calibration through its process door: a copy of
// narrators.json, the canned backend, and the rates it writes back.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseNarrators } from "../../skills/creative-video/scripts/lib/narrators.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "creative-video");
const script = path.join(skill, "maintainer", "calibrate-rates.mjs");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The fake's frame layout, worked by hand: 10 silent frames lead, a word holds
// 3 frames per letter, then a `|` frame and 2 silent frames, and each sentence
// ends on 10 more. Frames are 20 ms. A sentence's speech runs from its first
// word's first letter to its last `|`; the rest of the audio is silence.
function fakeCalibration(texts) {
  let chars = 0;
  let speech = 0;
  let sentences = 0;
  let total = 0;
  for (const text of texts) {
    const ss = text
      .split(/(?<=[.!?])\s+/)
      .map((s) => s.toUpperCase().match(/[A-Z']+/g));
    const ws = ss.flat();
    chars += text.match(/[\p{L}\p{N}]/gu).length;
    sentences += ss.length;
    speech +=
      ws.reduce((n, w) => n + 3 * w.length + 1, 0) +
      2 * (ws.length - ss.length);
    total += 10 + ws.reduce((n, w) => n + 3 * w.length + 3, 0) + 10 * ss.length;
  }
  return {
    rate: chars / (speech * 0.02),
    pause: ((total - speech) * 0.02) / sentences,
  };
}

const shipped = JSON.parse(
  fs.readFileSync(path.join(skill, "narrators.json"), "utf8"),
);

// Run the calibration on a narrators.json of the shipped defaults and the
// shipped entries of the narrators in `given`,
// `{ id: [rate, pause] }` (null for one not yet calibrated), with the command
// line `args` after the language and `env` on top of the canned backend: the
// process, the synthesize calls, the narrators (as readers see them) before
// and after, and `file`, the file's own text after. A
// `second` run, with its own `args` and `env`, reuses the file the first left.
function calibrate(language, given, args = [], env = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "creative-calibrate-"));
  temps.push(tmp);
  const file = path.join(tmp, "narrators.json");
  const read = () => parseNarrators(fs.readFileSync(file, "utf8"));
  const narrators = Object.entries(given).map(([id, [rate, pause]]) => ({
    ...shipped.narrators.find((n) => n.id === id),
    rate,
    pause,
  }));
  fs.writeFileSync(
    file,
    JSON.stringify({ defaults: shipped.defaults, narrators }),
  );
  const before = read();
  let runs = 0;
  const run = (more, extra) => {
    const log = path.join(tmp, `calls-${runs++}.jsonl`);
    const r = spawnSync(
      process.execPath,
      [script, language, "--file", file, ...more],
      {
        env: {
          PATH: process.env.PATH,
          HOME: path.join(tmp, "home"),
          XDG_CACHE_HOME: path.join(tmp, "cache"),
          CREATIVE_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
          CREATIVE_VIDEO_FAKE_LOG: log,
          ...extra,
        },
        encoding: "utf8",
      },
    );
    const calls = fs.existsSync(log)
      ? fs
          .readFileSync(log, "utf8")
          .trim()
          .split("\n")
          .map((l) => JSON.parse(l))
          .filter((c) => c.call === "synthesize")
      : [];
    return {
      r,
      out: r.stdout,
      err: r.stderr,
      calls,
      before,
      after: read(),
      file: JSON.parse(fs.readFileSync(file, "utf8")),
    };
  };
  return {
    ...run(args, env),
    second: (more = [], extra = {}) => run(more, extra),
  };
}

const rateLine = (n) =>
  new RegExp(
    `^calibrate ${n.id}: ${n.rate} chars/s, ${n.pause} s a sentence$`,
    "m",
  );
const textLine = (id, k) =>
  new RegExp(
    `^calibrate ${id} text ${k + 1}: \\d+\\.\\d+ chars/s, \\d+\\.\\d+ s a sentence$`,
    "m",
  );
const voices = (calls) => [...new Set(calls.map((c) => c.voice))];

test("calibration measures each uncalibrated English narrator's characters a second of speech and pause a sentence over several texts, printing each text's rate and pause, and leaves calibrated narrators and other languages alone", () => {
  const { r, out, calls, before, after } = calibrate("en", {
    bf_emma: [16.55, 0.78],
    af_alloy: [null, null],
    am_adam: [null, null],
    "ar-eg-advisor-11": [null, null],
  });
  assert.equal(r.status, 0, out + r.stderr);
  const texts = [...new Set(calls.map((c) => c.text))];
  assert.ok(texts.length >= 3, `${texts.length} texts`);
  assert.deepEqual(
    calls.map((c) => c.voice),
    ["af_alloy", "am_adam"].flatMap((v) => texts.map(() => v)),
  );
  const want = fakeCalibration(texts);
  for (const n of after.filter((n) => ["af_alloy", "am_adam"].includes(n.id))) {
    assert.ok(
      Math.abs(n.rate - want.rate) / want.rate < 0.02,
      `${n.id} ${n.rate}`,
    );
    // The aligner's word edges sit a frame or two inside the hand count's.
    assert.ok(Math.abs(n.pause - want.pause) < 0.05, `${n.id} ${n.pause}`);
    texts.forEach((_, k) => assert.match(out, textLine(n.id, k)));
    assert.match(out, rateLine(n));
  }
  assert.match(
    out,
    /^calibrate bf_emma: skipped, already calibrated \(--all measures it again\)$/m,
  );
  for (const id of ["bf_emma", "ar-eg-advisor-11"])
    assert.deepEqual(
      after.find((n) => n.id === id),
      before.find((n) => n.id === id),
    );
  assert.deepEqual(
    after.map(({ rate, pause, ...n }) => n),
    before.map(({ rate, pause, ...n }) => n),
  );
});

test("calibration with --all measures a narrator that already has a rate, voicing each Arabic text on each Gemini narrator, and writes their rates and pauses", () => {
  const { r, out, calls, before, after } = calibrate(
    "ar",
    {
      "ar-eg-csagent-2": [11.2, 0.7],
      "ar-eg-commercial-11": [12.71, 0.68],
      af_alloy: [null, null],
    },
    ["--all"],
  );
  assert.equal(r.status, 0, out + r.stderr);
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
    assert.notDeepEqual(
      n,
      before.find((b) => b.id === n.id),
      `${n.id} measured again`,
    );
    assert.ok(n.rate > 8 && n.rate < 25, `${n.id} ${n.rate}`);
    assert.ok(n.pause > 0 && n.pause < 2, `${n.id} ${n.pause}`);
    texts.forEach((_, k) => assert.match(out, textLine(n.id, k)));
    assert.match(out, rateLine(n));
  }
  assert.deepEqual(
    after.filter((n) => n.language === "en"),
    before.filter((n) => n.language === "en"),
  );
});

test("calibration given narrator ids measures only those, still skipping a calibrated one unless --all", () => {
  const given = {
    bf_emma: [16.55, 0.78],
    af_alloy: [null, null],
    am_adam: [null, null],
  };
  const one = calibrate("en", given, ["am_adam", "bf_emma"]);
  assert.equal(one.r.status, 0, one.out + one.err);
  assert.deepEqual(voices(one.calls), ["am_adam"]);
  assert.ok(Number.isFinite(one.after[2].rate));
  assert.equal(one.after[1].rate, null);
  assert.deepEqual(one.after[0], one.before[0]);

  const all = calibrate("en", given, ["--all", "bf_emma"]);
  assert.equal(all.r.status, 0, all.out + all.err);
  assert.deepEqual(voices(all.calls), ["bf_emma"]);
  assert.notEqual(all.after[0].rate, 16.55);
  assert.equal(all.after[1].rate, null);
  assert.equal(all.after[2].rate, null);
});

test("calibration refuses a narrator id that is not a narrator of the language, writing nothing", () => {
  const r = calibrate(
    "en",
    { af_alloy: [null, null], "ar-eg-advisor-11": [null, null] },
    ["af_alloy", "ar-eg-advisor-11"],
  );
  assert.equal(r.r.status, 2, r.out + r.err);
  assert.match(r.err, /no en narrator ar-eg-advisor-11/);
  assert.equal(r.calls.length, 0);
  assert.deepEqual(r.after, r.before);
});

test("calibration writes narrators.json after each narrator, so a quota stop keeps what it measured and names where it stopped, and the next run resumes there", () => {
  const given = {
    "ar-eg-advisor-11": [null, null],
    "ar-eg-advisor-12": [null, null],
    "ar-eg-advisor-4": [null, null],
  };
  const first = calibrate("ar", given, [], { CREATIVE_VIDEO_FAKE_QUOTA: "3" });
  assert.equal(first.r.status, 1, first.out + first.err);
  assert.match(first.err, /^calibrate: stopped at ar-eg-advisor-12: /m);
  assert.equal(first.calls.length, 3);
  assert.match(first.out, rateLine(first.after[0]));
  assert.ok(first.after[0].rate > 8 && first.after[0].pause > 0);
  assert.deepEqual(
    first.after.slice(1).map((n) => [n.rate, n.pause]),
    [
      [null, null],
      [null, null],
    ],
  );

  const second = first.second();
  assert.equal(second.r.status, 0, second.out + second.err);
  assert.deepEqual(voices(second.calls), [
    "ar-eg-advisor-12",
    "ar-eg-advisor-4",
  ]);
  assert.deepEqual(second.after[0], first.after[0]);
  for (const n of second.after) assert.ok(n.rate > 8 && n.pause > 0, n.id);
});

test("calibration writes back only the rate and pause of the entries it measured, leaving the defaults block and the entries' other fields as the file holds them", () => {
  const { r, out, err, after, file } = calibrate(
    "en",
    { af_alloy: [null, null], am_adam: [null, null] },
    ["af_alloy"],
  );
  assert.equal(r.status, 0, out + err);
  assert.deepEqual(file.defaults, shipped.defaults);
  const [alloy, adam] = file.narrators;
  assert.deepEqual(Object.keys(alloy), [
    "id",
    "gender",
    "backend",
    "rate",
    "pause",
  ]);
  assert.equal(alloy.rate, after[0].rate);
  assert.equal(alloy.pause, after[0].pause);
  assert.deepEqual(adam, {
    ...shipped.narrators.find((n) => n.id === "am_adam"),
    rate: null,
    pause: null,
  });
  assert.equal(after[0].language, "en");
  assert.equal(after[0].licence, "Apache-2.0");
});
