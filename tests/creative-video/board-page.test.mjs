// The storyboard page, board/page.js run headless in a vm: the answers it
// writes read back through board.mjs's parser to the same document, an
// approval is offered only while nothing is commented, and the page reads no
// field board-data.md does not define. The board is a real `board build`'s.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { readAnswers } from "../../skills/creative-video/scripts/board/answers.mjs";
import { boardDir, built, build, ok, ready } from "./board-lib.mjs";

const read = (f) => fs.readFileSync(f, "utf8");
const source = read(path.join(boardDir, "page.js"));
const ctx = vm.createContext({ console, TextEncoder });
vm.runInContext(source, ctx);
const B = ctx.Board;
const clone = (o) => JSON.parse(JSON.stringify(o));

const fx = ready();
ok(build(fx));
const doc = built(fx);

// What the page sends: the answers document minus its clock.
const sent = (S) => {
  const { submittedAt, ...rest } = clone(B.answersDoc(S));
  assert.ok(!Number.isNaN(Date.parse(submittedAt)));
  return rest;
};
const read_back = (S) => {
  const { submittedAt, ...rest } = readAnswers(B.answersText(B.answersDoc(S)));
  return rest;
};

test("page.js is one script that boots only where a document exists, and exposes its pure functions", () => {
  assert.doesNotThrow(() => new vm.Script(source));
  for (const f of [
    "newState",
    "ACT",
    "canApprove",
    "canSend",
    "answersDoc",
    "answersText",
    "capped",
    "outcome",
    "statusOf",
    "setAnswers",
    "view",
  ])
    assert.ok(f in B, f);
  const html = read(path.join(boardDir, "page.html"));
  assert.match(html, /<title>\{\{TITLE\}\}<\/title>/);
  assert.equal(html.split("{{TITLE}}").length, 2);
  assert.match(
    html,
    /<script type="application\/json" id="board">null<\/script>/,
  );
});

test("an approval, notes, a direction and a look each read back through apply's parser to the same document", () => {
  let S = B.newState(clone(doc));
  B.ACT.approve(S);
  assert.deepEqual(sent(S), {
    version: 1,
    approve: true,
    direction: null,
    look: "",
    scenes: [],
  });
  assert.deepEqual(read_back(S), sent(S));

  S = B.newState(clone(doc));
  B.ACT.note(S, {
    id: "hook",
    value: "slower\nwith a pause\n\nthen the question",
  });
  B.ACT.note(S, { id: "recap", value: "  shorter  " });
  B.ACT.note(S, { id: "context", value: "   " });
  assert.deepEqual(sent(S).scenes, [
    { id: "hook", note: "slower\nwith a pause\n\nthen the question" },
    { id: "recap", note: "shorter" },
  ]);
  assert.deepEqual(read_back(S), sent(S));

  S = B.newState(clone(doc));
  B.ACT.direction(S, { id: "kitchen" });
  assert.equal(sent(S).direction, "kitchen");
  assert.deepEqual(read_back(S), sent(S));

  S = B.newState(clone(doc));
  B.ACT.look(S, { value: "warmer\n  indented line\nlast" });
  B.ACT.direction(S, { id: "plain" });
  B.ACT.note(S, { id: "context", value: "x: y" });
  assert.deepEqual(read_back(S), sent(S));
  assert.equal(sent(S).look, "warmer\n  indented line\nlast");
});

test("the answers text names its board and carries only the lines that apply", () => {
  const S = B.newState(clone(doc));
  B.ACT.approve(S);
  assert.equal(
    B.answersText(B.answersDoc(S)),
    "creative-video: board 1 answers (database document answers/board-1)\nApproved: the look",
  );
  B.ACT.look(S, { value: "darker" });
  B.ACT.note(S, { id: "hook", value: "slower" });
  assert.equal(
    B.answersText(B.answersDoc(S)),
    "creative-video: board 1 answers (database document answers/board-1)\nLook: darker\nhook: slower",
  );
});

test("the look can be approved only while nothing is commented or picked", () => {
  const S = B.newState(clone(doc));
  assert.equal(B.canApprove(S), true);
  assert.equal(B.canSend(S), false);
  B.ACT.note(S, { id: "hook", value: "slower" });
  assert.deepEqual([B.canApprove(S), B.canSend(S)], [false, true]);
  B.ACT.note(S, { id: "hook", value: "  " });
  assert.equal(B.canApprove(S), true);
  B.ACT.look(S, { value: "warmer" });
  assert.deepEqual([B.canApprove(S), B.canSend(S)], [false, true]);
  B.ACT.look(S, { value: "" });
  B.ACT.direction(S, { id: "kitchen" });
  assert.deepEqual([B.canApprove(S), B.canSend(S)], [false, true]);
  // Selecting the pick again clears it, and the picked direction takes no pick.
  B.ACT.direction(S, { id: "kitchen" });
  B.ACT.direction(S, { id: "switch" });
  assert.deepEqual([B.canApprove(S), B.canSend(S)], [true, false]);
  assert.equal(B.answersDoc(S).direction, null);
  // An approval asked for, then a comment typed, is no approval.
  B.ACT.approve(S);
  B.ACT.look(S, { value: "darker" });
  assert.equal(B.answersDoc(S).approve, false);
});

