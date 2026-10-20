// The reading time video gate, judged on the layout probe's samples: each text
// box's longest single readable stretch against its words, and kinetic type
// read along with the voice judged whole.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ALONG_SECONDS,
  readingFindings,
  readingFloor,
} from "../../skills/explainer-video/scripts/gates/reading.mjs";

// A scene of 6 s sampled every 0.5 s. `shown(t)` says which boxes read at `t`
// as [text, words, line?] triples; each is a probe element of scene `s`.
const times = Array.from({ length: 12 }, (_, i) => i * 0.5);
const scene = { id: "s", start: 10, duration: 6 };
const el = (text, words, line = null, along = false) => ({
  text,
  words,
  scene: "s",
  opacity: 1,
  blur: 0,
  line,
  along,
});
const judge = (shown, moving = () => false) =>
  readingFindings(
    { sc: scene, end: 16, times: times.map((t) => t + 10) },
    times.map((t) => ({ t: t + 10, elements: shown(t) })),
    moving,
  );

test("the floors keep today's times: 0.8 s up to three words, else 0.3 s a word and 1.2 s at least", () => {
  assert.equal(readingFloor(1), 0.8);
  assert.equal(readingFloor(3), 0.8);
  assert.equal(readingFloor(4), 1.2);
  assert.equal(readingFloor(10), 3);
  assert.equal(ALONG_SECONDS, 0.8);
});

test("a box readable from 1 s to the scene's end passes, one shown for 0.5 s fails with its longest stretch", () => {
  const long = el("one two three four five six", 6);
  assert.deepEqual(
    judge((t) => (t >= 1 ? [long] : [])),
    [],
  );
  const f = judge((t) => (t >= 5.5 ? [long] : []));
  assert.equal(f.length, 1);
  assert.match(
    f[0],
    /^10\.00 s s: "one two three four five six": 0\.5 s readable vs 1\.8 s to read$/,
  );
});

test("a box readable in two short stretches fails even when their sum would pass", () => {
  const box = el("one two three four five six", 6);
  // 1.0 to 2.0 and 3.0 to 4.0: 2 s in all against 1.8 s, 1 s at most in one.
  const f = judge((t) => ((t >= 1 && t < 2) || (t >= 3 && t < 4) ? [box] : []));
  assert.equal(f.length, 1);
  assert.match(f[0], /1\.0 s readable vs 1\.8 s to read/);
});

test("a stretch exactly as long as the floor passes, half a sample less fails", () => {
  const box = el("a b c d e f g h i j", 10);
  // 3.0 s needed: shown 1.0 to 4.0 is exactly 3.0 s, to 3.5 only 2.5 s.
  assert.deepEqual(
    judge((t) => (t >= 1 && t < 4 ? [box] : [])),
    [],
  );
  const f = judge((t) => (t >= 1 && t < 3.5 ? [box] : []));
  assert.match(f[0], /2\.5 s readable vs 3\.0 s to read/);
});

test("a box carried by a seam or camera is readable only outside it", () => {
  const box = el("one two three four five six", 6);
  const moving = (id, t) => t >= 12 && t < 14.5;
  const f = judge(() => [box], moving);
  // The scene runs 10 to 16 s: 2 s before the move, 1.5 s after.
  assert.deepEqual(f, []);
  const g = judge(
    () => [box],
    (id, t) => t >= 11 && t < 15.5,
  );
  assert.equal(g.length, 1);
  assert.match(g[0], /1\.0 s readable vs 1\.8 s/);
});

test("a box never readable fails with 0.0 s", () => {
  const f = judge(() => [{ ...el("one", 1), opacity: 0.4 }]);
  assert.equal(f.length, 1);
  assert.match(f[0], /"one": 0\.0 s readable vs 0\.8 s to read$/);
});

test("a box blurred above one pixel is not readable", () => {
  const f = judge(() => [{ ...el("one", 1), blur: 4 }]);
  assert.match(f[0], /0\.0 s readable/);
  assert.deepEqual(
    judge(() => [{ ...el("one", 1), blur: 1 }]),
    [],
  );
});

test("elements of another scene and the page's own text are not judged", () => {
  const f = judge(() => [
    { ...el("x", 1), scene: "other", opacity: 0 },
    { ...el("caption", 1), scene: null, opacity: 0 },
  ]);
  assert.deepEqual(f, []);
});

test("a kinetic line read along is judged whole against 0.8 s, with no words-per-second check", () => {
  // Six words would need 1.8 s as a box; whole from 4.5 s it has 1.5 s.
  const line = (t) =>
    ["a", "b", "c", "d", "e", "f"].map((w) => ({
      ...el(w, 1, "l0", true),
      opacity: t >= 4.5 ? 1 : 0,
    }));
  assert.deepEqual(judge(line), []);
});

test("a line read along fails when it is whole for under 0.8 s", () => {
  const line = (t) =>
    ["a", "b", "c"].map((w) => ({
      ...el(w, 1, "l0", true),
      opacity: t >= 5.5 ? 1 : 0,
    }));
  const f = judge(line);
  assert.equal(f.length, 1);
  assert.match(
    f[0],
    /^10\.00 s s: "a b c": 0\.5 s readable whole vs 0\.8 s after its last word$/,
  );
});

test("a line's words must all read at once: one word still rising holds the line back", () => {
  const line = (t) => [
    el("a", 1, "l0", true),
    { ...el("b", 1, "l0", true), opacity: t >= 5.5 ? 1 : 0.2 },
  ];
  const f = judge(line);
  assert.match(f[0], /0\.5 s readable whole/);
});

test("a line cued off its own spoken words is judged like any box, by its words", () => {
  // Seven words need 2.1 s; 1.0 s whole is not enough, as it is not for any box.
  const seven = (t) =>
    Array.from({ length: 7 }, (_, i) => ({
      ...el(`w${i}`, 1, "l0", false),
      opacity: t >= 5 ? 1 : 0,
    }));
  const f = judge(seven);
  assert.equal(f.length, 1);
  assert.match(
    f[0],
    /"w0 w1 w2 w3 w4 w5 w6": 1\.0 s readable vs 2\.1 s to read$/,
  );
  // The same line read along passes on the same samples.
  assert.deepEqual(
    judge((t) => seven(t).map((e) => ({ ...e, along: true }))),
    [],
  );
});
