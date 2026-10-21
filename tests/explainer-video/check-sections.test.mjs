// The script gates and sections: the arc of a long video, and the opener's
// seconds.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, TITLE, check, fixture, line, say } from "./check-lib.mjs";

const LONG = ["length=6", "must=local gate", "avoid=pricing"];
const point = (id) => ({ ...SCENES[2], id });
// A 6 to 12 s opener: two sentences of twelve words, 98 characters, the budget
// of 8 s at the narrator's rate less two pauses.
const opener = (id) => ({
  id,
  role: "section",
  seconds: 8,
  sentences: [say(12), say(12, "[no-claim]")],
  visual: TITLE,
});
const [hook, why, , recap, bye] = SCENES;
const SECTIONED = [
  hook,
  why,
  opener("one"),
  point("a"),
  point("b"),
  opener("two"),
  point("c"),
  point("d"),
  recap,
  bye,
];
const WANT = "want hook, context, (section, point x 2 to 5)..., recap, end";

test("the arc of a long video is hook, context, sections of two to five points, recap, end", () => {
  const r = check(fixture({ scenes: SECTIONED, brief: LONG }));
  assert.equal(line(r, "arc"), "script arc: pass");
  // The opener's 8 s is no fault of the 12 to 30 s a scene runs: only the
  // total is short of six minutes.
  assert.equal(
    line(r, "budget"),
    "script budget: fail: the scenes run 112 s and the 1 s hold vs the brief's 360 s ±10%",
  );
});

test("a section is held to its place in the arc", () => {
  for (const [scenes, roles] of [
    [
      [hook, opener("one"), point("a"), point("b"), why, recap, bye],
      "hook, section, point, point, context, recap, end",
    ],
    [
      [hook, why, point("x"), ...SECTIONED.slice(2)],
      "hook, context, point, section, point, point, section, point, point, recap, end",
    ],
  ]) {
    const r = check(fixture({ scenes, brief: LONG }));
    assert.equal(r.code, 1);
    assert.equal(line(r, "arc"), `script arc: fail: roles ${roles}; ${WANT}`);
  }
});

test("a video over five minutes is cut into sections, and one of five minutes or less needs none", () => {
  let r = check(fixture({ brief: LONG }));
  assert.equal(
    line(r, "arc"),
    `script arc: fail: roles hook, context, point, recap, end; a video over 5 minutes is cut into sections: ${WANT}`,
  );
  r = check(fixture({ brief: ["length=5", "must=local gate"] }));
  assert.equal(line(r, "arc"), "script arc: pass");
});

// Compile refuses a section outside its bounds, so the gates meet one only in a
// script.json edited after it: `edit` rewrites a compiled one and checks it.
const edited = (change) => {
  const fx = fixture({
    scenes: [hook, why, opener("one"), point("a"), point("b"), recap, bye],
    brief: LONG,
  });
  const file = path.join(fx.dir, "script.json");
  const script = JSON.parse(fs.readFileSync(file, "utf8"));
  change(script);
  fs.writeFileSync(file, JSON.stringify(script));
  return check(fx);
};

test("the arc holds a section to two to five points, the bounds themselves included", () => {
  const arc = (n) =>
    line(
      edited((s) => {
        const points = s.scenes.filter((x) => x.role === "point");
        s.scenes.splice(
          s.scenes.indexOf(points[0]),
          points.length,
          ...Array.from({ length: n }, (_, i) => ({
            ...points[0],
            id: `p${i}`,
          })),
        );
      }),
      "arc",
    );
  for (const n of [2, 5]) assert.equal(arc(n), "script arc: pass");
  for (const n of [1, 6]) assert.match(arc(n), /^script arc: fail: roles /);
});

test("the budget holds an opener to 6 to 12 s, the bounds themselves included", () => {
  const out = (seconds) =>
    edited((s) => {
      s.scenes.find((x) => x.role === "section").seconds = seconds;
    }).out;
  for (const s of [6, 12]) assert.doesNotMatch(out(s), /one \S+ s is outside/);
  for (const s of [5.9, 12.1])
    assert.match(out(s), new RegExp(`one ${s} s is outside 6 to 12 s`));
});
