// The gates stage's layout, contrast and caption band gates: each fixture built
// to fail fails its gate alone, and its passing twin passes (the canned
// backend's markers are in fake-backend-gates.mjs).
import { test } from "node:test";
import assert from "node:assert/strict";
import { gateLine, only, runGates, timed } from "./gates-lib.mjs";

const GATES = [
  "determinism",
  "layout",
  "contrast",
  "reading",
  "caption band",
  "anchors",
  "must and avoid",
];

test("a project of readable lines in the clear passes every gate, captions in the band included", () => {
  const r = runGates(timed());
  assert.equal(r.code, 0, r.out + r.err);
  for (const g of GATES) assert.equal(gateLine(r, g)?.slice(0, 4), "pass", g);
  assert.match(r.out, /^gates: 7 pass, 0 fail$/m);
});

test("a clipped line fails layout, naming its time and scene, and its fitting twin passes", () => {
  const r = runGates(timed({ context: "<p>a clipped line</p>" }));
  assert.equal(r.code, 1);
  only(r, "layout");
  assert.match(
    gateLine(r, "layout"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s context: text_box_overflow: "a clipped line" vs none, text >= 18 px, margin 5%$/,
  );
  assert.equal(runGates(timed({ context: "<p>a fitting line</p>" })).code, 0);
});

test("text under 18 px or outside the 5% margin fails layout, and text still fading in does not", () => {
  const small = runGates(timed({ hook: "<p>a tiny line</p>" }));
  only(small, "layout");
  assert.match(gateLine(small, "layout"), /s hook: "a tiny line" is 12 px/);
  const edge = runGates(timed({ hook: "<p>an edge line</p>" }));
  only(edge, "layout");
  assert.match(gateLine(edge, "layout"), /s hook: "an edge line" is outside/);
  const faint = runGates(timed({ hook: "<p>a faint tiny edge line</p>" }));
  assert.equal(faint.code, 0, faint.out);
});

test("a low contrast line fails contrast though HyperFrames grades it a warning, and its twin passes", () => {
  const r = runGates(timed({ recap: "<p>a low-contrast line</p>" }));
  assert.equal(r.code, 1);
  only(r, "contrast");
  assert.match(
    gateLine(r, "contrast"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s recap: "a low-contrast line" 2\.1:1 under 4\.5:1 vs WCAG AA 4\.5:1, 3:1 large$/,
  );
  assert.equal(runGates(timed({ recap: "<p>a strong line</p>" })).code, 0);
});

test("readable text in the bottom 220 px fails the caption band gate, painting behind it does not", () => {
  const r = runGates(timed({ hook: "<p>an in-band line</p>" }));
  assert.equal(r.code, 1);
  only(r, "caption band");
  assert.match(
    gateLine(r, "caption band"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s hook: "an in-band line" at y 900-948 \(3 samples\) vs no readable text in the bottom 220 px$/,
  );
  // fading text is not yet readable, and a decoration with no text is no text
  const behind = runGates(
    timed({ hook: '<p>a faint in-band line</p><div class="wash"></div>' }),
  );
  assert.equal(behind.code, 0, behind.out);
});
