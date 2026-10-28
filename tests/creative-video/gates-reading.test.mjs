// The reading time gate: readable scene text stays readable at least 0.8 s (up
// to 3 words) or 0.3 s a word, 1.2 s at least, measured on the probe's 0.25 s
// grid and the sample frames.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readingFloor } from "../../skills/creative-video/scripts/gates/reading.mjs";
import { gateLine, only, runGates, timed } from "./gates-lib.mjs";

test("the floor is 0.8 s up to 3 words, then 0.3 s a word and 1.2 s at least", () => {
  assert.equal(readingFloor(1), 0.8);
  assert.equal(readingFloor(3), 0.8);
  assert.equal(readingFloor(4), 1.2);
  assert.ok(Math.abs(readingFloor(10) - 3) < 1e-9);
});

test("a line readable for 0.5 s fails, naming how long it read against the floor, and the same line held passes", () => {
  const r = runGates(timed({ hook: "<p>a blink line</p>" }));
  assert.equal(r.code, 1);
  only(r, "reading");
  assert.match(
    gateLine(r, "reading"),
    /^fail: 1 finding\(s\), first: \d+\.\d\d s hook: "a blink line" is readable 0\.5 s vs 0\.8 s to read vs /,
  );
  assert.equal(runGates(timed({ hook: "<p>a held line</p>" })).code, 0);
});

test("a long line is held to 0.3 s a word: 10 words fit a 3.1 s scene, 12 do not", () => {
  const words = (n) =>
    `<p>${Array.from({ length: n }, (_, i) => `w${i}`).join(" ")}</p>`;
  assert.equal(runGates(timed({ hook: words(10) })).code, 0);
  const r = runGates(timed({ hook: words(12) }));
  assert.equal(r.code, 1);
  only(r, "reading");
  assert.match(gateLine(r, "reading"), /readable 3\.1 s vs 3\.6 s to read/);
});
