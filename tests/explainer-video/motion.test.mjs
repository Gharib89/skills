// The motion measures the determinism gate and the critic's motion strip share
// (lib/motion.mjs): pure functions over per-frame content-band differences.
// The real backend's band reader against a video ffmpeg generates is
// motion-real.test.mjs, which the turn rung leaves out.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  STILL,
  fullest,
  meanDiff,
  peak,
  deadBeats,
  sampleTimes,
  seamStripStart,
  stripEnd,
  stripStart,
} from "../../skills/explainer-video/scripts/lib/motion.mjs";

test("the peak frame is the one with the largest difference from the frame before it", () => {
  // diffs[k] compares frame first+k+1 with frame first+k.
  const p = peak([1, 2, 9, 3], 100, 30);
  assert.deepEqual(p, { still: false, frame: 103, t: 103 / 30, diff: 9 });
});

test("a tie goes to the earliest frame", () => {
  assert.equal(peak([4, 7, 7, 7], 0, 30).frame, 2);
});

test("a scene nothing moves in is still, and its frame is the middle one", () => {
  const p = peak([0, 0, 0, 0, 0, 0, 0, 0, 0], 60, 30);
  assert.equal(p.still, true);
  assert.equal(p.frame, 65);
  // The encode's noise floor is not motion.
  assert.equal(peak([STILL, STILL / 2, 0], 0, 30).still, true);
  assert.equal(peak([STILL, STILL * 2, 0], 0, 30).still, false);
});

test("a seam's frames are never the peak, and a still scene's frame stays outside it", () => {
  const diffs = [1, 2, 9, 3, 4];
  // Frames 103 and 104 sit in [3.4, 3.5): the next largest difference wins.
  assert.equal(peak(diffs, 100, 30, [[102 / 30, 105 / 30]]).frame, 105);
  assert.equal(peak(diffs, 100, 30, [[5, 6]]).frame, 103);
  // The middle frame (65) is in the seam: the nearest one outside it is taken, the earlier of two.
  const p = peak(Array(9).fill(0), 60, 30, [[64 / 30, 67 / 30]]);
  assert.deepEqual([p.still, p.frame], [true, 63]);
  // A scene wholly in a seam falls back to the unfiltered peak.
  assert.equal(peak(diffs, 100, 30, [[0, 99]]).frame, 103);
  // A seam over every frame but the first leaves the first frame to judge.
  assert.equal(peak([9], 0, 30, [[1 / 30, 1]]).frame, 0);
});

test("sample times are the 0.5 s grid, the last frame and each event's frame, once", () => {
  const base = { start: 2, duration: 4, fps: 30 };
  const grid = sampleTimes(base).map((t) => Math.round(t * 30));
  assert.deepEqual(grid, [60, 75, 90, 105, 120, 135, 150, 165, 179]);
  // 2.5 s is on the grid already; 3.01 s takes frame 91, 3.0 s frame 90; one
  // before the scene and one past it are no sample of it.
  const ev = sampleTimes({ ...base, events: [2.5, 3.01, 3.0, 1, 6.5, 5.999] });
  assert.deepEqual(
    ev.map((t) => Math.round(t * 30)),
    [60, 75, 90, 91, 105, 120, 135, 150, 165, 179],
  );
});

test("the fullest sample has the most words, the latest on a tie, the last when none read", () => {
  const at = (...w) => w.map((words, i) => ({ t: i, words }));
  assert.equal(fullest(at(1, 3, 3, 2)), 2);
  assert.equal(fullest(at(4, 1, 4, 4)), 3);
  assert.equal(fullest(at(0, 0, 0)), 2);
});

test("mean absolute difference reads two frames' bytes", () => {
  assert.equal(
    meanDiff(Buffer.from([0, 10, 20]), Buffer.from([0, 20, 10])),
    20 / 3,
  );
  assert.equal(meanDiff(Buffer.from([5, 5]), Buffer.from([5, 5])), 0);
});

test("a dead beat is a stretch of 1.5 s or more of the scene's timeline with no tween running", () => {
  const scene = { start: 10, duration: 6 };
  // Tweens run 10-11 and 12.6-13: the gap 11-12.6 is 1.6 s.
  assert.deepEqual(
    deadBeats(scene, [
      [10, 11],
      [12.6, 13],
    ]),
    [
      { start: 11, end: 12.6 },
      { start: 13, end: 16 },
    ],
  );
  // A tween inside the 1.6 s stretch splits it into two short ones.
  assert.deepEqual(
    deadBeats(scene, [
      [10, 11],
      [11.5, 12],
      [12.6, 13],
      [13.5, 16],
    ]),
    [],
  );
  // Overlapping tweens count once, and a tween window is clipped to the scene.
  assert.deepEqual(
    deadBeats({ start: 0, duration: 4 }, [
      [-1, 1],
      [0.5, 1.2],
    ]),
    [{ start: 1.2, end: 4 }],
  );
  // No tween at all is a dead beat from end to end.
  assert.deepEqual(deadBeats({ start: 2, duration: 3 }, []), [
    { start: 2, end: 5 },
  ]);
  // A stretch just under 1.5 s is no dead beat.
  assert.deepEqual(deadBeats({ start: 0, duration: 1.4 }, []), []);
  // Exactly 1.5 s is one; a tween ending on the scene's last moment leaves none.
  assert.deepEqual(deadBeats({ start: 0, duration: 1.5 }, []), [
    { start: 0, end: 1.5 },
  ]);
  assert.deepEqual(deadBeats({ start: 0, duration: 4 }, [[0, 4]]), []);
});

test("the strip starts 5 frames before the peak and stays inside the scene", () => {
  assert.equal(stripStart(50, 0, 200), 45);
  assert.equal(stripStart(2, 0, 200), 0);
  assert.equal(stripStart(199, 0, 200), 188);
  assert.equal(stripEnd(188, 0, 200), 199);
  // A scene shorter than a strip: the strip starts at its first frame and ends at its last.
  assert.equal(stripStart(5, 10, 8), 10);
  assert.equal(stripEnd(10, 10, 8), 17);
});

test("the strip steps off a seam: its first and last frame, and every one between, sit outside the seam window", () => {
  const inSeam = (f, seams) =>
    seams.some(([a, b]) => f / 30 >= a && f / 30 < b);
  // A seam over frames 45-50 pushes a strip due at 47 to start after it.
  const seams = [[45 / 30, 51 / 30]];
  const from = stripStart(52, 0, 200, 30, seams);
  assert.equal(from, 51);
  // A seam after the peak ends the strip before it, the nearest start kept.
  const early = stripStart(44, 0, 200, 30, [[50 / 30, 56 / 30]]);
  assert.equal(early, 38);
  for (const [f, s] of [
    [from, seams],
    [early, [[50 / 30, 56 / 30]]],
  ])
    for (let k = f; k < f + 12; k++) assert.ok(!inSeam(k, s), `frame ${k}`);
  // No seam: unchanged.
  assert.equal(stripStart(50, 0, 200, 30, []), 45);
  // No room between seams: the clamped start, as before.
  assert.equal(stripStart(50, 0, 200, 30, [[0, 100]]), 45);
});

test("a seam's strip is 12 frames centred on its window, from the frame the window opens in", () => {
  // 6 frames, 60-66: three frames of lead, three after.
  assert.equal(seamStripStart([2, 2.2], 30), 57);
  // A window of 12 or more frames starts at its own first frame.
  assert.equal(seamStripStart([2, 2.5], 30), 60);
  // Never before the video's first frame.
  assert.equal(seamStripStart([0, 0.2], 30), 0);
});
