// The determinism row of real-render.mjs names where two renders differ, so a
// failing row says which frames to look at (#917).
import { test } from "node:test";
import assert from "node:assert/strict";
import { differing } from "../../skills/explainer-video/maintainer/real-render-compare.mjs";

test("identical renders differ nowhere", () => {
  const a = ["x", "y", "z"];
  assert.deepEqual(differing(a, [[...a], [...a]]), [
    { n: 0, at: [] },
    { n: 0, at: [] },
  ]);
});

test("a render names the frames that differ, first and last read as a range", () => {
  const a = ["a", "b", "c", "d", "e"];
  const [one, two] = differing(a, [["a", "B", "c", "D", "e"], [...a]]);
  assert.deepEqual(one, { n: 2, at: [1, 3] });
  assert.deepEqual(two, { n: 0, at: [] });
});

test("a frame a render lacks differs once, and so does one it has beyond the first's last", () => {
  const [short, long] = differing(
    ["a", "b", "c"],
    [
      ["a", "b"],
      ["a", "b", "c", "d"],
    ],
  );
  assert.deepEqual(short, { n: 1, at: [2] });
  assert.deepEqual(long, { n: 1, at: [] });
});
