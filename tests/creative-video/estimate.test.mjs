// The render estimate (lib/estimate.mjs): the rates table's refusals, the
// estimate and budget arithmetic, the m:ss clock, and the calibrator's rate
// math.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  BUDGET,
  clock,
  estimate,
  loadRates,
  median,
  ratesFrom,
} from "../../skills/creative-video/scripts/lib/estimate.mjs";

function table(t, body) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-rates-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, "render-rates.json");
  if (body !== undefined)
    fs.writeFileSync(
      file,
      typeof body === "string" ? body : JSON.stringify(body),
    );
  return file;
}

test("the shipped table loads with a HyperFrames version and a render and an audio rate", () => {
  const t = loadRates();
  assert.match(t.hyperframes, /^\d+\.\d+\.\d+$/);
  assert.ok(t.rates.render >= 0 && t.rates.audio >= 0);
  assert.equal(BUDGET, 5);
});

test("a table that is missing, not JSON or of the wrong shape is refused, naming the file and the field", (t) => {
  const ok = { hyperframes: "0.8.206", rates: { render: 1, audio: 0.1 } };
  const bad = [
    [undefined, /: cannot be read \(ENOENT\)$/],
    ["{", /: is not JSON \(/],
    [
      { ...ok, hyperframes: "" },
      /: hyperframes is not the HyperFrames version/,
    ],
    [{ hyperframes: "0.8.206" }, /: rates is not an object of rates$/],
    [
      { ...ok, rates: { audio: 0.1 } },
      /: rates\.render is not a number of 0 or more$/,
    ],
    [
      { ...ok, rates: { render: 1, audio: -1 } },
      /: rates\.audio is not a number of 0 or more$/,
    ],
    [
      { ...ok, rates: { render: "1", audio: 0.1 } },
      /: rates\.render is not a number of 0 or more$/,
    ],
  ];
  for (const [body, why] of bad) {
    const file = table(t, body);
    assert.throws(() => loadRates(file), why);
    assert.throws(() => loadRates(file), new RegExp(path.basename(file)));
  }
  assert.deepEqual(loadRates(table(t, ok)), ok);
});

test("the estimate is the chapters to render at the render rate plus the whole video at the audio rate, against 5 times the video", () => {
  const rates = { render: 4, audio: 0.5 };
  assert.deepEqual(estimate(120, 240, rates), {
    seconds: 120 * 4 + 240 * 0.5,
    budget: 1200,
  });
  // Every chapter cached: the audio pass alone.
  assert.deepEqual(estimate(0, 240, rates), { seconds: 120, budget: 1200 });
});

test("clock writes whole seconds as m:ss", () => {
  assert.equal(clock(0), "0:00");
  assert.equal(clock(59.4), "0:59");
  assert.equal(clock(59.5), "1:00");
  assert.equal(clock(605), "10:05");
  assert.equal(clock(3725), "62:05");
});

test("the rates are the cold median less the cached median over the video, the audio the cached median over it, and a negative delta is zero", () => {
  assert.equal(median([9, 1, 5]), 5);
  assert.equal(median([4, 2, 8, 6]), 4);
  assert.deepEqual(
    ratesFrom({ cold: [150, 120, 180], cached: [20, 40, 30] }, 60),
    {
      render: 2,
      audio: 0.5,
    },
  );
  assert.equal(
    ratesFrom({ cold: [10, 11, 12], cached: [20, 21, 22] }, 60).render,
    0,
  );
});
