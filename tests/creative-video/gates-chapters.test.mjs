// The chapter titles gate: in a video in chapters, each chapter's first frame
// (its opener scene's frame 0) draws every word of the chapter's title, and a
// video without chapters has no such gate. The canned backend draws the text a
// scene file holds (fake-backend-gates.mjs), `hidden` at opacity 0.
import { test } from "node:test";
import assert from "node:assert/strict";
import { authored } from "../../skills/creative-video/maintainer/real-render-lib.mjs";
import { chapter, chaptered } from "./chapters-lib.mjs";
import {
  gateLine,
  only,
  record,
  runGates,
  supported,
  timed,
} from "./gates-lib.mjs";
import { exec, timing } from "./timing-lib.mjs";

// Four scenes in two chapters; `a` and `c` open them and draw `drawn.a` and
// `drawn.c`, the others one line.
function run(titles, drawn) {
  const html = (id) => authored(id, `<p>${drawn[id] ?? `${id} line`}</p>`);
  const fx = chaptered(
    ["a", "b", "c", "d"].map((id) => ({ id, frames: 1800, html: html(id) })),
    {
      chapters: [chapter(titles[0], "a", "b"), chapter(titles[1], "c", "d")],
    },
  );
  supported(fx);
  assert.equal(exec(timing, fx).code, 0);
  return runGates(fx);
}
const FLOOR = "each chapter's first frame draws every word of its title";

test("openers that draw their chapter's title pass the gate, case and punctuation aside", () => {
  const fx = run(["Why, then?", "How it works"], {
    a: "WHY then",
    c: "How it works!",
  });
  assert.equal(fx.code, 0, fx.out + fx.err);
  assert.equal(
    gateLine(fx, "chapter titles"),
    `pass: 0 finding(s) vs ${FLOOR}`,
  );
});

test("an opener that leaves a title word out fails the gate, naming the chapter, its opener and the missing words", () => {
  const r = run(["Why", "How it works"], { a: "Why", c: "How it" });
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "chapter titles");
  assert.equal(
    gateLine(r, "chapter titles"),
    `fail: 1 finding(s), first: 120.00 s c: chapter 2 "How it works" is not drawn on its first frame, missing works vs ${FLOOR}`,
  );
});

test("a title drawn at opacity 0 on the first frame is not drawn", () => {
  const r = run(["Hidden", "How"], { a: "hidden", c: "How" });
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "chapter titles");
  assert.match(
    gateLine(r, "chapter titles"),
    /first: 0\.00 s a: chapter 1 "Hidden" is not drawn on its first frame, missing hidden/,
  );
});

test("a video without chapters has no chapter titles gate", () => {
  const fx = timed();
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gateLine(r, "chapter titles"), undefined);
  assert.ok(!("chapter titles" in record(fx).gates));
});
