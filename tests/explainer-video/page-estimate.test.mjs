// The storyboard page's render estimate: shown beside the brief, amber above
// the budget, never in the way of the board, with a rich card's added seconds.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  P,
  clone,
  sample,
  seen,
  session,
  shape,
  shapeProblems,
  submitDisabled,
} from "./page-lib.mjs";

const estimate = (v) =>
  v.match(/<section class="estimate[\s\S]*?<\/section>/)?.[0];
const withEstimate = (e) => {
  const b = sample("board-review");
  b.estimate = { ...b.estimate, ...e };
  return b;
};

test("the estimate shows its time against the budget, and the HyperFrames version it was measured on", () => {
  const v = P.view(
    session([withEstimate({ seconds: 390, budget: 600, over: false })]),
  );
  const e = estimate(v);
  assert.match(e, /<b>6 min 30 s<\/b> within a 10 min budget/);
  assert.match(e, /HyperFrames 0\.8\.169/);
  assert.ok(!/class="tag warn"/.test(e), "inside the budget is not amber");
  // beside the brief, ahead of it
  assert.ok(v.indexOf('class="estimate') < v.indexOf('class="brief'));
});

test("an estimate above the budget is flagged amber and the board still submits", () => {
  const S = session([withEstimate({ seconds: 720, budget: 600, over: true })]);
  const v = P.view(S);
  assert.match(
    estimate(v),
    /<span class="tag warn"><b>12 min<\/b> over a 10 min budget/,
  );
  assert.ok(!submitDisabled(v), "an estimate warns, it never refuses");
  assert.ok(P.canSubmit(S));
});

test("a rich card shows the seconds it adds, and a card with none to show says nothing", () => {
  const b = sample("board-finding");
  b.scenes.find((c) => c.rich).adds = 4.8;
  const v = P.view(session([b]));
  assert.equal([...v.matchAll(/adds <b>\+4\.8 s<\/b>/g)].length, 1);
  assert.equal([...v.matchAll(/data-adds/g)].length, 1);
});

test("a delivered board shows no estimate, the video being rendered", () => {
  assert.equal(
    estimate(P.view(session([sample("board-delivered")]))),
    undefined,
  );
});

test("the page reads the estimate fields, all documented, and every sample carries one", () => {
  for (const n of ["board-review", "board-finding", "board-gate-stop"]) {
    session([sample(n)]);
    assert.deepEqual(shapeProblems(clone(sample(n)), "board"), [], n);
  }
  for (const p of seen)
    assert.ok(shape.has(p), `page reads an undocumented field ${p}`);
  for (const p of [
    "board.estimate.seconds",
    "board.estimate.budget",
    "board.estimate.over",
    "board.estimate.hyperframes",
    "board.scenes[].adds",
  ])
    assert.ok(seen.has(p), `page never reads ${p}`);
});
