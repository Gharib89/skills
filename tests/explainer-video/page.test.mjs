// The storyboard page's one seam: the board and answers documents between a run
// and storyboard/page.html. The sample boards must match the shape
// board-data.md documents, and the page, run headless over them and a click
// path, must read and write only that shape's fields. Reads are recorded
// through proxies, so the assertion is what crosses the seam, not how the page
// builds its DOM. The answers text it copies must read back through
// `board.mjs apply` to the same answers.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { ARABIC, SCRIPT } from "./scene-file.mjs";
import {
  P,
  clone,
  doc,
  here,
  html,
  read,
  sample,
  scripts,
  seen,
  session,
  shape,
  shapeProblems,
  skill,
  submitDisabled,
} from "./page-lib.mjs";

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

test("the sample boards hold to the documented shape, and the checker refuses a malformed one", () => {
  assert.ok(shape.size > 30, "no field table in board-data.md");
  for (const n of [
    "board-review",
    "board-finding",
    "board-gate-stop",
    "board-delivered",
  ])
    assert.deepEqual(shapeProblems(sample(n), "board"), [], n);
  const noStill = sample("board-review");
  delete noStill.scenes[0].still;
  assert.ok(
    shapeProblems(noStill, "board").some((p) => /scenes\[\]\.still/.test(p)),
  );
  const extra = sample("board-review");
  extra.scenes[0].mood = "calm";
  assert.ok(
    shapeProblems(extra, "board").some((p) => /undocumented field/.test(p)),
  );
});

test("the page is one inline code script with the title placeholder once", () => {
  assert.equal(scripts.length, 1);
  assert.doesNotThrow(() => new vm.Script(scripts[0]));
  assert.match(html, /<title>\{\{TITLE\}\}<\/title>/);
  assert.equal(html.split("{{TITLE}}").length, 2);
  assert.match(
    html,
    /<script type="application\/json" id="board">null<\/script>/,
  );
  // A local page returns at its capability check, so its listeners come first.
  for (const ev of ["click", "change", "input"])
    assert.ok(
      scripts[0].indexOf(`document.addEventListener('${ev}'`) <
        scripts[0].indexOf("return localMode()"),
      ev,
    );
});

test("a review board takes choices, edits and brief changes, and the answers match the shape", () => {
  const S = session([sample("board-review")]);
  P.ACT.choose(S, { id: "hook", choice: "approve" });
  P.ACT.choose(S, { id: "steps", choice: "revise" });
  P.ACT.choose(S, { id: "gate", choice: "approve" });
  P.ACT.field(S, { id: "steps", field: "note", value: "too fast" });
  P.ACT.field(S, {
    id: "steps",
    field: "narration",
    value:
      "1. It reads the ticket. [ex-1]\n2. It writes a failing test. [ex-2]",
  });
  P.ACT.brief(S, { knob: "focus", value: "the gate only" });
  P.ACT.brief(S, { knob: "must", value: "name the gate; add a recap; " });
  P.ACT.brief(S, { knob: "avoid", value: "" });
  const a = clone(P.answersDoc(S, "2026-10-16T10:00:00Z"));
  assert.deepEqual(shapeProblems(a, "answers"), []);
  assert.deepEqual(
    a.scenes.map((s) => s.choice),
    ["approve", "revise", "approve"],
  );
  assert.equal(a.scenes[1].note, "too fast");
  assert.match(a.scenes[1].narration, /^1\. It reads the ticket/);
  assert.equal(a.scenes[0].narration, "");
  assert.deepEqual(a.brief, [
    "focus=the gate only",
    "must=name the gate",
    "must=add a recap",
    "avoid=",
  ]);
  const head = P.answersText(S).split("\n")[0].replace(/\d+/g, "<n>");
  assert.ok(doc.includes("`" + head + "`"), head);
});

