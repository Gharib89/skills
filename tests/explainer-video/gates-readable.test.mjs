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
import { readable } from "../../skills/explainer-video/scripts/lib/layout.mjs";
import { sceneEvents } from "../../skills/explainer-video/scripts/gates/events.mjs";
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

test("a push-in that leaves a box past the safe area is judged once it ends, and fails", () => {
  const fx = fixture();
  // the margin title sits outside the safe area; the composed push-in carries
  // it only while it runs
  const r = renderUnjudged(fx, titled("edge"));
  assert.equal(r.code, 1, r.out + r.err);
  const hook = read(calls(fx, "events")[0].dir, "scenes", "hook.html");
  const [, start, end] = hook.match(
    /addLabel\("camera:start", ([\d.]+)\)\.addLabel\("camera:end", ([\d.]+)\)/,
  );
  assert.ok(+end > +start, "the hook scene composes a push-in");
  const first = record(fx).gates.layout.evidence[0];
  assert.match(first, /outside the safe margin/);
  assert.equal(firstAt(fx), +end, "judged from the push's end, not inside it");
});

test("a scene's seam holds the next scene's text back, its camera only its own", () => {
  const sc = [
    { id: "a", start: 0 },
    { id: "b", start: 4 },
  ];
  const { moving } = sceneEvents(
    { a: { seams: [[3, 5]], camera: [[0, 1]] } },
    sc,
  );
  assert.ok(moving("b", 4.5), "a's seam runs on into b");
  assert.ok(!moving("b", 0.5), "a's camera does not carry b");
  assert.ok(moving("a", 0.5));
  assert.ok(!moving("b", 5));
});

test("a camera push-in is no tween a dead beat reads, a zero-length tween neither", () => {
  const { moves } = sceneEvents(
    {
      b: {
        seams: [],
        camera: [[0, 5]],
        tweens: [
          [0, 5],
          [1, 2],
          [3, 3],
        ],
      },
    },
    [{ id: "b", start: 4 }],
  );
  assert.deepEqual(moves.b.tweens, [[5, 6]]);
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

test("a box the depth overlay blurs is not readable, one blurred by a pixel or less is", () => {
  const box = { opacity: 1, scene: "hook" };
  const still = () => false;
  assert.equal(readable({ ...box, blur: 0 }, 1, still), true);
  assert.equal(readable({ ...box, blur: 1 }, 1, still), true);
  assert.equal(readable({ ...box, blur: 4 }, 1, still), false);
});

test("the reading gate fails a box the camera carries off after 1.0 s, 1.2 s being what four words need", () => {
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT, events({ hook: { camera: [[1, 99]] } }));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate reading: fail: 2 finding\(s\), first: 0\.00 s hook: /m,
  );
  const found = record(fx).gates.reading;
  assert.equal(found.status, "fail");
  assert.deepEqual(found.evidence, [
    '0.00 s hook: "Issue to pull request": 1.0 s readable vs 1.2 s to read',
    '0.00 s hook: "One run, one merge": 1.0 s readable vs 1.2 s to read',
  ]);
});
