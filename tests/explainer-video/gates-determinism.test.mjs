// The video gates through their process doors, part 5: determinism, the motion
// strips and verdicts cached in old formats.
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  frameTime,
  sceneFrames,
  stripStart,
} from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { judged } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  calls,
  delivered,
  fixture,
  read,
  record,
  render,
  renderUnjudged,
  seamRecord,
  skill,
  stage,
} from "./gates-lib.mjs";

// The fake backend's peak for a moving scene: its largest difference sits at
// entry n/3, which is frame first + n/3 + 1.
const peakOf = (s) => {
  const { first, n } = sceneFrames({
    start: s.start,
    duration: s.duration,
    fps: 30,
  });
  return { first, n, frame: first + Math.floor(n / 3) + 1 };
};

test("determinism renders each scene's peak-motion frame twice in two browsers and compares decoded pixels, not files", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const frames = calls(fx, "frame");
  assert.equal(frames.length, 6, "two renders of one frame per scene");
  timeline.scenes.forEach((s, i) => {
    const [a, b] = frames.slice(2 * i, 2 * i + 2);
    assert.equal(a.t, frameTime(peakOf(s).frame, 30));
    assert.equal(b.t, a.t);
    assert.notEqual(a.out, b.out);
    // The files differ in metadata on every render; the pixels do not.
    assert.notEqual(read(a.out), read(b.out));
    assert.ok(a.out.includes(path.join(".cache", "gates", "frames")), a.out);
  });
  assert.equal(calls(fx, "bandMotion").length, 3);
  // the default layout is open: the motion gate crops its content from 96 px
  assert.ok(calls(fx, "bandMotion").every((c) => c.band.top === 96));
});

test("a second gates run on an unchanged render makes no frame render call", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const before = [calls(fx, "frame").length, calls(fx, "bandMotion").length];
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate determinism: pass: /m);
  assert.deepEqual(
    [calls(fx, "frame").length, calls(fx, "bandMotion").length],
    before,
  );
});

test("a frame that renders differently twice fails determinism, names the scene and frame time, and stops with no fix attempt", () => {
  const fx = fixture();
  const r = renderUnjudged(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "flaky code"'),
  );
  assert.equal(r.code, 1, r.out + r.err);
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  const { frame } = peakOf(steps);
  assert.match(
    r.out,
    new RegExp(
      `^gate determinism: fail: 1 of 3 scene\\(s\\) differ between two renders, first: ${steps.start.toFixed(2)} s steps: frame ${frame} \\(${(frame / 30).toFixed(2)} s\\) renders differently twice, sha256 [0-9a-f]{12} vs [0-9a-f]{12}: `,
      "m",
    ),
  );
  assert.match(
    r.out,
    /^gates: \d pass, 1 fail, 1 pending; stop: determinism is red, a skill defect to report, no fix attempt, no video$/m,
  );
  assert.ok(!/next: fix attempt/.test(r.out), r.out);
  const g = record(fx);
  assert.ok(g.attempts >= 3, "the storyboard reads it as stopped");
  assert.equal(g.gates.determinism.status, "fail");
  assert.equal(g.gates.determinism.evidence.length, 1);
  // Both renders' files are the evidence.
  for (const f of g.gates.determinism.evidence[0].match(/\.cache\/\S+\.png/g))
    assert.ok(fs.existsSync(path.join(fx.dir, f)), f);
  assert.match(read(fx.dir, "gates.md"), /^## determinism$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
});

test("each moving scene gets a motion strip and record beside its contact sheet; a still scene gets a record that says so and no strip", () => {
  const first = fixture();
  assert.equal(renderUnjudged(first, SCRIPT).code, 1);
  const timeline = JSON.parse(read(first.dir, "timeline.json"));
  const starts = timeline.scenes.map((s) => s.start);
  // The same script times the same in a second fixture, whose middle scene is still.
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_STILL: JSON.stringify([starts[1]]),
  });
  assert.equal(r.code, 1, r.out + r.err);
  const dir = path.join(fx.dir, record(fx).gates.critic.sheets);
  timeline.scenes.forEach((s, i) => {
    assert.ok(fs.existsSync(path.join(dir, `${s.id}.png`)));
    const rec = JSON.parse(read(dir, `${s.id}.motion.json`));
    if (i === 1) {
      assert.ok(!fs.existsSync(path.join(dir, `${s.id}.motion.png`)));
      assert.equal(rec.still, true);
      assert.equal(rec.peak, null);
      assert.equal(rec.strip, null);
      assert.deepEqual(rec.seam, seamRecord(s.id));
      return;
    }
    const { first: f, n, frame } = peakOf(s);
    const from = stripStart(frame, f, n);
    assert.ok(fs.existsSync(path.join(dir, `${s.id}.motion.png`)));
    assert.deepEqual(rec, {
      still: false,
      peak: { frame, t: frameTime(frame, 30) },
      strip: {
        first: +(from / 30).toFixed(3),
        last: +((from + 11) / 30).toFixed(3),
      },
      seam: seamRecord(s.id),
      dead: [],
    });
    const cut = calls(fx, "strip").find((c) =>
      c.output.endsWith(`${s.id}.motion.png`),
    );
    assert.equal(cut.first, from);
  });
  // Two motion strips and two seam strips (the still scene hands over too).
  assert.equal(calls(fx, "strip").length, 4);
  // Cut only when absent: gating again cuts nothing.
  stage(fx, "render/render.mjs");
  assert.equal(calls(fx, "strip").length, 4);
  assert.equal(calls(fx, "sheet").length, 3);
});

test("verdicts cached in the old format are judged again, not refused by the new validator", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  const g = record(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  // The key the code before the verdict format change computed.
  const old = crypto
    .createHash("sha256")
    .update(g.render)
    .update(
      JSON.stringify([
        script.title,
        script.scenes.map((s) =>
          s.cites.map((ids) => ids.map((id) => [id, undefined])),
        ),
      ]),
    )
    .digest("hex")
    .slice(0, 16);
  assert.notEqual(old, g.gates.critic.key);
  const dir = path.join(fx.dir, ".cache", "critic", old);
  fs.mkdirSync(dir, { recursive: true });
  for (const s of script.scenes)
    fs.writeFileSync(
      path.join(dir, `${s.id}.json`),
      JSON.stringify({
        failures: [],
        scores: { clarity: 4, legibility: 5, fit: 4 },
      }),
    );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.ok(!/critic verdict/.test(r.err), r.err);
  assert.match(
    r.out,
    /^gate critic: pending: round 1 of 2, 0 of 3 scene\(s\) judged, /m,
  );
});

test("two old-format rounds recorded in gates.json are dropped, not read by the new validator", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  const g = record(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  // A record from before the format: two rounds, no format field.
  const rounds = ["a".repeat(16), "b".repeat(16)];
  delete g.gates.critic.format;
  g.gates.critic.rounds = rounds;
  fs.writeFileSync(path.join(fx.dir, "gates.json"), JSON.stringify(g));
  const dir = path.join(fx.dir, ".cache", "critic", rounds[1]);
  fs.mkdirSync(dir, { recursive: true });
  for (const s of script.scenes)
    fs.writeFileSync(
      path.join(dir, `${s.id}.json`),
      JSON.stringify({
        failures: [],
        scores: { clarity: 4, legibility: 5, fit: 4 },
      }),
    );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.ok(!/critic verdict/.test(r.err), r.err);
  assert.match(
    r.out,
    /^gate critic: pending: round 1 of 2, 0 of 3 scene\(s\) judged, /m,
  );
  assert.equal(record(fx).gates.critic.format, 4);
});
