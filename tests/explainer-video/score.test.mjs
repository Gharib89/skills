// The score through its module door: the duck curve read off a worked word
// timeline, and the synthesised score's determinism.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  duck,
  score,
} from "../../skills/explainer-video/scripts/score/score.mjs";

// One 10 s scene: two words close enough to share a speech span, a pause, a
// third word, then no narration to the scene's end.
const SCENE = {
  id: "s1",
  start: 0,
  duration: 10,
  words: [
    { text: "one", start: 0.5, end: 1.0 },
    { text: "two", start: 1.1, end: 1.5 },
    { text: "three", start: 3.5, end: 4.0 },
  ],
};
const at = (curve, t) => curve.db[Math.round(t * curve.rate)];
const near = (got, want, why) =>
  assert.ok(Math.abs(got - want) <= 0.5, `${why}: ${got} dB, want ${want}`);

test("the duck holds 0 dB with no narration, -6 dB in a pause and -15 dB under speech", () => {
  const c = duck([SCENE], 10);
  near(at(c, 0), 0, "before the first word");
  near(at(c, 1.0), -15, "under the first span");
  near(at(c, 2.4), -6, "in the pause between spans");
  near(at(c, 3.75), -15, "under the third word");
  near(at(c, 6), 0, "after the scene's last word");
});

test("speech opens 150 ms before its word, and each change is smoothed over 400 ms", () => {
  const c = duck([SCENE], 10);
  // A centred 400 ms average sits halfway across a step at the step itself.
  near(at(c, 0.35), -7.5, "at the lead before the first word");
  near(at(c, 0.15), 0, "400 ms window just short of the lead");
  near(at(c, 0.55), -15, "400 ms window just past the lead");
  near(at(c, 1.5), -10.5, "where speech gives way to the pause");
  near(at(c, 4.0), -7.5, "where the last word gives way to silence");
});

test("a gap under 400 ms between spans stays ducked under speech", () => {
  const c = duck([SCENE], 10);
  near(at(c, 1.05), -15, "between one and two");
});

test("each scene ducks on its own words, the hold before the next at 0 dB", () => {
  const second = {
    id: "s2",
    start: 10,
    duration: 5,
    words: [{ text: "four", start: 11, end: 12 }],
  };
  const c = duck([SCENE, second], 15);
  near(at(c, 9), 0, "after s1's last word");
  near(at(c, 11.5), -15, "under s2's word");
  near(at(c, 14), 0, "after s2's last word");
});

const SCENES = [
  { ...SCENE, duration: 4.5 },
  {
    id: "s2",
    start: 4.5,
    duration: 3.5,
    words: [{ text: "four", start: 5, end: 6 }],
  },
];
const ARGS = { scenes: SCENES, total: 8, seed: 5, level: -28, perMinute: 24 };
const bytes = (r) =>
  Buffer.concat([r.buf.L, r.buf.R].map((x) => Buffer.from(x.buffer)));

test("the same scene timings and seed make the same score, another seed another", () => {
  const a = score(ARGS);
  const b = score(ARGS);
  const c = score({ ...ARGS, seed: 6 });
  assert.equal(a.buf.L.length, 8 * 48000);
  assert.ok(bytes(a).equals(bytes(b)), "same seed, same samples");
  assert.deepEqual(a.cues, b.cues);
  assert.deepEqual(a.spec, b.spec);
  assert.ok(!bytes(a).equals(bytes(c)), "another seed, other samples");
});

test("music made elsewhere (ACE-Step) takes the synth's place: set to the level, then ducked under speech", () => {
  const n = 8 * 48000;
  const square = Float32Array.from({ length: n }, (_, i) =>
    i % 2 ? 0.3 : -0.3,
  );
  const r = score({
    ...ARGS,
    perMinute: 0,
    music: { L: square, R: Float32Array.from(square) },
  });
  const rms = (t) => {
    let e = 0;
    const a = Math.round(t * 48000);
    for (let i = a; i < a + 4800; i++) e += r.buf.L[i] ** 2;
    return 20 * Math.log10(Math.sqrt(e / 4800));
  };
  near(rms(7.5), -28, "no narration: the level");
  near(rms(5.4), -43, "under speech: 15 dB down");
  assert.deepEqual(r.spec, { seed: 5 });
});

test("the score arranges one section per scene at the scene's start", () => {
  const r = score(ARGS);
  assert.deepEqual(
    r.spec.sections.map((s) => [s.type, s.start]),
    [
      ["intro", 0],
      ["outro", 4.5],
    ],
  );
});

test("a cue past the sfx floor's count in its minute is dropped", () => {
  const short = [0, 1, 2, 3, 4, 5].map((i) => ({
    id: `s${i}`,
    start: i,
    duration: 1,
    words: [{ text: "w", start: i + 0.2, end: i + 0.8 }],
  }));
  const at = (perMinute) =>
    score({ scenes: short, total: 6, seed: 5, level: -28, perMinute }).cues;
  assert.equal(at(24).length, 6);
  assert.deepEqual(at(2), [
    { type: "whoosh", t: 1 },
    { type: "whoosh", t: 2 },
  ]);
  assert.deepEqual(at(1), [{ type: "whoosh", t: 1 }]);
  assert.deepEqual(at(0), []);
});

test("a whoosh marks each cut and a sting the last word's end", () => {
  const r = score(ARGS);
  assert.deepEqual(r.cues, [
    { type: "whoosh", t: 4.5 },
    { type: "sting", t: 6 },
  ]);
});
