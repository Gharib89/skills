// The storyboard of a video in chapters (#1015): one chapter per plan entry,
// cards only for the scene files authored so far, a later chapter being
// authored while the first is shown, and the guard that admits its new scene
// files but still refuses an edit to a scene the person saw and did not comment.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calls, readJson } from "./timing-lib.mjs";
import { compose, timeline } from "./gates-lib.mjs";
import { cited } from "./support-lib.mjs";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";
import { answersText, apply, build, built, ok, ready } from "./board-lib.mjs";

const mmss = (s) =>
  `${Math.floor(Math.round(s) / 60)}:${String(Math.round(s) % 60).padStart(2, "0")}`;

// A timed run folder planned in chapters: script.json's `chapters` and
// timeline.json's, as the timing stage writes them. `plan` lists each
// chapter's title, focus and scene ids; `unauthored` the scene files not
// written yet.
function chaptered(plan, unauthored = []) {
  const fx = ready();
  const file = path.join(fx.dir, "script.json");
  const script = readJson(file);
  script.chapters = plan;
  fs.writeFileSync(file, JSON.stringify(script));
  const tfile = path.join(fx.dir, "timeline.json");
  const tl = readJson(tfile);
  const at = (id) => tl.scenes.find((s) => s.id === id);
  tl.chapters = plan.map((c, i) => {
    const last = at(c.scenes.at(-1));
    return {
      n: i + 1,
      title: c.title,
      start: at(c.scenes[0]).start,
      end: last.start + last.duration,
      scenes: c.scenes,
    };
  });
  fs.writeFileSync(tfile, JSON.stringify(tl));
  for (const id of unauthored)
    fs.rmSync(path.join(fx.dir, "project", "compositions", `${id}.html`));
  return fx;
}

const TWO = [
  { title: "The loop", focus: "what a loop is", scenes: ["hook", "context"] },
  { title: "The wrap", focus: "how it ends", scenes: ["recap"] },
];
const THREE = [
  { title: "One", focus: "first", scenes: ["hook"] },
  { title: "Two", focus: "second", scenes: ["context"] },
  { title: "Three", focus: "third", scenes: ["recap"] },
];
const GROWING = [
  { title: "One", focus: "first", scenes: ["hook"] },
  { title: "Two", focus: "second", scenes: ["context", "recap"] },
];

test("two chapters with only the first authored: both listed, cards for the first alone, the later one awaiting", () => {
  const fx = chaptered(TWO, ["recap"]);
  const r = build(fx);
  ok(r);
  const doc = built(fx);
  const tl = timeline(fx);
  assert.deepEqual(doc.chapters, [
    { n: 1, title: "The loop", status: "awaiting" },
    { n: 2, title: "The wrap", status: "awaiting" },
  ]);
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.chapter]),
    [
      ["hook", 1],
      ["context", 1],
    ],
  );
  assert.deepEqual(
    doc.plan.map((p) => [p.chapter, p.title, p.focus, p.status]),
    [
      [1, "The loop", "what a loop is", "awaiting"],
      [2, "The wrap", "how it ends", "awaiting"],
    ],
  );
  assert.equal(doc.length, mmss(tl.total));
  // Stills are taken for the scenes shown only.
  const shot = calls(fx).find((c) => c.call === "snapshot");
  const times = [
    ...new Set(
      tl.scenes
        .filter((s) => s.id !== "recap")
        .flatMap((s) => Object.values(sampleTimes(s))),
    ),
  ].sort((a, b) => a - b);
  assert.deepEqual(shot.times, times);
  assert.match(r.out, /\(2 scenes, \d+ stills, 0 changed\)/);
});

test("three chapters with only the first authored: every chapter in the plan, one card, the later two awaiting", () => {
  const fx = chaptered(THREE, ["context", "recap"]);
  ok(build(fx));
  const doc = built(fx);
  assert.deepEqual(
    doc.chapters.map((c) => [c.n, c.title, c.status]),
    [
      [1, "One", "awaiting"],
      [2, "Two", "awaiting"],
      [3, "Three", "awaiting"],
    ],
  );
  assert.deepEqual(
    doc.scenes.map((s) => s.id),
    ["hook"],
  );
  assert.deepEqual(
    doc.plan.map((p) => p.chapter),
    [1, 2, 3],
  );
});

test("a later chapter with some of its scene files is authoring, and shows the cards it has", () => {
  const fx = chaptered(GROWING, ["recap"]);
  ok(build(fx));
  const doc = built(fx);
  assert.deepEqual(
    doc.chapters.map((c) => [c.n, c.status]),
    [
      [1, "awaiting"],
      [2, "authoring"],
    ],
  );
  assert.deepEqual(
    doc.plan.map((p) => p.status),
    ["awaiting", "authoring"],
  );
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.chapter]),
    [
      ["hook", 1],
      ["context", 2],
    ],
  );
});

