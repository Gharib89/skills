// The storyboard of a video in sections: the board groups its cards under a
// heading per section, and each heading plays the animatic over its own stretch.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import vm from "node:vm";
import { SCRIPT } from "./scene-file.mjs";
import { sectionFile } from "./sections-lib.mjs";
import { board, doc, fixture, ok, prep } from "./board-lib.mjs";
import { clone, ctx, P, read, sample, session, skill } from "./page-lib.mjs";

const built = (text) => {
  const fx = fixture(text);
  prep(fx);
  ok(board(fx, "build", "--local"), "build");
  return doc(fx, 1);
};
const inPage = (code) => vm.runInContext(code, ctx);

test("build marks every card with its section when the script has openers, and none when it has none", () => {
  assert.deepEqual(
    built(sectionFile()).scenes.map((c) => c.section),
    [1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3],
  );
  assert.ok(
    built(SCRIPT).scenes.every((c) => !("section" in c)),
    "an unsectioned board carries no section key",
  );
});

test("the page groups the cards under a heading per section, in order, and a heading per section plays only its own stretch", () => {
  const b = built(sectionFile());
  const v = P.view(session([b]));
  // Each heading, then the ids of the cards that follow it up to the next heading.
  const groups = v
    .split('<h2 class="sec-title"')
    .slice(1)
    .map((g) => [
      g.match(/^[^>]*>([^<]*)</)[1],
      [...g.matchAll(/<article[^>]* data-card="([\w-]+)"/g)].map((m) => m[1]),
    ]);
  assert.deepEqual(groups, [
    ["Section 1: Scene one", ["hook", "why", "one", "one-a", "one-b"]],
    ["Section 2: Scene two", ["two", "two-a", "two-b"]],
    ["Section 3: Scene three", ["three", "three-a", "three-b", "recap", "bye"]],
  ]);
  assert.equal(
    [...v.matchAll(/data-act="play-section" data-section="(\d)"/g)]
      .map((m) => m[1])
      .join(""),
    "123",
  );
  // The window: from the section's first scene to the next section's first, the last to the video's end.
  const start = (id) => b.scenes.find((c) => c.id === id).start;
  const span = (n) => clone(inPage(`sectionsOf(${JSON.stringify(b)})[${n}]`));
  assert.deepEqual(
    [0, 1, 2].map((n) => [span(n).from, span(n).to]),
    [
      [start("hook"), start("two")],
      [start("two"), start("three")],
      [start("three"), null],
    ],
  );
  assert.equal(start("hook"), 0);
  assert.ok(start("two") > 0 && start("three") > start("two"));
});

test("a board with no sections renders exactly its cards, no heading and no section control", () => {
  const b = sample("board-review");
  const S = session([b]);
  const v = P.view(S);
  assert.doesNotMatch(v, /sec-title|play-section/);
  const [first] = S.boards;
  const card = inPage("card");
  const cards = first.scenes.map((c) => card(S, first, c)).join("");
  assert.ok(v.includes(`<section class="cards">${cards}</section>`));
});

test("the animatic's driver stops by itself at the section's end and a section play hands it that window", () => {
  const boot = read(path.join(skill, "storyboard", "page-boot.js"));
  const tick = boot.match(/function tick\(\) \{[\s\S]*?\n  \}\n/)[0];
  assert.match(
    tick,
    /until !== null && narration\(\)\.currentTime >= until\) return stop\(\)/,
  );
  assert.match(boot, /function stop\(\) \{[^]*?until = null/);
  assert.match(boot, /playAnimatic\(g\.from, g\.to\)/);
  assert.match(
    boot,
    /function playAnimatic\(t, to = null\) \{\n    until = to;/,
  );
  // The whole-video button still plays it all.
  assert.match(boot, /act === "play"\) return playAnimatic\(0\)/);
});