test("a chapter is approved by an approving document in the database, and not by one that approves nothing", () => {
  const S = B.newState(clone(doc));
  assert.equal(B.statusOf(S, 1), "awaiting you");
  B.setAnswers(S, [{ version: 1, approve: false }]);
  assert.equal(B.statusOf(S, 1), "awaiting you");
  B.setAnswers(S, [{ version: 1, approve: true }]);
  assert.equal(B.statusOf(S, 1), "approved");
  const v = B.view(S);
  assert.match(v, /approved/);
  assert.doesNotMatch(v, /awaiting you/);
});

test("an approval of an earlier board still reads approved on a later board", () => {
  const later = clone(doc);
  later.version = 3;
  const S = B.newState(later);
  B.setAnswers(S, [{ version: 1, approve: true }]);
  assert.equal(B.statusOf(S, 1), "approved");
  B.setAnswers(S, [{ version: 2, approve: false }]);
  assert.equal(B.statusOf(S, 1), "awaiting you");
});

test("a local page reads approved once its approval is asked for, and not after a comment", () => {
  const S = B.newState(clone(doc));
  S.local = true;
  B.ACT.approve(S);
  assert.equal(B.statusOf(S, 1), "approved");
  B.ACT.look(S, { value: "darker" });
  assert.equal(B.statusOf(S, 1), "awaiting you");
});

test("the comment text is cut to 4096 bytes with a tail naming the answers document", () => {
  const short = "creative-video: board 1 answers\nLook: darker";
  assert.equal(B.capped(short, 1), short);
  const at = "x".repeat(4096);
  assert.equal(B.capped(at, 1), at);
  const over = B.capped(`${at}y`, 1);
  assert.notEqual(over, `${at}y`);
  assert.ok(new TextEncoder().encode(over).length <= 4096);
  const long = `Look: ${"é".repeat(5000)}`;
  const cut = B.capped(long, 1);
  assert.ok(new TextEncoder().encode(cut).length <= 4096);
  assert.ok(cut.endsWith("\n[cut to fit: read answers/board-1]"));
  // readAnswers refuses that text, and says to read the database document.
  assert.throws(
    () => readAnswers(`creative-video: board 1 answers (x)\n${cut}`),
    /read answers\/board-1 from the database/,
  );
});

test("a send is sent, saved or neither by whether the save and the wake landed, and whole text counts for a failed save", () => {
  assert.equal(B.outcome(true, true, true), "sent");
  assert.equal(B.outcome(true, true, false), "sent");
  assert.equal(B.outcome(true, false, true), "saved");
  assert.equal(B.outcome(false, true, true), "sent");
  assert.equal(B.outcome(false, true, false), "neither");
  assert.equal(B.outcome(false, false, true), "neither");
});

test("the view shows the tab and plan, the directions, the scene cards and the submit bar", () => {
  const S = B.newState(clone(doc));
  const v = B.view(S);
  assert.match(v, /role="tab"[^>]*>[^<]*Why agentic engineering/);
  assert.match(v, /awaiting you/);
  for (const d of doc.directions) {
    assert.ok(v.includes(`src="${d.frame}"`), d.id);
    assert.ok(v.includes(d.name), d.id);
  }
  assert.match(v, /Recommended/);
  assert.match(v, /In use/);
  assert.equal((v.match(/data-act="direction"/g) ?? []).length, 2);
  for (const s of doc.scenes) {
    for (const f of Object.values(s.stills))
      assert.ok(v.includes(`src="${f}"`), f);
    assert.ok(v.includes(s.timecode));
    assert.ok(v.includes(s.narration));
    assert.ok(v.includes(s.notes));
  }
  assert.equal((v.match(/data-field="note"/g) ?? []).length, doc.scenes.length);
  assert.match(v, /Colours, theme, the whole look/);
  for (const h of ["Chapter", "Title", "Length", "Focus", "Sources", "Status"])
    assert.match(v, new RegExp(`<th[^>]*>${h}</th>`));
  assert.match(v, /Approve the look/);
  assert.match(v, /Send comments/);
  assert.doesNotMatch(v, /id="approve"[^>]*disabled/);
  assert.match(v, /id="send"[^>]*disabled/);
  B.ACT.note(S, { id: "hook", value: "slower" });
  const after = B.view(S);
  assert.match(after, /id="approve"[^>]*disabled/);
  assert.doesNotMatch(after, /id="send"[^>]*disabled/);
  // A changed scene wears its badge.
  const edited = clone(doc);
  edited.scenes[1].changed = true;
  assert.equal(
    (B.view(B.newState(edited)).match(/class="tag accent"[^>]*>changed/g) ?? [])
      .length,
    1,
  );
});