test("a chapter whose files are all there is awaiting again, and every scene carries its chapter", () => {
  const fx = chaptered(GROWING);
  ok(build(fx));
  const doc = built(fx);
  assert.deepEqual(
    doc.scenes.map((s) => [s.id, s.chapter]),
    [
      ["hook", 1],
      ["context", 2],
      ["recap", 2],
    ],
  );
  assert.deepEqual(
    doc.chapters.map((c) => c.status),
    ["awaiting", "awaiting"],
  );
});

test("the plan row's length is the chapter's span in the timeline, and its sources the ones its scenes cite", () => {
  const fx = chaptered(TWO);
  fs.writeFileSync(
    path.join(fx.dir, "excerpts.json"),
    JSON.stringify({
      sources: [
        { id: "s1", title: "Ship docs" },
        { id: "s2", title: "The loop paper" },
        { id: "s3", title: "Never cited" },
      ],
      excerpts: [
        { id: "ex-1", source: "s1", text: "a" },
        { id: "ex-2", source: "s2", text: "b" },
        { id: "ex-3", source: "s3", text: "c" },
      ],
    }),
  );
  const file = path.join(fx.dir, "script.json");
  const script = readJson(file);
  script.scenes = cited(script.scenes, {
    hook: [["ex-2"]],
    context: [["ex-1"], ["ex-2"]],
    recap: [["ex-1"]],
  });
  fs.writeFileSync(file, JSON.stringify(script));
  ok(build(fx));
  const plan = built(fx).plan;
  const tl = timeline(fx);
  assert.deepEqual(
    plan.map((p) => p.length),
    tl.chapters.map((c) => mmss(c.end - c.start)),
  );
  assert.deepEqual(plan[0].sources, ["The loop paper", "Ship docs"]);
  assert.deepEqual(plan[1].sources, ["Ship docs"]);
});

test("chapter 1's scene files must all exist, whatever the later chapters hold", () => {
  const fx = chaptered(TWO, ["context"]);
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "board: no compositions/context.html: author each scene file\n",
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "1.json")));
});

test("a scene of a later chapter with no storyboard.json entry yet is no refusal while its file is missing, and is once its file exists", () => {
  const fx = chaptered(TWO, ["recap"]);
  const file = path.join(fx.dir, "storyboard.json");
  const sb = readJson(file);
  delete sb.scenes.recap;
  fs.writeFileSync(file, JSON.stringify(sb));
  ok(build(fx));
  compose(fx, "recap", "<p>recap line</p>");
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: storyboard\.json: no entry for scene recap$/m);
});

test("after a comment on one scene, a later chapter's newly authored scene files build, and the board lists them", () => {
  const fx = chaptered(GROWING, ["context", "recap"]);
  ok(build(fx));
  ok(apply(fx, answersText(1, "Approved: the look", "hook: slower")));
  compose(fx, "hook", "<p>hook, slower</p>");
  compose(fx, "context", "<p>context line</p>");
  const r = build(fx);
  ok(r);
  assert.equal(built(fx, 2).chapters[1].status, "authoring");
  compose(fx, "recap", "<p>recap line</p>");
  ok(build(fx));
  const three = built(fx, 3);
  assert.deepEqual(
    three.scenes.map((s) => [s.id, s.chapter, s.changed]),
    [
      ["hook", 1, true],
      ["context", 2, true],
      ["recap", 2, true],
    ],
  );
  assert.equal(three.chapters[1].status, "awaiting");
});

test("an uncommented chapter 1 scene that changed is still refused beside a later chapter's new files", () => {
  const fx = chaptered(TWO, ["recap"]);
  ok(build(fx));
  ok(apply(fx, answersText(1, "hook: slower")));
  compose(fx, "recap", "<p>recap line</p>");
  compose(fx, "context", "<p>context changed on its own</p>");
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "board: context changed, but board 1's comments named only hook: re-author only those scenes\n",
  );
});

test("a later chapter's scene that was on the answered board and changed uncommented is still refused", () => {
  const fx = chaptered(TWO);
  ok(build(fx));
  ok(apply(fx, answersText(1, "hook: slower")));
  compose(fx, "recap", "<p>recap changed on its own</p>");
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err,
    "board: recap changed, but board 1's comments named only hook: re-author only those scenes\n",
  );
});

test("a video with no chapters is one chapter, as before", () => {
  const fx = ready();
  ok(build(fx));
  const doc = built(fx);
  assert.deepEqual(
    doc.chapters.map((c) => c.n),
    [1],
  );
  assert.ok(doc.scenes.every((s) => s.chapter === 1));
});
