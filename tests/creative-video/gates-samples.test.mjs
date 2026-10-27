// The sample times of a scene (gates/samples.mjs): the in, key and out stills
// the gates judge and the storyboard card shows.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  FPS,
  frames,
} from "../../skills/creative-video/scripts/render/grid.mjs";
import { sampleTimes } from "../../skills/creative-video/scripts/gates/samples.mjs";

const onFrame = (t, start) =>
  Math.abs((t - start) * FPS - Math.round((t - start) * FPS)) < 0.031;

test("a scene is sampled 0.3 s in, at its middle and on its last frame, each on a whole frame written to 3 places", () => {
  const sc = { start: 8.133333, duration: 4.4 };
  const t = sampleTimes(sc);
  assert.deepEqual(t, { in: 8.434, key: 10.334, out: 12.5 });
  for (const v of Object.values(t)) {
    assert.ok(onFrame(v, sc.start), String(v));
    assert.equal(v, +v.toFixed(3));
    assert.ok(v >= sc.start && v < sc.start + sc.duration);
  }
  // the last frame is the one before the scene ends
  assert.ok(t.out + 1 / FPS - 0.001 <= sc.start + sc.duration + 0.001);
  assert.equal(Math.round((t.out - sc.start) * FPS), frames(sc.duration) - 1);
});

test("a scene shorter than 0.6 s takes its middle as the in still, and one frame long has all three on it", () => {
  const short = sampleTimes({ start: 2, duration: 0.5 });
  assert.equal(short.in, short.key);
  assert.ok(short.in >= 2 && short.out < 2.5);
  const one = sampleTimes({ start: 0, duration: 1 / FPS });
  assert.deepEqual(one, { in: 0, key: 0, out: 0 });
});

test("a time on a millisecond is not pushed to the next one", () => {
  assert.deepEqual(sampleTimes({ start: 0, duration: 3 }), {
    in: 0.3,
    key: 1.5,
    out: 2.967,
  });
});
