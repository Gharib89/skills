// What a reference video's frames measure: edge sharpness, grain, and the
// motion summary (cut rate, blur at cuts, grain) built from them.
import test from "node:test";
import assert from "node:assert/strict";
import {
  GRAIN_FULL,
  measureMotion,
  noise,
  planStills,
  sharpness,
} from "../../skills/explainer-video/scripts/style/motion.mjs";

const W = 48;
const H = 36;
// A deterministic generator, so a noisy frame is the same every run.
const rng = (seed) => () =>
  (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;

// An image from a luma function of (x, y), as the decoded PPM carries it.
function image(fn) {
  const px = Buffer.alloc(W * H * 3);
  for (let y = 0; y < H; y++)
    for (let x = 0; x < W; x++)
      px.fill(
        Math.max(0, Math.min(255, Math.round(fn(x, y)))),
        (y * W + x) * 3,
        (y * W + x) * 3 + 3,
      );
  return { w: W, h: H, px };
}
const edge = () => image((x) => (x < W / 2 ? 40 : 215));
// The same edge spread over `r` columns: what a blurred frame holds.
const soft = (r) =>
  image((x) => 40 + 175 * Math.min(1, Math.max(0, (x - W / 2 + r) / (2 * r))));
const grainy = (amp) => {
  const r = rng(7);
  return image((x) => 128 + (r() - 0.5) * 2 * amp);
};

test("a hard edge is sharper than the same edge spread out", () => {
  assert.ok(sharpness(edge()) > 2 * sharpness(soft(6)));
});

test("noise reads grain in flat areas and ignores an edge", () => {
  assert.equal(noise(image(() => 128)), 0);
  assert.equal(noise(edge()), 0);
  const n = noise(grainy(10));
  assert.ok(n > 3 && n < 10, `noise ${n}`);
});

test("motion: cut rate, blur before each cut and grain from the steady frames", () => {
  const blurred = measureMotion({
    duration: 4,
    cuts: [1.5, 3],
    shots: [
      { before: soft(6), steady: edge() },
      { before: soft(6), steady: edge() },
    ],
  });
  assert.equal(blurred.cutsPerMinute, 30);
  assert.ok(blurred.blurAtCuts > 0.5, `blur ${blurred.blurAtCuts}`);
  assert.equal(blurred.grain, 0);

  const clean = measureMotion({
    duration: 4,
    cuts: [2],
    shots: [{ before: edge(), steady: edge() }],
  });
  assert.equal(clean.cutsPerMinute, 15);
  assert.equal(clean.blurAtCuts, 0);

  const noisy = measureMotion({
    duration: 2,
    cuts: [1],
    shots: [{ before: grainy(14), steady: grainy(14) }],
  });
  assert.ok(noisy.grain > 0.3 && noisy.grain <= 1, `grain ${noisy.grain}`);
  assert.ok(GRAIN_FULL > 0);
});

test("a video with no cut has a cut rate of 0, no blur to read, and still its grain", () => {
  const m = measureMotion({
    duration: 3,
    cuts: [],
    shots: [{ steady: image(() => 128) }],
  });
  assert.deepEqual(m, { cutsPerMinute: 0, blurAtCuts: 0, grain: 0 });
  const g = measureMotion({
    duration: 3,
    cuts: [],
    shots: [{ steady: grainy(14) }],
  });
  assert.ok(g.grain > 0.3);
});

test("the still plan reads each shot's middle and the frame before each cut", () => {
  const p = planStills({ duration: 6, cuts: [2, 4] });
  const at = (i) => p.times[i];
  assert.deepEqual(
    p.shots.map((s) => [
      at(s.steady),
      s.before === undefined ? null : at(s.before),
    ]),
    [
      [1, 1.92],
      [3, 3.92],
      [5, null],
    ],
  );
  // Both cuts get a strip: the frame before, at and after.
  assert.deepEqual(
    p.strips.map((s) => [s.cut, at(s.before), at(s.at), at(s.after)]),
    [
      [1, 1.92, 2, 2.08],
      [2, 3.92, 4, 4.08],
    ],
  );
});

test("the still plan keeps six shots and two strips of a video with many cuts", () => {
  const cuts = Array.from({ length: 20 }, (_, i) => i + 1);
  const p = planStills({ duration: 21, cuts });
  assert.equal(p.shots.length, 6);
  assert.equal(p.strips.length, 2);
  assert.deepEqual(
    p.strips.map((s) => s.cut),
    [1, 20],
  );
  assert.ok(p.times.every((t) => t >= 0 && t < 21));
});

test("the still plan of a video with no cut is one shot and no strip", () => {
  const p = planStills({ duration: 3, cuts: [] });
  assert.equal(p.shots.length, 1);
  assert.equal(p.strips.length, 0);
  assert.equal(p.times[p.shots[0].steady], 1.5);
});
