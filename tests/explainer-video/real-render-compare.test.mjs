// The determinism row of real-render.mjs names where two renders differ, so a
// failing row says which frames to look at, and keeps the renders' frame hash
// lists beside the frames (#917).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  describe,
  differing,
  keepHashLists,
} from "../../skills/explainer-video/maintainer/real-render-compare.mjs";

test("identical renders differ nowhere", () => {
  const a = ["x", "y", "z"];
  assert.deepEqual(differing(a, [[...a], [...a]]), [
    { n: 0, at: [], extra: 0 },
    { n: 0, at: [], extra: 0 },
  ]);
});

test("a render names the frames that differ, first and last read as a range", () => {
  const a = ["a", "b", "c", "d", "e"];
  const [one, two] = differing(a, [["a", "B", "c", "D", "e"], [...a]]);
  assert.deepEqual(one, { n: 2, at: [1, 3], extra: 0 });
  assert.deepEqual(two, { n: 0, at: [], extra: 0 });
});

test("a frame a render lacks differs once, and so does one it has beyond the first's last", () => {
  const [short, long] = differing(
    ["a", "b", "c"],
    [
      ["a", "b"],
      ["a", "b", "c", "d"],
    ],
  );
  assert.deepEqual(short, { n: 1, at: [2], extra: 0 });
  assert.deepEqual(long, { n: 1, at: [], extra: 1 });
});

test("the row's detail reads each render's count, its range, and any frames beyond the first's last", () => {
  const diffs = [
    { n: 0, at: [], extra: 0 },
    { n: 3, at: [1, 3], extra: 1 },
    { n: 2, at: [], extra: 2 },
  ];
  assert.equal(
    describe(diffs),
    "0 and 3 (frames 1 to 3, 1 beyond the first's last) and 2 (2 beyond the first's last)",
  );
});

test("the frame hash lists are kept in a folder made for them", () => {
  const dir = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "compare-test-")),
    "not",
    "yet",
  );
  const files = keepHashLists(
    { "whole-1": ["a", "b"], "whole-2": ["a", "B"] },
    dir,
  );
  assert.equal(files.length, 2);
  assert.equal(fs.readFileSync(files[1], "utf8"), "a\nB");
  assert.ok(files.every((f) => f.startsWith(dir)));
});
