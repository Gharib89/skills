// The loop seam: a sound loops clean when the join has no click and no jump in
// level.
import { test } from "node:test";
import assert from "node:assert/strict";
import { seam } from "../../skills/creative-video/scripts/lib/seam.mjs";

const RATE = 8000;
// `seconds` of a 200 Hz tone, whole cycles, `edit` applied to the samples.
const tone = (edit = () => {}, seconds = 1) => {
  const s = Float32Array.from(
    { length: RATE * seconds },
    (_, i) => 0.5 * Math.sin((2 * Math.PI * 200 * i) / RATE),
  );
  edit(s);
  return s;
};

test("a tone of whole cycles loops clean", () => {
  const r = seam(tone(), RATE);
  assert.equal(r.clean, true, JSON.stringify(r));
  assert.ok(r.level < 0.1);
});

test("a jump at the join fails the seam, though every other step is small", () => {
  const r = seam(
    tone((s) => {
      for (let i = 0; i < 40; i++) s[s.length - 1 - i] += 0.4;
    }),
    RATE,
  );
  assert.equal(r.clean, false);
  assert.ok(r.jump > r.step, JSON.stringify(r));
});

test("a last 50 ms more than 3 dB off the first fails the seam, which a loop would swell or drop at", () => {
  const faded = (gain) =>
    seam(
      tone((s) => {
        for (let i = s.length - 400; i < s.length; i++) s[i] *= gain;
      }),
      RATE,
    );
  assert.equal(faded(0.2).clean, false);
  assert.equal(faded(0.2).level.toFixed(1), "14.0");
  assert.equal(faded(0.8).clean, true);
});

test("a file silent at both ends has no level to differ by, and one silent at one end is not clean", () => {
  const quiet = (s, from, to) => s.fill(0, from, to);
  assert.deepEqual(
    seam(
      tone((s) => quiet(s, 0, 400)),
      RATE,
    ).level === null,
    false,
  );
  const both = tone((s) => {
    quiet(s, 0, 400);
    quiet(s, s.length - 400);
  });
  const r = seam(both, RATE);
  assert.equal(r.level, null);
  assert.equal(r.clean, true);
  assert.equal(
    seam(
      tone((s) => quiet(s, 0, 400)),
      RATE,
    ).clean,
    false,
  );
});
