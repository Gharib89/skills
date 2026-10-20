// The video gates through their process doors, part 1: a clean render and the
// narration and score mix. A run rendered with the canned backend, whose marker
// words (fake-backend.mjs) break one gate each.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { frameTime } from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  calls,
  delivered,
  fixture,
  read,
  record,
  render,
  renderUnjudged,
  skill,
  stage,
} from "./gates-lib.mjs";

test("a clean render passes all six gates, writes the record and the report, and delivers", () => {
  const fx = fixture();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const lines = r.out.split("\n").filter((l) => /^gates?\b/.test(l));
  assert.deepEqual(lines, [
    "gate layout: pass: 0 finding(s) vs none, text >= 18 px, margin 5%",
    "gate contrast: pass: 0 finding(s) vs body 4.5:1, large 3:1",
    "gate loudness: pass: -14.0 LUFS, peak -1.6 dBTP vs -14 +-1 LUFS, peak <= -1 dBTP",
    lines[3],
    lines[4],
    "gate determinism: pass: 0 of 3 scene(s) differ between two renders vs none, the same pixels twice",
    "gate critic: pass: 0 hard failure(s), mean scores clarity 4.0, legibility 5.0, fit 4.0, motion 3.0, round 1 of 2 vs no unreadable or invented content; scores advise",
    "gates: 7 pass, 0 fail",
  ]);
  assert.match(
    lines[3],
    /^gate captions: pass: \d+ cue\(s\), 0 finding\(s\) vs none$/,
  );
  const sfx = JSON.parse(read(fx.dir, "score.json")).cues.length;
  assert.equal(
    lines[4],
    `gate sfx: pass: ${sfx} cue(s), at most ${sfx} in a minute vs <= 24 a minute`,
  );
  const gates = record(fx);
  assert.match(gates.script, /^[0-9a-f]{16}$/);
  assert.deepEqual(Object.keys(gates.gates), [
    "layout",
    "contrast",
    "loudness",
    "captions",
    "sfx",
    "determinism",
    "critic",
  ]);
  assert.deepEqual(gates.gates.determinism, {
    status: "pass",
    measured: "0 of 3 scene(s) differ between two renders",
    floor: "none, the same pixels twice",
    attempts: 0,
    evidence: [],
  });
  assert.deepEqual(gates.gates.loudness, {
    status: "pass",
    measured: "-14.0 LUFS, peak -1.6 dBTP",
    floor: "-14 +-1 LUFS, peak <= -1 dBTP",
    attempts: 0,
    evidence: [],
  });
  const md = read(fx.dir, "gates.md");
  assert.match(md, /^# Video gates\n/);
  assert.match(md, /^\| gate \| status \| measured \| floor \| attempts \|$/m);
  assert.match(
    md,
    /^\| loudness \| pass \| -14\.0 LUFS, peak -1\.6 dBTP \| -14 \+-1 LUFS, peak <= -1 dBTP \| 0 \|$/m,
  );
  assert.ok(!/\d{4}-\d\d-\d\d/.test(md), "no date in the report");
  assert.ok(fs.existsSync(path.join(delivered(fx), "demo.mp4")));
  assert.match(r.out, /^delivered: /m);
  // Samples: every 15 frames from each scene's start, plus its settled last
  // frame and where the seam into it ends (the previous scene's seam length).
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  assert.ok(
    timeline.scenes.some((s) => s.slot > s.duration),
    "the default style draws a seam",
  );
  const want = timeline.scenes.flatMap((s, i) => {
    const first = Math.round(s.start * 30);
    const last = first + Math.round(s.duration * 30) - 1;
    const prev = timeline.scenes[i - 1];
    const seam = prev ? Math.round((prev.slot - prev.duration) * 30) : 0;
    const frames = new Set([last]);
    for (let f = first; f < last; f += 15) frames.add(f);
    if (seam) frames.add(first + seam);
    return [...frames].sort((a, b) => a - b).map((f) => frameTime(f, 30));
  });
  assert.deepEqual(calls(fx, "probe")[0].times, want);
  assert.deepEqual(calls(fx, "check")[0].times, want);
});

test("the narration is mastered to -14 LUFS under the peak floor before the video renders", () => {
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT);
  assert.match(r.out, /^gates: 6 pass, 0 fail, 1 pending/m, r.out + r.err);
  const m = calls(fx, "master");
  assert.equal(m.length, 1);
  assert.equal(m[0].lufs, -14);
  assert.equal(m[0].peak, -1.5);
  assert.equal(path.basename(m[0].output), "narration.wav");
  assert.equal(path.basename(path.dirname(m[0].output)), "composition");
});

