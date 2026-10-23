// real-render.mjs saves a frame of every scene of the fixture and layout-checks
// every scene: the lists come from the fixture's scenes, so a scene added there
// gets a frame and a layout check with no other edit (#937, #947).
import { test } from "node:test";
import assert from "node:assert/strict";
import { FIXTURE } from "../../skills/explainer-video/maintainer/real-render-fixture.mjs";
import {
  countingIds,
  layoutRuns,
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

test("a scene added to the fixture gets a saved frame and a layout check with no other edit", () => {
  const more = [
    ...FIXTURE,
    { scene: { ...FIXTURE[0].scene, id: "extra" }, seconds: 2 },
  ];
  assert.ok(savedFrames(composed(more)).some((f) => f.id === "extra"));
  assert.ok(
    layoutRuns(more).some(({ part }) =>
      part.some((p) => p.scene.id === "extra"),
    ),
  );
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

const laidOut = (fixture) =>
  layoutRuns(fixture).flatMap(({ part }) => part.map((p) => p.scene.id));

test("every fixture scene gets a layout check on the real backend, the custom scene included", () => {
  assert.deepEqual(laidOut(FIXTURE).toSorted(), ids.toSorted());
  assert.ok(laidOut(FIXTURE).includes("custom"));
});

test("the layout runs are one page a reading direction, as a run in that language composes it", () => {
  const runs = layoutRuns(FIXTURE);
  assert.deepEqual(
    runs.map((r) => r.dir),
    ["ltr", "rtl"],
  );
  for (const { dir, part } of runs)
    for (const p of part) assert.equal(p.dir ?? "ltr", dir, p.scene.id);
  const english = layoutRuns(FIXTURE.filter((p) => p.dir !== "rtl"));
  assert.deepEqual(
    english.map((r) => r.dir),
    ["ltr"],
  );
  const other = [...FIXTURE, { ...FIXTURE[0], dir: "other" }];
  assert.ok(layoutRuns(other).some((r) => r.dir === "other"));
});

test("the count-up scenes are the fixture's stats and charts, English and Arabic", () => {
  assert.deepEqual(countingIds(FIXTURE), [
    "bars",
    "numbers",
    "arabic-line",
    "arabic-stat",
  ]);
});
