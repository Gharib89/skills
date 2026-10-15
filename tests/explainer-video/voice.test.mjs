// The voice stage through its process door: a run folder holding a script, the
// canned backend (fake audio that spells its text, a fake aligner model), and
// assertions on the files the stage writes, its verdict lines and exit code.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const voice = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "voice",
  "voice.mjs",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

const SCENES = [
  {
    id: "hook",
    narration: ["Ship drives one issue to a merged pull request."],
  },
  {
    id: "context",
    narration: [
      "It reads the profile first.",
      "Then it claims the issue so no other run takes it.",
    ],
  },
  {
    id: "recap",
    narration: ["Every change lands through a reviewed pull request."],
  },
];

function fixture(scenes = SCENES) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-voice-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const fx = { tmp, dir, log: path.join(tmp, "calls.jsonl") };
  write(fx, scenes);
  return fx;
}

const write = (fx, scenes) =>
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({ language: "en", scenes }),
  );

function run(fx) {
  const r = spawnSync(process.execPath, [voice, fx.dir], {
    env: {
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

const synths = (fx) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === "synthesize")
    : [];

const line = (out, id) =>
  out.split("\n").find((l) => l.startsWith(`voice ${id}:`));

// Seconds of 16-bit mono PCM in a WAV file, read from its header.
function wavSeconds(file) {
  const b = fs.readFileSync(file);
  assert.equal(b.toString("ascii", 0, 4), "RIFF");
  assert.equal(b.toString("ascii", 8, 12), "WAVE");
  const rate = b.readUInt32LE(24);
  return b.readUInt32LE(40) / 2 / rate;
}

test("a first run voices the whole narration in one call and writes a WAV and word timings per scene", () => {
  const fx = fixture();
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(synths(fx).length, 1);
  assert.equal(
    synths(fx)[0].text,
    SCENES.flatMap((s) => s.narration).join(" "),
  );
  assert.match(synths(fx)[0].model, /models\/kokoro-82m@1939ad2a8e41$/);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.narrator, "bf_emma");
  assert.deepEqual(
    timeline.scenes.map((s) => s.id),
    SCENES.map((s) => s.id),
  );
  for (const [i, s] of timeline.scenes.entries()) {
    assert.match(line(r.out, s.id), /voiced/);
    const seconds = wavSeconds(path.join(fx.dir, s.audio));
    assert.ok(Math.abs(seconds - s.duration) < 0.01, `${s.id} duration`);
    const words = SCENES[i].narration.join(" ").split(" ");
    assert.deepEqual(
      s.words.map((w) => w.text),
      words,
    );
    let t = 0;
    for (const w of s.words) {
      assert.ok(w.start >= t && w.end > w.start, JSON.stringify(w));
      t = w.end;
    }
    assert.ok(t <= s.duration);
  }
});

test("changing one scene's text re-voices only that scene; the others are cache hits", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const changed = structuredClone(SCENES);
  changed[1].narration[1] =
    "Then it takes the issue so no other run claims it.";
  write(fx, changed);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "hook"), /: cached ·/);
  assert.match(line(r.out, "context"), /: voiced ·/);
  assert.match(line(r.out, "recap"), /: cached ·/);
  assert.match(r.out, /3 scene\(s\), 1 voiced in 1 call\(s\), 2 cached/);
  const calls = synths(fx);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].text, changed[1].narration.join(" "));
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.scenes[1].words[7].text, "takes");
});

// Each misrender the fake can make, the floor it misses, and the value the
// verdict line must carry: worked from the fake's frame layout.
for (const [name, sentence, why] of [
  [
    "a garbled render",
    "This garbled sentence comes out as noise.",
    /recall 0 under 0\.8/,
  ],
  [
    "a looped render",
    "This looped sentence plays its words twice.",
    /precision 0\.5 under 0\.85/,
  ],
  [
    "a dragged render",
    "This sentence reads slowly.",
    /rate \d+(\.\d+)? chars\/s outside 9 to 22/,
  ],
]) {
  test(`voice QC blocks ${name} with the measured value, writes no timeline and caches nothing for it`, () => {
    const scenes = structuredClone(SCENES);
    scenes[2].narration = [sentence];
    const fx = fixture(scenes);
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(line(r.out, "recap"), /· fail: /);
    assert.match(line(r.out, "recap"), why);
    assert.match(line(r.out, "hook"), /· pass$/);
    assert.match(r.out, /^voice QC failed: 1 scene\(s\)/m);
    assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
    const again = run(fx);
    assert.match(line(again.out, "recap"), /: voiced ·/);
    assert.match(line(again.out, "hook"), /: cached ·/);
  });
}
