// The storyboard page's recommendation: every card opens on the agent's pick,
// Approve all takes the board, a note flips a card to Revise, a finding shows
// with its proposed fix, and the overview counts what the board document holds.
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

test("every card opens on the agent's recommendation, so one Approve all submits the board approved", () => {
  const S = session([sample("board-review")]);
  const v = P.view(S);
  assert.deepEqual(clone(P.answersDoc(S).scenes.map((s) => s.choice)), [
    "approve",
    "approve",
    "approve",
  ]);
  assert.ok(!submitDisabled(v), "nothing is left to answer");
  assert.match(v, /data-act="approve-all"/);
  // Approve all takes a board whose answers were changed too.
  P.ACT.choose(S, { id: "steps", choice: "revise" });
  P.ACT.approveAll(S);
  const a = clone(P.answersDoc(S));
  assert.deepEqual(shapeProblems(a, "answers"), []);
  assert.deepEqual(
    a.scenes.map((s) => s.choice),
    ["approve", "approve", "approve"],
  );
  assert.ok(P.canSubmit(S));
});

test("a note or an edited narration flips a card to Revise, and an unchanged narration does not", () => {
  const S = session([sample("board-review")]);
  const same = sample("board-review").scenes[0].narration;
  P.ACT.field(S, { id: "hook", field: "narration", value: same });
  P.ACT.field(S, { id: "hook", field: "note", value: "  " });
  assert.equal(P.answersDoc(S).scenes[0].choice, "approve");
  P.ACT.field(S, { id: "hook", field: "note", value: "slower" });
  assert.equal(P.answersDoc(S).scenes[0].choice, "revise");
  P.ACT.field(S, {
    id: "steps",
    field: "narration",
    value: "1. It reads the ticket. [ex-1]",
  });
  assert.equal(P.answersDoc(S).scenes[1].choice, "revise");
  assert.equal(P.answersDoc(S).scenes[2].choice, "approve");
  // The human can still approve over the flip.
  P.ACT.choose(S, { id: "hook", choice: "approve" });
  assert.equal(P.answersDoc(S).scenes[0].choice, "approve");
});

test("a card with a finding opens on Revise with the proposed fix shown, and Approve on it submits approved", () => {
  const board = sample("board-finding");
  const S = session([board]);
  const v = P.view(S);
  const gate = board.scenes[2];
  assert.equal(P.answersDoc(S).scenes[2].choice, "revise");
  for (const line of gate.finding.split("\n"))
    assert.ok(v.includes(line.replaceAll('"', "&quot;")), line);
  assert.ok(v.includes(gate.fix), "the proposed fix is shown");
  // A card with no finding shows none.
  assert.equal(v.split('class="finding"').length - 1, 1);
  P.ACT.choose(S, { id: "gate", choice: "approve" });
  assert.equal(P.answersDoc(S).scenes[2].choice, "approve");
});

test("Approve all submits every card approved, a card with a finding included", () => {
  const S = session([sample("board-finding")]);
  P.ACT.choose(S, { id: "hook", choice: "revise" });
  assert.equal(P.answersDoc(S).scenes[2].choice, "revise");
  P.ACT.approveAll(S);
  assert.deepEqual(clone(P.answersDoc(S).scenes.map((s) => s.choice)), [
    "approve",
    "approve",
    "approve",
  ]);
  assert.ok(P.canSubmit(S), "nothing is left to answer");
});

test("the overview shows every poster and counts rich, finding and changed cards as the board document does", () => {
  const board = sample("board-finding");
  const v = P.view(session([board]));
  const count = (k) =>
    +v.match(new RegExp(`data-count="${k}"[^>]*><b>(\\d+)</b>`))[1];
  assert.equal(count("rich"), board.scenes.filter((c) => c.rich).length);
  assert.equal(count("finding"), board.scenes.filter((c) => c.finding).length);
  assert.equal(
    count("changed"),
    board.scenes.filter((c) => c.status !== "approved").length,
  );
  assert.deepEqual(
    [count("rich"), count("finding"), count("changed")],
    [1, 1, 3],
  );
  const grid = v.match(/<section class="overview[\s\S]*?<\/section>/)[0];
  assert.equal(grid.split("<img").length - 1, board.scenes.length);
  // The gate stop's board counts its already approved cards out of the changed.
  const stop = sample("board-gate-stop");
  const w = P.view(session([stop]));
  assert.match(w, /data-count="changed"[^>]*><b>1<\/b>/);
  assert.match(w, /data-count="finding"[^>]*><b>1<\/b>/);
  assert.ok(
    !/class="overview/.test(P.view(session([sample("board-delivered")]))),
  );
});

test("the page reads the recommendation fields, all documented", () => {
  for (const p of seen)
    assert.ok(shape.has(p), `page reads an undocumented field ${p}`);
  for (const p of [
    "board.scenes[].recommendation",
    "board.scenes[].finding",
    "board.scenes[].fix",
    "board.scenes[].rich",
  ])
    assert.ok(seen.has(p), `page never reads ${p}`);
});