test("a gate stop shows its red gate lines, opens its reopened card on Revise and its approved cards on approve", () => {
  const board = sample("board-gate-stop");
  const S = session([board]);
  const v = P.view(S);
  for (const g of board.banner.gates)
    assert.ok(
      v.includes(g.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`)) ||
        v.includes(
          g
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;"),
        ),
      g,
    );
  assert.ok(v.includes(board.banner.text));
  // The count names cards approved on an earlier board, not this board's picks.
  assert.match(v, /of 1 to answer done · 2 already approved/);
  // The reopened card arrives recommended Revise, so nothing is left unanswered.
  assert.ok(!submitDisabled(v));
  assert.deepEqual(clone(P.answersDoc(S).scenes.map((s) => s.choice)), [
    "approve",
    "revise",
    "approve",
  ]);
});

test("a delivered board shows a video per clip and takes no answers", () => {
  const board = sample("board-delivered");
  const S = session([board]);
  const v = P.view(S);
  assert.equal(v.split("<video").length - 1, board.scenes.length);
  assert.ok(!/id="submit"/.test(v) && !/type="radio"/.test(v));
  P.ACT.choose(S, { id: "steps", choice: "revise" });
  assert.equal(P.answersDoc(S).scenes[1].choice, "approve");
});

test("only the card in view mounts its build, in a frame that runs scripts and nothing else", () => {
  const S = session([sample("board-review")]);
  const frames = (v) => v.split("<iframe").length - 1;
  const posters = (v) => v.split('class="stage"').length - 1;
  let v = P.view(S);
  assert.equal(frames(v), 0, "no card in view, no build");
  assert.equal(posters(v), 4, "three cards and the animatic show a poster");
  S.inView = { steps: true };
  v = P.view(S);
  assert.equal(frames(v), 1);
  assert.match(
    v,
    /<div class="stage" data-stage="steps"><img[^>]*><iframe class="live" sandbox="allow-scripts" [^>]*data-live="steps"><\/iframe>/,
  );
  // no origin and no markup in the attribute: the page hands the build in after mount
  assert.doesNotMatch(v, /allow-same-origin|srcdoc/);
  // the animatic plays the one build, so no card keeps its own
  S.animatic = true;
  v = P.view(S);
  assert.equal(frames(v), 1);
  assert.match(v, /data-live="animatic"/);
  assert.doesNotMatch(v, /data-live="steps"/);
});

test("the animatic's tick marks a scene change in place, never through render, which reloads a frame where moveBefore is missing", () => {
  const boot = read(path.join(skill, "storyboard", "page-boot.js"));
  const tick = boot.match(/function tick\(\) \{[\s\S]*?\n  \}\n/)[0];
  assert.match(tick, /classList\.toggle\("on"/);
  assert.doesNotMatch(tick, /\brender\(/);
});

test("a card loops its slot, the animatic finds the scene at the narration's time, and its list highlights the playing card", () => {
  const board = sample("board-review");
  const S = session([board]);
  const b = S.boards[0];
  const [hook, steps] = b.scenes;
  assert.deepEqual(clone(P.loopOf(hook)), [hook.start, hook.start + hook.slot]);
  assert.ok(hook.slot > hook.seconds, "the slot holds the exit seam");
  assert.equal(P.sceneAt(b, 0).id, "hook");
  assert.equal(P.sceneAt(b, steps.start - 0.01).id, "hook");
  assert.equal(
    P.sceneAt(b, steps.start).id,
    "steps",
    "a seam belongs to the scene it enters",
  );
  assert.equal(P.sceneAt(b, 999).id, "gate");
  assert.equal(P.buildOf(b), board.build);
  assert.match(
    P.view(S),
    /<audio id="player-audio"[^>]* src="\.cache\/board-audio\//,
  );
  const on = (v) =>
    [...v.matchAll(/class="scene on" data-act="jump" data-id="(\w+)"/g)].map(
      (m) => m[1],
    );
  assert.deepEqual(on(P.view(S)), []);
  S.animatic = true;
  S.playing = "steps";
  const v = P.view(S);
  assert.deepEqual(on(v), ["steps"]);
  assert.match(v, /class="scene on" [^>]*aria-current="true"/);
  assert.match(v, /data-act="jump" data-id="hook"/);
  assert.match(v, /data-act="card-play" data-id="steps"/);
});

test("a board whose answers are submitted takes no more edits", () => {
  const S = session(
    [sample("board-review")],
    [
      {
        version: 1,
        submittedAt: "2026-10-16T10:00:00Z",
        scenes: [],
        brief: [],
      },
    ],
  );
  P.ACT.choose(S, { id: "hook", choice: "revise" });
  assert.equal(P.answersDoc(S).scenes[0].choice, "approve");
  assert.ok(submitDisabled(P.view(S)));
});

test("a submit whose save failed reads as sent only when the comment carried the whole answers", () => {
  assert.equal(P.outcome(true, true, false), "sent");
  assert.equal(P.outcome(true, false, true), "saved");
  assert.equal(P.outcome(false, true, true), "sent");
  assert.equal(P.outcome(false, true, false), "neither");
  assert.equal(P.outcome(false, false, true), "neither");
});

test("a media URL is kept when https, a blob or relative and dropped otherwise", () => {
  for (const u of ["/_blob/x", "https://a/b", ".cache/stills/a.png"])
    assert.equal(P.mediaUrl(u), u);
  for (const u of ["javascript:alert(1)", "//evil", "/etc/passwd", "data:x"])
    assert.equal(P.mediaUrl(u), "", u);
  const board = sample("board-review");
  board.scenes[0].still = "javascript:alert(1)";
  assert.ok(!/javascript:/.test(P.view(session([board]))));
});

test("the answers text of an edited board reads back through apply to the same answers", () => {
  const dir = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "explainer-page-")),
    "demo",
  );
  temps.push(path.dirname(dir));
  fs.mkdirSync(path.join(dir, "board"), { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), SCRIPT);
  fs.writeFileSync(
    path.join(dir, "board", "1.json"),
    JSON.stringify(sample("board-review")),
  );
  const S = session([sample("board-review")]);
  P.ACT.choose(S, { id: "hook", choice: "approve" });
  P.ACT.choose(S, { id: "steps", choice: "revise" });
  P.ACT.choose(S, { id: "gate", choice: "approve" });
  P.ACT.field(S, { id: "steps", field: "note", value: "slower please" });
  P.ACT.field(S, {
    id: "steps",
    field: "narration",
    value:
      "1. It reads the ticket. [ex-1]\n2. It writes a failing test. [ex-2]",
  });
  P.ACT.brief(S, { knob: "must", value: "name the gate; add a recap" });
  const file = path.join(dir, "answers.txt");
  fs.writeFileSync(file, P.answersText(S));
  const r = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "storyboard", "board.mjs"),
      dir,
      "apply",
      file,
    ],
    { encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const got = JSON.parse(read(path.join(dir, "board", "answers-1.json")));
  const want = clone(P.answersDoc(S));
  assert.deepEqual(got.scenes, want.scenes);
  assert.deepEqual(got.brief, want.brief);
});

test("a board with kept terms shows each one editable, and an edited term reads back through apply", () => {
  const board = { ...sample("board-review"), kept: ["Ship", "pull request"] };
  assert.deepEqual(shapeProblems(board, "board"), []);
  const S = session([board]);
  const v = P.view(S);
  assert.match(v, /data-kept="Ship" value="Ship"/);
  assert.match(v, /data-kept="pull request" value="pull request"/);
  // An Arabic run's title, card titles, narration and notes read in their
  // own direction, not the page's.
  assert.match(v, /<h1 dir="auto">/);
  assert.match(v, /<h3 dir="auto">/);
  assert.match(v, /<textarea dir="auto" rows="4" data-field="narration"/);
  assert.match(v, /<textarea dir="auto" rows="2" data-field="note"/);
  for (const id of ["hook", "steps", "gate"])
    P.ACT.choose(S, { id, choice: "approve" });
  P.ACT.kept(S, { term: "pull request", value: " PR " });
  P.ACT.kept(S, { term: "Ship", value: "" });
  const a = clone(P.answersDoc(S));
  assert.deepEqual(shapeProblems(a, "answers"), []);
  assert.deepEqual(a.kept, [{ term: "pull request", to: "PR" }]);
  assert.match(P.answersText(S), /^Kept: pull request -> PR$/m);

  const dir = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "explainer-page-")),
    "demo",
  );
  temps.push(path.dirname(dir));
  fs.mkdirSync(path.join(dir, "board"), { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), ARABIC);
  fs.writeFileSync(path.join(dir, "board", "1.json"), JSON.stringify(board));
  const file = path.join(dir, "answers.txt");
  fs.writeFileSync(file, P.answersText(S));
  const r = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "storyboard", "board.mjs"),
      dir,
      "apply",
      file,
    ],
    { encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const got = JSON.parse(read(path.join(dir, "board", "answers-1.json")));
  assert.deepEqual(got.kept, a.kept);
  assert.doesNotMatch(read(path.join(dir, "script.md")), /pull request/);
});

test("every field the page reads is documented, and it reads the ones it renders", () => {
  for (const p of seen)
    assert.ok(shape.has(p), `page reads an undocumented field ${p}`);
  for (const p of [
    "board.banner.gates",
    "board.scenes[].clip",
    "board.sources[].excerpts",
    "board.brief[].value",
    "board.brief[].type",
    "board.brief[].options",
    "board.voices",
    "board.voices[].language",
    "board.voices[].options",
    "board.scenes[].menus",
    "board.scenes[].menus.camera.options",
    "board.scenes[].menus.camera.disabled",
    "board.scenes[].role",
    "board.scenes[].seconds",
    "board.scenes[].style",
    "board.scenes[].intent",
    "board.scenes[].audio",
    "board.scenes[].start",
    "board.scenes[].slot",
    "board.narration",
    "board.build",
    "answers.version",
  ])
    assert.ok(seen.has(p), `page never reads ${p}`);
});
