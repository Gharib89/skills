// The first-render estimate: render seconds from a rates table, worked by hand.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  BUDGET,
  estimate,
  loadRates,
} from "../../skills/explainer-video/scripts/lib/estimate.mjs";

// A table file in a fresh folder, named as the shipped one is.
function tableFile(text) {
  const file = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "estimate-")),
    "render-rates.json",
  );
  fs.writeFileSync(file, text);
  return file;
}
const GOOD = { base: 1, texture: 0, live3d: 1, gates: 1, score: 1 };

const RATES = { base: 2, texture: 0.5, live3d: 1, gates: 0.4, score: 0.2 };
// A 10 s plain scene and a 20 s WebGL one: 30 voiced seconds, and the render
// holds the last frame one second more, so the video is 31 s.
const SCENES = [
  { id: "a", seconds: 10, webgl: false },
  { id: "b", seconds: 20, webgl: true },
];

test("the estimate is base, texture and gates over every video second plus live 3D over the WebGL scenes", () => {
  // 31 x (2 + 0.5 + 0.4) = 89.9, then 20 x 1 = 20
  const e = estimate(SCENES, RATES, { textured: true, score: "off" });
  assert.equal(e.seconds, 109.9);
  assert.equal(e.budget, 31 * BUDGET);
  assert.equal(e.over, false);
});

test("a style with no texture pays no texture rate", () => {
  // 31 x (2 + 0.4) = 74.4, then 20
  assert.equal(
    estimate(SCENES, RATES, { textured: false, score: "off" }).seconds,
    94.4,
  );
});

test("an estimate above 5 render seconds per video second is over, and one at it is not", () => {
  assert.equal(BUDGET, 5);
  // 31 x (4.5 + 0.5 + 0.4) = 167.4, then 20: 187.4 against 155
  const over = estimate(
    SCENES,
    { ...RATES, base: 4.5 },
    { textured: true, score: "off" },
  );
  assert.equal(over.seconds, 187.4);
  assert.equal(over.over, true);
  // 31 x (4.1 + 0.5 + 0.4) = 155 with live 3D at 0: exactly the budget
  const at = estimate(
    SCENES,
    { ...RATES, base: 4.1, live3d: 0 },
    { textured: true, score: "off" },
  );
  assert.equal(at.seconds, 155);
  assert.equal(at.over, false);
});

test("each scene's added seconds are its live 3D seconds, zero for one that draws none", () => {
  const e = estimate(SCENES, RATES, { textured: true, score: "off" });
  assert.deepEqual(e.adds, { a: 0, b: 20 });
});

test("a brief with the score on adds the synthesised rate over every video second", () => {
  const off = estimate(SCENES, RATES, { textured: true, score: "off" });
  // 31 x 0.2 = 6.2 over the 109.9 of the same video with the score off
  const on = estimate(SCENES, RATES, { textured: true, score: "on" });
  assert.equal(on.seconds, 116.1);
  assert.equal(on.unmeasured, false);
  assert.equal(off.unmeasured, false);
  // the score is a per-video-second cost: no scene's added seconds move
  assert.deepEqual(on.adds, off.adds);
  // an option left out is the brief's own default, on
  assert.equal(estimate(SCENES, RATES, { textured: true }).seconds, on.seconds);
});

test("a brief with ace-step adds the ace-step rate where the table holds one, and not the synthesised one", () => {
  // 31 x 3 = 93 over the 109.9 of the score-off estimate
  const e = estimate(
    SCENES,
    { ...RATES, aceStep: 3 },
    { textured: true, score: "ace-step" },
  );
  assert.equal(e.seconds, 202.9);
  assert.equal(e.unmeasured, false);
});

test("a brief with ace-step and no rate in the table gets the estimate without a score, marked not measured", () => {
  const e = estimate(SCENES, RATES, { textured: true, score: "ace-step" });
  assert.equal(e.seconds, 109.9);
  assert.equal(e.unmeasured, true);
});

test("a table loads when it names the version and each rate is a number of 0 or more", () => {
  const t = { hyperframes: "0.8.169", rates: GOOD };
  assert.deepEqual(loadRates(tableFile(JSON.stringify(t))), t);
});

test("a table may hold an ace-step rate, and loads without one", () => {
  const t = { hyperframes: "0.8.169", rates: { ...GOOD, aceStep: 3 } };
  assert.deepEqual(loadRates(tableFile(JSON.stringify(t))), t);
});

test("a table of the wrong shape is refused naming the file and the field", () => {
  const bad = (hyperframes, rates) => JSON.stringify({ hyperframes, rates });
  for (const [text, field] of [
    [
      bad("0.8.169", { base: 1, texture: 1, gates: 1, score: 1 }),
      "rates.live3d",
    ],
    [
      bad("0.8.169", { base: 1, texture: 1, live3d: 1, gates: 1 }),
      "rates.score",
    ],
    [bad("0.8.169", { ...GOOD, score: "1" }), "rates.score"],
    [bad("0.8.169", { ...GOOD, aceStep: -1 }), "rates.aceStep"],
    [bad("0.8.169", { ...GOOD, aceStep: "9" }), "rates.aceStep"],
    [bad("0.8.169", { ...GOOD, base: "1" }), "rates.base"],
    [bad("0.8.169", { ...GOOD, gates: -1 }), "rates.gates"],
    [bad("0.8.169", { ...GOOD, texture: null }), "rates.texture"],
    [JSON.stringify({ rates: GOOD }), "hyperframes"],
    [JSON.stringify({ hyperframes: "0.8.169" }), "rates"],
    ["{", "is not JSON"],
  ])
    assert.throws(
      () => loadRates(tableFile(text)),
      new RegExp(`render-rates\\.json: .*${field}`),
      field,
    );
});

test("a table that cannot be read is refused as unreadable, not as bad JSON", () => {
  const missing = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "estimate-")),
    "render-rates.json",
  );
  assert.throws(
    () => loadRates(missing),
    /render-rates\.json: cannot be read \(ENOENT/,
  );
});
