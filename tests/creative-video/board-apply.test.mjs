// The storyboard stage's apply, node board.mjs <run> apply <file>: what an
// answers file, the document or the text, asks the agent to do, and what it
// refuses.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { readJson } from "./timing-lib.mjs";
import { answersText, apply, build, ok, ready } from "./board-lib.mjs";

test("apply of an approval prints approved, and writes the normalized answers", () => {
  const fx = ready();
  ok(build(fx));
  const r = apply(fx, answersText(1, "Approved: the look"));
  ok(r);
  assert.equal(r.out, "board: approved; next: run the gates\n");
  const doc = readJson(path.join(fx.dir, "board", "answers-1.json"));
  assert.equal(doc.version, 1);
  assert.equal(doc.approve, true);
  assert.equal(doc.direction, null);
  assert.equal(doc.look, "");
  assert.deepEqual(doc.scenes, []);
  assert.ok(!Number.isNaN(Date.parse(doc.submittedAt)));
  // The same answers as the document the database holds.
  const j = apply(fx, {
    version: 1,
    submittedAt: "2026-10-28T10:00:00.000Z",
    approve: true,
    direction: null,
    look: "",
    scenes: [],
  });
  ok(j);
  assert.equal(j.out, "board: approved; next: run the gates\n");
});

test("apply of scene notes prints a redo line for each noted scene and only those", () => {
  const fx = ready();
  ok(build(fx));
  const r = apply(
    fx,
    answersText(
      1,
      "hook: make the first beat slower",
      "context: drop the second metaphor",
      "  and keep the question",
    ),
  );
  ok(r);
  assert.equal(
    r.out,
    [
      "board: redo hook: make the first beat slower",
      "board: redo context: drop the second metaphor",
      "  and keep the question",
      "board: next: re-author only hook, context, then build the board again",
      "",
    ].join("\n"),
  );
  assert.doesNotMatch(r.out, /approved|recap/);
  const doc = readJson(path.join(fx.dir, "board", "answers-1.json"));
  assert.deepEqual(doc.scenes, [
    { id: "hook", note: "make the first beat slower" },
    { id: "context", note: "drop the second metaphor\nand keep the question" },
  ]);
});

test("apply of a direction pick and of a look comment each name the whole chapter", () => {
  const fx = ready();
  ok(build(fx));
  let r = apply(fx, answersText(1, "Direction: kitchen"));
  ok(r);
  assert.equal(
    r.out,
    [
      "board: direction kitchen",
      "board: next: re-author the whole chapter, then build the board again",
      "",
    ].join("\n"),
  );
  r = apply(
    fx,
    answersText(1, "Look: warmer colours", "  and a lighter ground"),
  );
  ok(r);
  assert.equal(
    r.out,
    [
      "board: look: warmer colours",
      "  and a lighter ground",
      "board: next: re-author the whole chapter, then build the board again",
      "",
    ].join("\n"),
  );
});

test("a comment wins over an approval: the board is not approved", () => {
  const fx = ready();
  ok(build(fx));
  for (const lines of [
    ["Approved: the look", "Look: darker"],
    ["Approved: the look", "hook: slower"],
    ["Approved: the look", "Direction: plain"],
  ]) {
    const r = apply(fx, answersText(1, ...lines));
    ok(r);
    assert.doesNotMatch(r.out, /approved/);
    assert.match(r.out, /^board: next: re-author /m);
  }
});

test("apply refuses a stale version, an unknown scene or direction, the direction in use, a cut text, a line it cannot read and a document whose fields are not text", () => {
  const fx = ready();
  ok(build(fx));
  const refused = (answers, why) => {
    const r = apply(fx, answers);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(r.out, "");
  };
  refused(
    answersText(2, "Approved: the look"),
    /^board: these answers are of board 2, the latest is board 1$/m,
  );
  refused(answersText(1, "nope: slower"), /^board: no scene nope in board 1$/m);
  refused(
    answersText(1, "Direction: nope"),
    /^board: no direction nope in board 1$/m,
  );
  refused(
    {
      version: 1,
      approve: false,
      direction: null,
      look: "",
      scenes: [{ id: "nope", note: "x" }],
    },
    /^board: no scene nope in board 1$/m,
  );
  refused(
    answersText(1, "hook: slower", "[cut to fit: read answers/board-1]"),
    /^board: the answers were cut to fit a comment: read answers\/board-1 from the database$/m,
  );
  refused(
    answersText(1, "Approved: the look", "this is not a line"),
    /^board: cannot read this answers line: this is not a line$/m,
  );
  refused(
    "hello",
    /^board: not an answers text: its first line is not the header$/m,
  );
  refused("{ not json", /^board: the answers document is not valid JSON/m);
  refused(
    answersText(1, "Direction: switch"),
    /^board: direction switch is the one in use: pick another, or none$/m,
  );
  refused(
    { version: 1, scenes: [null] },
    /^board: the answers document's scenes hold an entry that is not \{ id, note \}$/m,
  );
  refused(
    { version: 1, scenes: [{ id: "hook", note: { x: 1 } }] },
    /^board: the answers document's scenes hold an entry that is not \{ id, note \}$/m,
  );
  refused(
    { version: 1, look: ["warmer"] },
    /^board: the answers document's look is not text$/m,
  );
  refused(
    { version: 1, direction: 3 },
    /^board: the answers document's direction is not text$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "board", "answers-1.json")));
});

test("apply reads a text with CRLF endings and a leading blank line, and a scene with an empty note asks nothing", () => {
  const fx = ready();
  ok(build(fx));
  let r = apply(
    fx,
    "\r\n" +
      answersText(1, "Direction: kitchen", "hook: slower").replaceAll(
        "\n",
        "\r\n",
      ),
  );
  ok(r);
  assert.match(r.out, /^board: direction kitchen$/m);
  assert.match(r.out, /^board: redo hook: slower$/m);
  r = apply(fx, {
    version: 1,
    look: "  ",
    scenes: [{ id: "hook", note: " " }],
  });
  ok(r);
  assert.equal(
    r.out,
    "board: these answers approve nothing and comment on nothing\n",
  );
  assert.deepEqual(
    readJson(path.join(fx.dir, "board", "answers-1.json")).scenes,
    [],
  );
});

test("apply refuses before any board is built", () => {
  const fx = ready();
  const r = apply(fx, answersText(1, "Approved: the look"));
  assert.equal(r.code, 1);
  assert.match(r.err, /^board: no board built yet: run build first$/m);
});
