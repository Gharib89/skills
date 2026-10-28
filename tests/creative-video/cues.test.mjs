// The caption cues (render/cues.mjs): a cue breaks at a sentence end or before
// a token that would take it past CUE_CHARS, and shows until the next cue.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CUE_CHARS,
  captionCues,
} from "../../skills/creative-video/scripts/render/cues.mjs";

// A scene from its sentences, each a list of one-word tokens, every word 0.5 s
// with no gap, the scene starting at `start` and lasting `duration`.
function scene(sentences, start = 0, duration) {
  const words = sentences.flat().map((_, i) => ({
    start: start + i * 0.5,
    end: start + (i + 1) * 0.5,
  }));
  return {
    script: {
      captions: sentences.map((s) => s.map((text) => ({ text, words: 1 }))),
    },
    timeline: { start, duration: duration ?? words.length * 0.5, words },
  };
}

test("a cue breaks at a sentence end and shows until the next cue starts", () => {
  const s = scene(
    [
      ["One", "two."],
      ["Three", "four."],
    ],
    0,
    3,
  );
  const cues = captionCues([s.script], [s.timeline]);
  assert.deepEqual(
    cues.map((c) => [c.text, c.start, c.end]),
    [
      ["One two.", 0, 1],
      ["Three four.", 1, 2.3],
    ],
  );
  assert.deepEqual(
    cues[1].tokens.map((t) => [t.text, t.start, t.end]),
    [
      ["Three", 1, 1.5],
      ["four.", 1.5, 2],
    ],
  );
});

test("the last cue holds 0.3 s past its last word, never past its scene's end", () => {
  const s = scene([["One", "two."]], 0, 1.1);
  assert.equal(captionCues([s.script], [s.timeline])[0].end, 1.1);
});

test("a token that would take a cue past CUE_CHARS starts a new cue", () => {
  const word = "x".repeat(20);
  const s = scene([Array(8).fill(word)]);
  const cues = captionCues([s.script], [s.timeline]);
  assert.ok(cues.length > 1);
  for (const c of cues) assert.ok(c.text.length <= CUE_CHARS, c.text);
  assert.equal(
    cues.map((c) => c.text).join(" "),
    Array(8).fill(word).join(" "),
  );
});

test("a cue of exactly CUE_CHARS stays one cue, and one more character splits it", () => {
  const words = (last) =>
    ["a", "b", "c", "d"].map((c, i) => c.repeat(i === 3 ? last : 20));
  const at = scene([words(21)]);
  assert.equal(
    captionCues([at.script], [at.timeline])[0].text.length,
    CUE_CHARS,
  );
  assert.equal(captionCues([at.script], [at.timeline]).length, 1);
  const over = scene([words(22)]);
  assert.equal(captionCues([over.script], [over.timeline]).length, 2);
});

test("a token spanning several words takes its first word's start and its last word's end", () => {
  const timeline = {
    start: 2,
    duration: 2,
    words: [
      { start: 2, end: 2.4 },
      { start: 2.4, end: 2.9 },
      { start: 3, end: 3.5 },
    ],
  };
  const script = {
    captions: [
      [
        { text: "pull request", words: 2 },
        { text: "merged.", words: 1 },
      ],
    ],
  };
  const [cue] = captionCues([script], [timeline]);
  assert.deepEqual(
    cue.tokens.map((t) => [t.text, t.start, t.end]),
    [
      ["pull request", 2, 2.9],
      ["merged.", 3, 3.5],
    ],
  );
  assert.equal(cue.end, 3.8);
});

test("with two roles, a cue whose role is not the last cue's opens with the role's name", () => {
  const a = scene([["One."], ["Two."], ["Three."]], 0, 1.5);
  const b = scene([["Four."]], 1.5, 0.5);
  a.script.roles = ["narrator", "learner", "learner"];
  b.script.roles = ["narrator"];
  const cues = captionCues([a.script, b.script], [a.timeline, b.timeline]);
  assert.deepEqual(
    cues.map((c) => [c.who, c.text]),
    [
      ["Narrator", "Narrator: One."],
      ["Learner", "Learner: Two."],
      [undefined, "Three."],
      ["Narrator", "Narrator: Four."],
    ],
  );
  assert.deepEqual(
    cues[1].tokens.map((t) => t.text),
    ["Two."],
  );
});

test("one role names no one, and a name counts toward CUE_CHARS", () => {
  const one = scene([["One."], ["Two."]]);
  one.script.roles = ["learner", "learner"];
  assert.deepEqual(
    captionCues([one.script], [one.timeline]).map((c) => [c.who, c.text]),
    [
      [undefined, "One."],
      [undefined, "Two."],
    ],
  );
  // "Learner: " is 9 characters: 75 of words fit beside it, 76 do not
  const words = (last) => ["a".repeat(20), "b".repeat(20), "c".repeat(last)];
  const two = (last) => {
    const s = scene([["Hi."], words(last)]);
    s.script.roles = ["narrator", "learner"];
    return captionCues([s.script], [s.timeline]);
  };
  assert.equal(two(33).length, 2);
  assert.equal(two(33)[1].text.length, CUE_CHARS);
  assert.equal(two(34).length, 3);
  assert.equal(two(34)[2].who, undefined);
});

test("each scene's cues end within that scene", () => {
  const a = scene([["One."]], 0, 0.6);
  const b = scene([["Two."]], 0.6, 0.6);
  const cues = captionCues([a.script, b.script], [a.timeline, b.timeline]);
  assert.deepEqual(
    cues.map((c) => [c.text, c.start, c.end]),
    [
      ["One.", 0, 0.6],
      ["Two.", 0.6, 1.2],
    ],
  );
});
