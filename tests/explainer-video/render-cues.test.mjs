// The render stage through its process door, part 4: a cue's `on` phrase lands
// a reveal on the phrase's voiced word, and an emphasis draws the grammar's
// callout on one item at its cue.
import { test } from "node:test";
import assert from "node:assert/strict";
import { DIAGRAMS, SCRIPT } from "./scene-file.mjs";
import {
  at,
  comp,
  fixture,
  near,
  read,
  render,
  tweens,
} from "./render-lib.mjs";

const scene = (fx, id) =>
  JSON.parse(read(fx.dir, "timeline.json")).scenes.find((s) => s.id === id);

test("a reveal with an `on` phrase starts at that phrase's first voiced word, not at its sentence", () => {
  const from = '{ "at": 2, "text": "Run every test" }';
  assert.ok(DIAGRAMS.includes(from), from);
  const fx = fixture(
    DIAGRAMS.replace(
      from,
      '{ "at": 2, "on": "tests", "text": "Run every test" }',
    ),
  );
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  // "The gate lints." is 3 words and "It runs the tests." puts `tests` 4th.
  const gates = scene(fx, "gates");
  const word = gates.words[3 + 3];
  const [, , , t] = tweens(fx, "gates").find(([s]) => s === ".i1");
  assert.ok(near(t, word.start - gates.start), `${t} vs ${word.start}`);
  assert.ok(t - at(fx, "gates", 2) > 0.05, "later than the sentence start");
  // The item before it, with no `on`, still lands at its sentence.
  const [, , , first] = tweens(fx, "gates").find(([s]) => s === ".i0");
  assert.ok(near(first, at(fx, "gates", 1)));
});

test("an emphasis draws the callout on the one item it names, revealed at its cue", () => {
  const from =
    '{ "at": 2, "label": "First", "value": "test", "note": "failing" }';
  assert.ok(SCRIPT.includes(from), from);
  const fx = fixture(
    SCRIPT.replace(
      '      { "at": 3, "label": "Then", "value": "code" }\n    ]',
      '      { "at": 3, "label": "Then", "value": "code" }\n    ],\n    "emphasis": { "target": "First", "at": 3, "on": "pass" }',
    ),
  );
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const html = comp(fx, "scenes/steps.html");
  const cards = html.match(/<div class="card r\d[^"]*">.*?<\/div><\/div>/g);
  assert.equal(cards.length, 3, html);
  assert.deepEqual(
    cards.map((c) => c.includes('class="em"')),
    [false, true, false],
  );
  assert.equal([...html.matchAll(/class="em"/g)].length, 1);
  const steps = scene(fx, "steps");
  const [, from0, to, t] = tweens(fx, "steps").find(([s]) => s === ".em");
  assert.equal(from0.opacity, 0);
  assert.equal(to.opacity, 1);
  // "Then the code makes it pass." puts `pass` 5th in the third sentence.
  assert.ok(near(t, steps.words[4 + 5 + 5].start - steps.start), String(t));
});

test("a code emphasis rings the range it names, beside the text", () => {
  const fx = fixture(DIAGRAMS);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const html = comp(fx, "scenes/code.html");
  assert.equal([...html.matchAll(/class="em side"/g)].length, 1);
  // Line 2 of 45 px rows: 28 px of frame padding, one row down, 4 px of slack.
  assert.match(html, /class="em side" style="top: 69px; height: 53px;/);
  const [, , , t] = tweens(fx, "code").find(([s]) => s === ".em");
  assert.ok(near(t, at(fx, "code", 2)));
});
