// The first-render estimate: render seconds from a rates table, worked by hand.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  BUDGET,
  estimate,
} from "../../skills/explainer-video/scripts/lib/estimate.mjs";

const RATES = { base: 2, texture: 0.5, live3d: 1, gates: 0.4 };
// A 10 s plain scene and a 20 s WebGL one: 30 video seconds.
const SCENES = [
  { id: "a", seconds: 10, webgl: false },
  { id: "b", seconds: 20, webgl: true },
];

test("the estimate is base, texture and gates over every video second plus live 3D over the WebGL scenes", () => {
  // 30 x (2 + 0.5 + 0.4) = 87, then 20 x 1 = 20
  const e = estimate(SCENES, RATES, { textured: true });
  assert.equal(e.seconds, 107);
  assert.equal(e.budget, 30 * BUDGET);
  assert.equal(e.over, false);
});

test("a style with no texture pays no texture rate", () => {
  // 30 x (2 + 0.4) = 72, then 20
  assert.equal(estimate(SCENES, RATES, { textured: false }).seconds, 92);
});

test("an estimate above 5 render seconds per video second is over, and one at it is not", () => {
  assert.equal(BUDGET, 5);
  // 30 x (4.5 + 0.5 + 0.4) = 162, then 20: 182 against 150
  const over = estimate(SCENES, { ...RATES, base: 4.5 }, { textured: true });
  assert.equal(over.seconds, 182);
  assert.equal(over.over, true);
  // 30 x (4.1 + 0.5 + 0.4) = 150 with live 3D at 0: exactly the budget
  const at = estimate(
    SCENES,
    { ...RATES, base: 4.1, live3d: 0 },
    { textured: true },
  );
  assert.equal(at.seconds, 150);
  assert.equal(at.over, false);
});

test("each scene's added seconds are its live 3D seconds, zero for one that draws none", () => {
  const e = estimate(SCENES, RATES, { textured: true });
  assert.deepEqual(e.adds, { a: 0, b: 20 });
});
