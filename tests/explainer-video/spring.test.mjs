// The spring motion's closed form (lib/spring.mjs): a pure function of time,
// each class inside its overshoot and settle bounds, changes stacking with no
// jump.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SPRING,
  settleTime,
  springAt,
  step,
} from "../../skills/explainer-video/scripts/lib/spring.mjs";

const FRAME = 1 / 30;
const sample = (rule, to = 1.5, dt = 0.001) => {
  const out = [];
  for (let t = 0; t <= to; t += dt) out.push([t, step(rule, t)]);
  return out;
};

test("one t gives one value in order, reversed or shuffled", () => {
  const ts = Array.from({ length: 200 }, (_, i) => i * 0.007);
  for (const rule of Object.values(SPRING)) {
    const ordered = ts.map((t) => step(rule, t));
    const reversed = [...ts].reverse().map((t) => step(rule, t));
    const shuffled = ts.map((_, i) => ts[(i * 37) % ts.length]);
    assert.deepEqual(reversed.reverse(), ordered);
    assert.deepEqual(
      shuffled.map((t) => step(rule, t)),
      shuffled.map((t) => ordered[ts.indexOf(t)]),
    );
  }
});

test("the value is the from value at the start and exactly the target from the settle time on", () => {
  for (const rule of Object.values(SPRING)) {
    assert.equal(step(rule, 0), 0);
    assert.equal(step(rule, -1), 0);
    const s = settleTime(rule);
    for (const t of [s, s + FRAME, s + 10]) assert.equal(step(rule, t), 1);
    // the hand-off to the exact target is under a thousandth of the travel
    assert.ok(Math.abs(step(rule, s - 1e-9) - 1) < 0.001);
  }
});

// [class, most overshoot of the travel, latest settle seconds, overshoots]
for (const [cls, over, settle, humps] of [
  ["snap", 0.02, 0.3, 0],
  ["settle", 0.1, 0.5, 1],
  ["land", 0.2, 0.75, 1],
]) {
  test(`${cls} overshoots at most ${over * 100} percent and settles within ${settle} s`, () => {
    const pts = sample(SPRING[cls]);
    const peak = Math.max(...pts.map(([, v]) => v)) - 1;
    assert.ok(peak <= over, `overshoot ${peak}`);
    assert.ok(
      settleTime(SPRING[cls]) <= settle,
      `settle ${settleTime(SPRING[cls])}`,
    );
    // the classes with a soft or visible overshoot go over by more than 5 percent
    if (humps) assert.ok(peak > 0.05, `overshoot ${peak}`);
    // after its one overshoot the ring-back stays within 3 percent of the target
    const first = pts.findIndex(([, v]) => v > 1);
    const back = pts.findIndex(([, v], i) => i > first && v < 1);
    if (humps && back > 0)
      for (const [, v] of pts.slice(back))
        assert.ok(Math.abs(v - 1) < 0.03, `ring ${v}`);
  });
}

test("two changes on one property are continuous across the second and end on its target", () => {
  const rule = SPRING.settle;
  const changes = [
    [0, -20],
    [0.2, 30],
  ];
  const at = (t) => springAt(rule, 20, changes, t);
  assert.ok(Math.abs(at(0.2) - at(0.2 - 1e-9)) < 1e-6, "jumps at the change");
  // the frames either side of it differ by no more than one frame's travel at
  // the fastest the value moves
  let fastest = 0;
  for (let t = FRAME; t < 1; t += FRAME)
    fastest = Math.max(fastest, Math.abs(at(t) - at(t - FRAME)));
  assert.ok(Math.abs(at(0.2 + 1e-9) - at(0.2 - 1e-9)) <= fastest);
  assert.ok(Math.abs(at(0.2 + FRAME) - at(0.2 - FRAME)) <= 2 * fastest);
  const end = changes[1][0] + settleTime(rule);
  for (const t of [end, end + 1]) assert.equal(at(t), 30);
});
