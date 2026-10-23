// real-render.mjs saves a frame of, and layout-checks, every scene of the
// fixture, and the product's determinism gate names the scenes that differ:
// the lists come from the fixture's scenes, so a scene added there is covered
// with no other edit (#937).
import { test } from "node:test";
import assert from "node:assert/strict";
import { renderedDifferently } from "../../skills/explainer-video/scripts/gates/scene.mjs";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import {
  countingIds,
  layoutIds,
  savedFrames,
} from "../../skills/explainer-video/maintainer/real-render-lists.mjs";

const timeline = FIXTURE.map(({ scene, seconds }, i) => ({
  id: scene.id,
  start: i * 4,
  duration: seconds,
}));
const ids = FIXTURE.map((p) => p.scene.id);

test("every fixture scene gets a saved frame, the custom scene included", () => {
  assert.deepEqual(
    savedFrames(timeline).map((f) => f.id),
    ids,
  );
  assert.ok(savedFrames(timeline).some((f) => f.id === "custom"));
});

test("a scene added to the fixture gets a saved frame, a layout check and no other edit", () => {
  const more = [
    ...FIXTURE,
    { scene: { ...FIXTURE[0].scene, id: "extra" }, seconds: 2 },
  ];
  const longer = [...timeline, { id: "extra", start: 100, duration: 2 }];
  assert.ok(savedFrames(longer).some((f) => f.id === "extra"));
  assert.ok(layoutIds(more).includes("extra"));
});

test("the saved frame lies inside its scene, settled 3 s in or on its last frame when it is shorter", () => {
  const frames = savedFrames([
    { id: "long", start: 10, duration: 6 },
    { id: "short", start: 20, duration: 2 },
  ]);
  assert.deepEqual(frames, [
    { id: "long", t: 13 },
    { id: "short", t: 21.967 },
  ]);
});

test("the custom scene gets a layout check on the real backend", () => {
  assert.ok(layoutIds(FIXTURE).includes("custom"));
  assert.deepEqual(layoutIds(FIXTURE), ids);
});

test("the count-up scenes are the fixture's stats and charts, English and Arabic", () => {
  assert.deepEqual(countingIds(FIXTURE), [
    "bars",
    "numbers",
    "arabic-line",
    "arabic-stat",
  ]);
});

test("the gate's findings name each scene whose two renders differ, and none when they match", () => {
  const found = (a, b) => ({
    frame: 90,
    t: 3,
    a,
    b,
    files: ["x-a.png", "x-b.png"],
  });
  const plan = [
    {
      sc: { id: "one", start: 0 },
      found: { determinism: found("aaa", "aaa") },
    },
    {
      sc: { id: "two", start: 4 },
      found: { determinism: found("aaa", "bbb") },
    },
  ];
  const lines = renderedDifferently(plan);
  assert.equal(lines.length, 1);
  assert.match(
    lines[0],
    /^4\.00 s two: frame 90 \(3\.00 s\) renders differently twice/,
  );
  assert.deepEqual(renderedDifferently(plan.slice(0, 1)), []);
});
