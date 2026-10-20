// The render stage through its process door, part 5: the Velocity Cut frame a
// profile with no grammar block plays (the open layout, glass over a colour
// field, grain, a vignette, depth blur and the velocity eases) and where a
// profile departs from it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ARABIC, DIAGRAMS, SCRIPT } from "./scene-file.mjs";
import { comp, fixture, profiled, render, tweens } from "./render-lib.mjs";

// The cards scene of SCRIPT with its first card emphasised at sentence 2.
const EMPHASISED = SCRIPT.replace(
  '{ "at": 3, "label": "Then", "value": "code" }\n    ]',
  '{ "at": 3, "label": "Then", "value": "code" }\n    ],\n    "emphasis": { "target": "Input", "at": 2 }',
);

const run = (text, grammar) => {
  const fx = fixture(text.replace("style: claude-code", "style: odd"));
  profiled(fx, "odd", grammar ? { grammar } : {});
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  return fx;
};

test("a profile with no grammar block composes the open layout with glass, field, grain, vignette and depth", () => {
  const fx = fixture(EMPHASISED);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const page = comp(fx);
  assert.doesNotMatch(page, /class="header"/);
  assert.match(page, /<div class="field"><i class="a"><\/i>/);
  assert.match(page, /filter: blur\(120px\)/);
  // its own layer, so damage from the scenes above never re-rasters it (#905)
  assert.match(page, /\.field \{[^}]*will-change: transform;/);
  assert.match(page, /<feTurbulence[^>]* seed="7"/);
  // an svg is 300 by 150 until sized: the grain must span the whole frame
  assert.match(page, /\.grain \{[^}]*width: 100%; height: 100%;/);
  assert.match(page, /<div class="vignette"><\/div>/);
  const steps = comp(fx, "scenes/steps.html");
  assert.match(
    steps,
    /\.content \{ position: absolute; left: 120px; top: 96px; width: 1680px; height: 772px; \}/,
  );
  assert.match(steps, /backdrop-filter: blur\(26px\) saturate\(1\.15\)/);
  // the depth blur: every item but the emphasised one, at the emphasis cue
  const depth = tweens(fx, "steps").filter(([sel]) => sel.includes(":not("));
  assert.equal(depth.length, 1);
  assert.deepEqual(depth[0][1], { filter: "blur(0px)" });
  assert.deepEqual(depth[0][2], { filter: "blur(4px)", duration: 0.35 });
});

test("the grain is the same bytes in two renders, its noise at a fixed seed", () => {
  const [a, b] = [0, 1].map(() => {
    const fx = fixture(SCRIPT);
    assert.equal(render(fx).code, 0);
    return comp(fx);
  });
  assert.equal(a, b);
});

test("itworx composes flat with a vignette and no glass, field, grain or depth", () => {
  const fx = fixture(EMPHASISED.replace("style: claude-code", "style: itworx"));
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const page = comp(fx);
  assert.match(page, /<div class="vignette"><\/div>/);
  assert.doesNotMatch(page, /<div class="field">|<svg class="grain"/);
  const steps = comp(fx, "scenes/steps.html");
  assert.doesNotMatch(steps, /backdrop-filter/);
  assert.match(steps, /background: var\(--panel\)/);
  assert.ok(!tweens(fx, "steps").some(([sel]) => sel.includes(":not(")));
});

test("a profile leaves an overlay out, or sets its blur to 0, and the page leaves it out or draws it unblurred", () => {
  const fx = run(EMPHASISED, { texture: { overlays: ["grain"] } });
  assert.doesNotMatch(comp(fx), /<div class="field">|<div class="vignette">/);
  assert.match(comp(fx), /<svg class="grain"/);
  assert.ok(!tweens(fx, "steps").some(([sel]) => sel.includes(":not(")));
  const flat = run(EMPHASISED, { texture: { depthBlur: 0, fieldBlur: 0 } });
  assert.match(comp(flat), /filter: blur\(0px\)/);
  assert.ok(!tweens(flat, "steps").some(([sel]) => sel.includes(":not(")));
});

test("a code scene takes no depth blur, its emphasis ring being the focus", () => {
  const fx = fixture(DIAGRAMS);
  assert.equal(render(fx).code, 0);
  assert.ok(!tweens(fx, "code").some(([sel]) => sel.includes(":not(")));
});

test("the bands layout keeps its header and its band from 178 px, mirrored right to left", () => {
  const fx = run(SCRIPT, { layout: "bands" });
  assert.match(comp(fx), /<div class="header" dir="ltr">/);
  assert.match(
    comp(fx, "scenes/steps.html"),
    /left: 120px; top: 178px; width: 1680px; height: 690px/,
  );
  const ar = run(ARABIC, { layout: "bands" });
  assert.match(comp(ar), /<div class="header" dir="rtl">/);
});

test("the velocity ease gives each reveal class its own fast-out ease, and soft keeps the one rise", () => {
  const fx = fixture(SCRIPT);
  assert.equal(render(fx).code, 0);
  const eases = (id) =>
    new Set(
      tweens(fx, id)
        .filter(([sel]) => !sel.startsWith(":is(") && !/^\.em/.test(sel))
        .map(([, , to]) => to.ease),
    );
  // a headline lands on power4, a card settles on power3, a terminal line snaps
  assert.ok(eases("hook").has("power4.out"));
  assert.deepEqual([...eases("steps")], ["power3.out"]);
  assert.ok(eases("gate").has("expo.out"));
  const soft = run(SCRIPT, { ease: "soft" });
  assert.deepEqual(
    [
      ...new Set(
        tweens(soft, "steps")
          .filter(([sel]) => !/^\.em/.test(sel))
          .map(([, , to]) => to.ease),
      ),
    ],
    ["power2.out"],
  );
});
