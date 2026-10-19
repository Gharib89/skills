// The video gates through their process doors, part 6: what the layout gate
// judges (a box only while readable), where it samples (the 0.5 s grid plus the
// timeline's events), the scene's fullest moment on the contact sheet and the
// determinism frame outside the seams.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  frameTime,
  sampleTimes,
  sceneFrames,
} from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  calls,
  fixture,
  read,
  record,
  renderUnjudged,
  titled,
} from "./gates-lib.mjs";

const events = (e) => ({ EXPLAINER_VIDEO_FAKE_EVENTS: JSON.stringify(e) });
const scenes = (fx) => JSON.parse(read(fx.dir, "timeline.json")).scenes;
// The seconds the layout gate's first finding in the hook scene opens with.
const firstAt = (fx) =>
  +record(fx).gates.layout.evidence[0].match(/^([\d.]+) s hook:/)[1];
const sheetOf = (fx, id) =>
  calls(fx, "sheet").find((c) => c.output.endsWith(`${id}.png`));

test("a box mid-reveal is not judged, and is judged once fully shown", () => {
  const fx = fixture();
  const r = renderUnjudged(fx, titled("tiny fading"));
  assert.equal(r.code, 1, r.out + r.err);
  // The box is mid-reveal until 1 s: the 0 and 0.5 s samples skip it.
  assert.equal(firstAt(fx), 1);
});

test("a HyperFrames finding on a box mid-reveal is held back too", () => {
  const fx = fixture();
  // The fake check flags a "clipped" box at every sample, shown or not.
  const r = renderUnjudged(fx, titled("clipped fading"));
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(firstAt(fx), 1);
});

test("the gate's samples include every timeline event of the scene, one per whole frame", () => {
  const fx = fixture();
  // 0.69 and 0.7 are the one frame 21; 1.234 is frame 38.
  const r = renderUnjudged(fx, titled("tiny fading"), {
    ...events({ hook: { ends: [0.69, 0.7, 1.234] } }),
    EXPLAINER_VIDEO_FAKE_FADE_END: "0.7",
  });
  assert.equal(r.code, 1, r.out + r.err);
  const times = calls(fx, "probe")[0].times;
  assert.equal(new Set(times).size, times.length);
  for (const f of [21, 38]) assert.ok(times.includes(frameTime(f, 30)), `${f}`);
  assert.ok(!times.includes(0.69), "an event is read as the frame it takes");
  // The box is fully shown at 0.7 s: the event's sample is the first judged.
  assert.equal(firstAt(fx), 0.7);
});

test("a box in a seam or carried by the camera is not judged there", () => {
  for (const kind of ["seams", "camera"]) {
    const fx = fixture();
    const r = renderUnjudged(
      fx,
      titled("tiny"),
      events({ hook: { [kind]: [[0, 2]] } }),
    );
    assert.equal(r.code, 1, r.out + r.err);
    assert.ok(firstAt(fx) >= 2, `${kind}: judged at ${firstAt(fx)}`);
  }
});

test("the contact sheet's fourth frame is the fullest moment, the latest of tied samples", () => {
  const fade = { EXPLAINER_VIDEO_FAKE_FADE_END: "0.7" };
  // The box's words count once it is fully shown, so every later sample ties.
  const open = fixture();
  assert.equal(renderUnjudged(open, titled("fading"), fade).code, 1);
  const hook = scenes(open)[0];
  const last = sampleTimes({ ...hook, fps: 30 }).at(-1);
  assert.equal(sheetOf(open, "hook").fullest, Math.round(last * 30));
  // A seam over the scene's close takes those samples out of the tie.
  const seam = 1.5;
  const fx = fixture();
  const r = renderUnjudged(fx, titled("fading"), {
    ...fade,
    ...events({ hook: { seams: [[seam, 99]] } }),
  });
  assert.equal(r.code, 1, r.out + r.err);
  const before = sampleTimes({ ...scenes(fx)[0], fps: 30 }).filter(
    (t) => t < seam,
  );
  assert.equal(sheetOf(fx, "hook").fullest, Math.round(before.at(-1) * 30));
});

test("the determinism frame lies outside every seam window of its scene", () => {
  const plain = fixture();
  assert.equal(renderUnjudged(plain, SCRIPT).code, 1);
  const steps = scenes(plain)[1];
  const { first, n } = sceneFrames({ ...steps, fps: 30 });
  // The fake scene's peak is frame first + n/3 + 1: a seam covers it.
  const peak = first + Math.floor(n / 3) + 1;
  const window = [(peak - 2) / 30, (peak + 3) / 30];
  const fx = fixture();
  // Events are in scene seconds.
  const local = window.map((t) => t - steps.start);
  const r = renderUnjudged(fx, SCRIPT, events({ steps: { seams: [local] } }));
  assert.equal(r.code, 1, r.out + r.err);
  const t = calls(fx, "frame")[2].t;
  assert.ok(t < window[0] || t >= window[1], `${t} in ${window}`);
});