test("a video in chapters has a tab per chapter with its status, cards under their own chapter's tab, and every chapter in the plan", () => {
  const chaptered = clone(doc);
  const [first, ...more] = chaptered.scenes;
  first.chapter = 1;
  more.forEach((s) => (s.chapter = 2));
  chaptered.chapters = [
    { n: 1, title: "The loop", status: "awaiting" },
    { n: 2, title: "The wrap", status: "authoring" },
    { n: 3, title: "The last", status: "authoring" },
  ];
  chaptered.plan = chaptered.chapters.map((c) => ({
    chapter: c.n,
    title: c.title,
    length: "1:00",
    focus: `focus ${c.n}`,
    sources: [],
    status: c.status,
  }));
  const S = B.newState(chaptered);
  let v = B.view(S);
  assert.equal((v.match(/role="tab"/g) ?? []).length, 3);
  assert.equal((v.match(/data-card=/g) ?? []).length, 1);
  assert.ok(v.includes(`data-card="${first.id}"`));
  assert.equal((v.match(/<tr><td>/g) ?? []).length, 3);
  assert.deepEqual(
    [1, 2, 3].map((n) => B.statusOf(S, n)),
    ["awaiting you", "being authored", "being authored"],
  );
  B.ACT.tab(S, { n: 2 });
  v = B.view(S);
  assert.equal((v.match(/data-card=/g) ?? []).length, more.length);
  assert.ok(!v.includes(`data-card="${first.id}"`));
  assert.doesNotMatch(v, /data-act="direction"/);
  assert.match(v, /being authored: its scenes join the board/);
  B.ACT.tab(S, { n: 3 });
  assert.equal((B.view(S).match(/data-card=/g) ?? []).length, 0);
  // The look's approval covers the video, but not a chapter with nothing to approve yet.
  B.setAnswers(S, [{ version: 1, approve: true }]);
  assert.deepEqual(
    [1, 2, 3].map((n) => B.statusOf(S, n)),
    ["approved", "being authored", "being authored"],
  );
});

test("a board posted while a comment was being written restores that unsent draft; its own draft, even empty, comes first", () => {
  const draft = (look) => JSON.stringify({ direction: null, look, notes: {} });
  const store = { "board-draft-2": draft("darker") };
  const get = (k) => store[k] ?? null;
  assert.equal(B.savedDraft(get, 3).look, "darker");
  store["board-draft-3"] = draft("");
  assert.equal(B.savedDraft(get, 3).look, "");
  store["board-draft-3"] = "{not json";
  assert.equal(B.savedDraft(get, 3).look, "darker");
  assert.equal(
    B.savedDraft(() => null, 3),
    null,
  );
});

test("the view escapes what the board holds", () => {
  const edited = clone(doc);
  edited.scenes[0].notes = '<img src=x onerror="boom()">';
  edited.title = "<b>t</b>";
  const v = B.view(B.newState(edited));
  assert.ok(!v.includes("<img src=x"));
  assert.ok(!v.includes("<b>t</b>"));
  assert.ok(v.includes("&lt;img src=x onerror=&quot;boom()&quot;&gt;"));
});

// Every path of the board document, with `[]` for an array element.
const paths = (v, p, acc = new Set()) => {
  if (p !== "board" && !p.endsWith("[]")) acc.add(p);
  if (Array.isArray(v)) v.forEach((x) => paths(x, `${p}[]`, acc));
  else if (v && typeof v === "object")
    for (const [k, x] of Object.entries(v)) paths(x, `${p}.${k}`, acc);
  return acc;
};
const documented = new Set(
  [
    ...read(path.join(boardDir, "board-data.md")).matchAll(
      /^\| `(board\.[^`]+)` \|/gm,
    ),
  ].map((m) => m[1]),
);

test("board-data.md documents exactly the fields a built board holds", () => {
  assert.ok(documented.size > 25, "no field table in board-data.md");
  assert.deepEqual([...paths(doc, "board")].sort(), [...documented].sort());
});

test("the page reads no field board-data.md does not define", () => {
  const seen = new Set();
  const watch = (v, p) => {
    if (!v || typeof v !== "object") return v;
    return new Proxy(v, {
      get(t, k, r) {
        if (typeof k === "symbol") return Reflect.get(t, k, r);
        if (Array.isArray(t))
          return /^\d+$/.test(k) ? watch(t[k], `${p}[]`) : Reflect.get(t, k, r);
        seen.add(`${p}.${k}`);
        return watch(t[k], `${p}.${k}`);
      },
    });
  };
  const S = B.newState(watch(clone(doc), "board"));
  B.view(S);
  B.ACT.note(S, { id: "hook", value: "slower" });
  B.ACT.look(S, { value: "warmer" });
  B.ACT.direction(S, { id: "kitchen" });
  B.answersDoc(S);
  B.answersText(B.answersDoc(S));
  B.canApprove(S);
  B.statusOf(S, 1);
  B.view(S);
  assert.ok(seen.size > 15, [...seen].join());
  assert.deepEqual(
    [...seen].filter((p) => !documented.has(p)),
    [],
  );
});
