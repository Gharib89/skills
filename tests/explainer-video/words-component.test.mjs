// The `words` component: key lines staged word by word. A line whose words
// each rise on their own spoken words is read along with the voice (marked for
// the reading gate), one cued any other way rises on its cue like any box.
// It is rich: it moves the frame itself, so it takes no `camera` key.
import { test } from "node:test";
import assert from "node:assert/strict";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  VISUALS,
  checkVisual,
  readAlong,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "Ship reads the issue.",
  "It opens a pull request.",
  "Then the gate checks it.",
];
const words = (...lines) => ({ component: "words", props: { lines } });
const line = (at, text, on) => ({ at, text, ...(on && { on }) });
const timing = {
  duration: 8,
  slot: 8,
  sentences: [0, 2, 4.5],
  words: Array.from({ length: 14 }, (_, i) => i * 0.5),
};
const drawn = (visual) =>
  sceneFile({ id: "a", narration: said, visual }, timing, claude, {
    backend: {},
    seam: {},
  });
// [selector, from, to, position] of each tween on a word.
const rises = (html) =>
  [...html.matchAll(/const tweens = (\[.*\]);/g)].flatMap((m) =>
    JSON.parse(m[1]).filter(([sel]) => /\.k\d+$/.test(sel)),
  );

test("words takes lines of at, text and an optional on, and refuses the rest", () => {
  assert.doesNotThrow(() =>
    checkVisual(words(line(1, "reads the issue", "reads the issue")), said),
  );
  const bad = (visual, why) =>
    assert.throws(() => checkVisual(visual, said), why);
  bad({ component: "words", props: {} }, /words needs lines/);
  bad(words(line(1, 3)), /words needs a text per line/);
  bad(words(line(4, "x")), /at 4 is not a sentence \(1 to 3\)/);
  bad(words(line(1, "x", "gate")), /on "gate" is not said in sentence 1/);
  bad(words({ ...line(1, "x"), note: "y" }), /a words item has no prop note/);
  bad(
    { component: "words", props: { lines: [line(1, "x")], emphasis: {} } },
    /words has no prop emphasis/,
  );
});

test("words is rich: it draws its own camera, so a camera key on it is refused", () => {
  assert.equal(VISUALS.words.ownCamera, true);
  assert.throws(
    () =>
      checkVisual(
        { ...words(line(1, "reads the issue")), camera: { at: 1 } },
        said,
      ),
    /words draws its own camera, so it takes no camera key/,
  );
});

test("a profile that bans kinetic bars the words component", () => {
  assert.match(
    banReason(["kinetic"], "words", "plain"),
    /component words uses kinetic, which style profile plain bans/,
  );
});

test("a line is read along when its words are the spoken words its cue lands on", () => {
  // The cue lands on the phrase's first word: word 5 of the scene.
  assert.equal(readAlong(said, line(2, "opens a pull request", "opens")), 5);
  assert.equal(
    readAlong(said, line(2, "opens a pull request", "opens a pull request")),
    5,
  );
  // A sentence's first words need no `on`.
  assert.equal(readAlong(said, line(2, "It opens")), 4);
  // Cued at the sentence, off the words: not read along.
  assert.equal(readAlong(said, line(2, "opens a pull request")), -1);
  assert.equal(readAlong(said, line(2, "opens a pull request", "pull")), -1);
  // Words the sentence never says.
  assert.equal(readAlong(said, line(2, "ten times faster")), -1);
});

test("a read-along line rises word by word on its spoken words and is marked for the gate", async () => {
  const html = await drawn(words(line(2, "opens a pull request", "opens")));
  assert.match(html, /<div class="kl" data-line="l0" data-along>/);
  const tw = rises(html);
  assert.deepEqual(
    tw.map(([sel, , , at]) => [sel, at]),
    [
      [".k0", 2.5],
      [".k1", 3],
      [".k2", 3.5],
      [".k3", 4],
    ],
  );
  assert.ok(
    tw.every(([, , to]) => to.delay === undefined && to.yPercent === 0),
  );
});

test("right to left, an English term glued into one span rises on its last spoken word", async () => {
  const ar = ["بعد كده بيعمل pull request."];
  const html = await sceneFile(
    {
      id: "a",
      narration: ar,
      visual: words(line(1, "بيعمل pull request", "بيعمل")),
    },
    { ...timing, sentences: [0] },
    claude,
    { backend: {}, seam: {}, dir: "rtl" },
  );
  assert.deepEqual(
    rises(html).map(([sel, , , at]) => [sel, at]),
    [
      [".k0", 1],
      [".k1", 2],
    ],
  );
});

test("a line cued off its spoken words rises on its cue, one stagger apart, and is not marked", async () => {
  const html = await drawn(words(line(2, "opens a pull request")));
  assert.match(html, /<div class="kl" data-line="l0">/);
  assert.doesNotMatch(html, /data-along/);
  const tw = rises(html);
  assert.deepEqual(
    tw.map(([, , to, at]) => [to.delay, at]),
    [
      [0, 2],
      [0.05, 2],
      [0.1, 2],
      [0.15, 2],
    ],
  );
});

test("each line is a box of its own, its words numbered through the scene", async () => {
  const html = await drawn(
    words(line(1, "reads the issue", "reads"), line(3, "the gate", "the")),
  );
  assert.match(html, /data-line="l0" data-along/);
  assert.match(html, /data-line="l1" data-along/);
  assert.deepEqual(
    rises(html).map(([sel]) => sel),
    [".k0", ".k1", ".k2", ".k3", ".k4"],
  );
  // "the gate" is the 7th and 8th spoken words of the scene after sentence 3's
  // first: word 10 and 11, 5 s and 5.5 s.
  assert.deepEqual(
    rises(html)
      .slice(3)
      .map(([, , , at]) => at),
    [5, 5.5],
  );
});