const wav = (f) => {
  const b = fs.readFileSync(f);
  return {
    channels: b.readUInt16LE(22),
    rate: b.readUInt32LE(24),
    bits: b.readUInt16LE(34),
    seconds: b.readUInt32LE(40) / b.readUInt32LE(28),
  };
};

test("by default a score of the whole timeline is mixed under the narration, its cues on the cuts", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const [m] = calls(fx, "master");
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  assert.deepEqual(wav(m.bed), {
    channels: 2,
    rate: 48000,
    bits: 24,
    seconds: Math.round(timeline.total * 48000) / 48000,
  });
  const s = JSON.parse(read(fx.dir, "score.json"));
  assert.equal(s.score, "on");
  assert.ok(s.preset && Number.isInteger(s.seed), JSON.stringify(s));
  const last = timeline.scenes.at(-1).words.at(-1);
  assert.deepEqual(s.cues, [
    ...timeline.scenes.slice(1).map((sc) => ({ type: "whoosh", t: sc.start })),
    { type: "sting", t: last.end },
  ]);
});

test("the same timings render the cached score again", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const first = calls(fx, "master")[0].bed;
  const before = fs.statSync(first).mtimeMs;
  assert.equal(stage(fx, "render/render.mjs").code, 0);
  const again = calls(fx, "master")[1].bed;
  assert.equal(again, first);
  assert.equal(fs.statSync(again).mtimeMs, before);
});

// The fixture's script voices about 15 s, under any length brief.mjs takes,
// so a score test's brief asks for a quarter minute to pass the voice stage.
function quarterMinute(fx) {
  const file = path.join(fx.dir, "brief.json");
  fs.writeFileSync(
    file,
    JSON.stringify({ ...JSON.parse(read(file)), length: 0.25 }, null, 2),
  );
}

// The brief set to score=ace-step; `installed` stamps the ace-step row as
// setup leaves it.
function aceBrief(fx, installed = true) {
  const b = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "brief", "brief.mjs"),
      fx.dir,
      "voice=am_fenrir",
      "score=ace-step",
    ],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(b.status, 0, b.stderr);
  quarterMinute(fx);
  const d = dest(
    catalogue().find((r) => r.id === "ace-step"),
    fx.dirs,
    "cpu", // no card here, so the CPU-only pin's folder
  );
  if (installed) {
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
  }
  return d;
}

test("a brief with score=ace-step mixes ACE-Step's music under the narration on the device the card allows, once per seed", () => {
  const fx = fixture();
  const dir = aceBrief(fx);
  const env = { EXPLAINER_VIDEO_FAKE_GPU: "7.5" };
  const r = render(fx, undefined, env);
  assert.equal(r.code, 0, r.out + r.err);
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const [a] = calls(fx, "aceStep");
  const s = JSON.parse(read(fx.dir, "score.json"));
  assert.deepEqual(
    { ...a, caption: typeof a.caption },
    {
      call: "aceStep",
      dir,
      device: "cpu",
      seconds: timeline.total,
      seed: s.seed,
      caption: "string",
    },
  );
  assert.equal(s.score, "ace-step");
  assert.equal(s.device, "cpu");
  assert.equal(s.preset, undefined);
  const [m] = calls(fx, "master");
  assert.equal(wav(m.bed).seconds, Math.round(timeline.total * 48000) / 48000);
  assert.equal(stage(fx, "render/render.mjs", env).code, 0);
  assert.equal(
    calls(fx, "aceStep").length,
    1,
    "the same seed made the music again",
  );
  assert.equal(calls(fx, "master")[1].bed, m.bed);
});

test("an ACE-Step run that fails stops render with its reason", () => {
  const fx = fixture();
  aceBrief(fx);
  const r = render(fx, undefined, { EXPLAINER_VIDEO_FAKE_ACE_EXIT: "1" });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^render: ace-step exited 1$/m);
  assert.deepEqual(calls(fx, "master"), []);
});

test("a brief with score=ace-step before setup installed it says to run setup", () => {
  const fx = fixture();
  aceBrief(fx, false);
  const r = render(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: ace-step is not installed: run \/explainer-video setup, asking for ace-step$/m,
  );
  assert.deepEqual(calls(fx, "aceStep"), []);
});

test("a brief with the score off masters the narration alone", () => {
  const fx = fixture();
  const b = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "brief", "brief.mjs"),
      fx.dir,
      "voice=am_fenrir",
      "score=off",
    ],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(b.status, 0, b.stderr);
  quarterMinute(fx);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(calls(fx, "master")[0].bed, undefined);
  assert.deepEqual(JSON.parse(read(fx.dir, "score.json")), {
    score: "off",
    cues: [],
  });
});
