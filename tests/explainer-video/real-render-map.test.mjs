// The `canvas map` row of real-render.mjs samples the camera twice over the
// second scene's start: just after it begins to travel, and once it has settled.
// The travel into the second scene is the first scene's run past its duration;
// the second scene's own run is its seam out, which the last scene has none of.
import { test } from "node:test";
import assert from "node:assert/strict";
import { sampleTimes } from "../../skills/explainer-video/maintainer/real-render-map.mjs";

test("the settled sample falls after the whole travel into the second scene", () => {
  const scenes = [
    { start: 0, duration: 3, slot: 3.8 },
    { start: 3, duration: 3, slot: 3.8 },
  ];
  assert.deepEqual(sampleTimes(scenes), [3.1, 4.2]);
});

test("a last second scene, with no seam out, still gets the travel into it measured", () => {
  const scenes = [
    { start: 0, duration: 3, slot: 3.8 },
    { start: 3, duration: 3, slot: 3 },
  ];
  assert.deepEqual(sampleTimes(scenes), [3.1, 4.2]);
});
