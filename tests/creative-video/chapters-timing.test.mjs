// The chapter plan in the timing stage (render/timing.mjs): script.json's
// `chapters` held to the scenes and to 2 to 6 minutes a chapter, written into
// timeline.json on the frame grid, and the root hosting only the scene files
// that exist.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { chapter, chaptered, MIN, setPlan } from "./chapters-lib.mjs";
import { exec, hf, project, read, readJson, timing } from "./timing-lib.mjs";

const four = (frames = [1800, 1800, 1800, 1800]) =>
  ["a", "b", "c", "d"].map((id, i) => ({ id, frames: frames[i] }));
const PLAN = [chapter("Why", "a", "b"), chapter("How", "c", "d")];
const timeline = (fx) => readJson(path.join(fx.dir, "timeline.json"));

function refused(fx, why) {
  const r = exec(timing, fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, why);
  assert.ok(!fs.existsSync(path.join(fx.dir, "timeline.json")));
}

test("a script with chapters writes each chapter's number, title, window on the grid and scenes into the timeline; one without writes none", () => {
  const fx = chaptered(four(), { chapters: PLAN });
  const r = exec(timing, fx);
  assert.equal(r.code, 0, r.out + r.err);
  const tl = timeline(fx);
  assert.deepEqual(tl.chapters, [
    { n: 1, title: "Why", start: 0, end: 120, scenes: ["a", "b"] },
    { n: 2, title: "How", start: 120, end: 241, scenes: ["c", "d"] },
  ]);
  assert.equal(tl.chapters[0].end, tl.scenes[2].start);
  assert.equal(tl.chapters[1].end, tl.total);
  setPlan(fx, undefined);
  assert.equal(exec(timing, fx).code, 0);
  assert.ok(!("chapters" in timeline(fx)));
});

test("a brief over 6 minutes with no chapters is refused, and 6 minutes is not", () => {
  const fx = chaptered(four(), { brief: { length: 6.5 } });
  refused(
    fx,
    /^timing: brief\.json asks for 6\.5 minutes, over 6: plan the video in chapters/,
  );
  fs.writeFileSync(path.join(fx.dir, "brief.json"), '{"length":6}');
  assert.equal(exec(timing, fx).code, 0);
});

test("a scene in no chapter, in two, unknown, or out of order is refused, naming it", () => {
  const cases = [
    [
      [chapter("Why", "a", "b"), chapter("How", "c")],
      /scene d is in no chapter/,
    ],
    [
      [chapter("Why", "a", "b"), chapter("How", "b", "c", "d")],
      /scene b is in two chapters/,
    ],
    [
      [chapter("Why", "a", "b"), chapter("How", "c", "d", "e")],
      /chapter 2 names scene e, which script\.json lacks/,
    ],
    [
      [chapter("Why", "a", "c"), chapter("How", "b", "d")],
      /chapters are not in scene order: found scene c where script\.json has b/,
    ],
    [
      [chapter("Why", "c", "d"), chapter("How", "a", "b")],
      /chapters are not in scene order/,
    ],
  ];
  for (const [plan, why] of cases) {
    const fx = chaptered(four(), { chapters: plan });
    refused(fx, new RegExp(`^timing: ${why.source}`));
  }
});

test("a blank title or a chapter with no scenes is refused", () => {
  refused(
    chaptered(four(), {
      chapters: [chapter("Why", "a", "b"), chapter("  ", "c", "d")],
    }),
    /^timing: chapter 2 has no title/,
  );
  refused(
    chaptered(four(), {
      chapters: [chapter("Why", "a", "b", "c", "d"), chapter("How")],
    }),
    /^timing: chapter 2 "How" has no scenes/,
  );
});

test("a chapter of 108 s passes and one frame less is refused, the closing hold counted on the last chapter, naming the chapter and its seconds; a single chapter has no minimum", () => {
  // Chapter 2 is c and d and the 30 frame hold: 1800 + d + 30 frames.
  const lastScene = (d) =>
    chaptered(four([1800, 1800, 1800, d]), { chapters: PLAN });
  assert.equal(exec(timing, lastScene(MIN - 1800 - 30)).code, 0);
  const r = exec(timing, lastScene(MIN - 1800 - 31));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^timing: chapter 2 "How" is 107\.97 s, outside 2 to 6 minutes within 10% \(108 to 396 s\)/,
  );
  const one = chaptered(four([30, 30, 30, 30]), {
    chapters: [chapter("All", "a", "b", "c", "d")],
  });
  assert.equal(exec(timing, one).code, 0);
  assert.equal(timeline(one).chapters.length, 1);
});

test("a one-chapter plan over 6 minutes is refused, the 6 minute cap applying to every chapter", () => {
  const fx = chaptered(four([5400, 5400, 5400, 5400]), {
    chapters: [chapter("All", "a", "b", "c", "d")],
  });
  refused(
    fx,
    /^timing: chapter 1 "All" is 721\.00 s, over 6 minutes within 10% \(396 s\): a video this long plans 2 or more chapters$/m,
  );
});

test("a chapter of 396 s passes and one frame more is refused", () => {
  const MAX = 11880;
  const plan = [chapter("Why", "a"), chapter("How", "b", "c", "d")];
  const run = (first) =>
    exec(
      timing,
      chaptered(
        [
          { id: "a", frames: first },
          { id: "b", frames: 1800 },
          { id: "c", frames: 1800 },
          { id: "d", frames: 1800 },
        ],
        { chapters: plan },
      ),
    );
  assert.equal(run(MAX).code, 0);
  const r = run(MAX + 1);
  assert.equal(r.code, 1);
  assert.match(r.err, /^timing: chapter 1 "Why" is 396\.03 s, outside 2 to 6/);
});

test("the root hosts only the scene files that exist, and a file written later joins it", () => {
  const fx = chaptered(four(), { chapters: PLAN });
  assert.equal(exec(timing, fx).code, 0);
  fs.rmSync(project(fx, "compositions", "b.html"));
  fs.rmSync(project(fx, "compositions", "d.html"));
  assert.equal(exec(hf, fx, [fx.dir, "check"]).code, 0);
  const ids = (html) =>
    [...html.matchAll(/<div id="([a-z0-9-]+)" data-composition-id="\1"/g)].map(
      (m) => m[1],
    );
  assert.deepEqual(ids(read(project(fx, "index.html"))), [
    "a",
    "c",
    "captions",
  ]);
  fs.writeFileSync(project(fx, "compositions", "b.html"), "<!-- b -->");
  assert.equal(exec(hf, fx, [fx.dir, "check"]).code, 0);
  assert.deepEqual(ids(read(project(fx, "index.html"))), [
    "a",
    "b",
    "c",
    "captions",
  ]);
});
