// real-render.mjs saves a frame of, and layout-checks, every scene of the
// fixture: the lists come from the fixture's scenes, so a scene added there is
// covered with no other edit (#937).
import { test } from "node:test";
import assert from "node:assert/strict";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import {
  countingIds,
  layoutIds,
  savedFrames,
} from "../../skills/explainer-video/maintainer/real-render-lists.mjs";

// The composed timeline of a fixture: one scene after another.
const composed = (fixture) =>
  fixture.map(({ scene, seconds }, i) => ({
    id: scene.id,
    start: i * 4,
    duration: seconds,
  }));
const timeline = composed(FIXTURE);
const ids = FIXTURE.map((p) => p.scene.id);

test("every fixture scene gets a saved frame, the custom scene included", () => {
  assert.deepEqual(
    savedFrames(timeline).map((f) => f.id),
    ids,
  );
  assert.ok(savedFrames(timeline).some((f) => f.id === "custom"));
});

test("a scene added to the fixture gets a saved frame with no other edit, and a layout check when it is marked", () => {
  const more = [
    ...FIXTURE,
    { scene: { ...FIXTURE[0].scene, id: "extra" }, seconds: 2, layout: true },
    { scene: { ...FIXTURE[0].scene, id: "plain" }, seconds: 2 },
  ];
  assert.ok(savedFrames(composed(more)).some((f) => f.id === "extra"));
  assert.ok(layoutIds(more).includes("extra"));
  assert.ok(!layoutIds(more).includes("plain"));
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

test("a short scene starting between frames is saved on its own last frame, not the one before", () => {
  // 4.333333 + 1.433333 ends at 5.766666 s, so its last frame is 172, shown from
  // 5.7333 s: 5.733 would seek frame 171.
  assert.deepEqual(
    savedFrames([{ id: "merge", start: 4.333333, duration: 1.433333 }]),
    [{ id: "merge", t: 5.734 }],
  );
});

test("the custom scene gets a layout check on the real backend, with the scenes checked before it (#947 widens it to every scene)", () => {
  assert.deepEqual(layoutIds(FIXTURE), [
    "diagram",
    "custom",
    "browser",
    "arabic-browser",
    "excerpt",
    "arabic-excerpt",
    "code-excerpt",
    "stack",
    "canvas",
    "arabic-canvas",
  ]);
});

test("the count-up scenes are the fixture's stats and charts, English and Arabic", () => {
  assert.deepEqual(countingIds(FIXTURE), [
    "bars",
    "numbers",
    "arabic-line",
    "arabic-stat",
  ]);
});
