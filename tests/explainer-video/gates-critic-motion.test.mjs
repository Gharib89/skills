// The video gates through their process doors, part 4d: what the critic reads
// of motion: a strip per seam, a motion strip clear of seams, dead beats read
// off the timeline.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { sceneFrames } from "../../skills/explainer-video/scripts/lib/motion.mjs";
import {
  SEAMS,
  calls,
  fixture,
  read,
  record,
  renderUnjudged,
  seamRecord,
} from "./gates-lib.mjs";
import { SCRIPT } from "./scene-file.mjs";

const sheets = (fx) => path.join(fx.dir, record(fx).gates.critic.sheets);
const motion = (fx, id) => JSON.parse(read(sheets(fx), `${id}.motion.json`));

test("a scene that hands over at a seam gets a second strip of that seam, listed in its record; the last scene gets none", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  for (const id of Object.keys(SEAMS)) {
    const png = path.join(sheets(fx), `${id}.seam.png`);
    assert.deepEqual(motion(fx, id).seam, seamRecord(id), id);
    assert.equal(fs.existsSync(png), !!SEAMS[id], id);
    const cut = calls(fx, "strip").find((c) => c.output === png);
    assert.equal(cut?.first, SEAMS[id]?.first, id);
  }
});

test("the motion strip of a scene with a seam starts and ends outside the seam window", () => {
  const probe = fixture();
  assert.equal(renderUnjudged(probe, SCRIPT).code, 1);
  const hook = JSON.parse(read(probe.dir, "timeline.json")).scenes[0];
  const { n } = sceneFrames({ ...hook, fps: 30 });
  // A peak at frame 129, 6 before the seam: the strip due at 124 would run
  // 124-135 into the seam that opens at frame 135.
  const diffs = Array(n - 1).fill(1);
  diffs[128] = 9;
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_MOTION: JSON.stringify({ 0: diffs }),
  });
  assert.equal(r.code, 1, r.out + r.err);
  const { peak, strip } = motion(fx, "hook");
  assert.equal(peak.frame, 129);
  assert.ok(strip.last < SEAMS.hook.window[0], JSON.stringify(strip));
});

test("a stretch of 1.6 s with no tween running is a dead beat; a tween inside it removes it", () => {
  const probe = fixture();
  assert.equal(renderUnjudged(probe, SCRIPT).code, 1);
  const [, steps] = JSON.parse(read(probe.dir, "timeline.json")).scenes;
  // Tweens run 0-1 s and 2.6-4.9 s of the steps scene, leaving 1-2.6 s; the
  // gate scene's extra tween at 1.4-1.6 s splits its gap in two short ones.
  const events = {
    steps: {
      tweens: [
        [0, 1],
        [2.6, 4.9],
      ],
    },
    gate: {
      tweens: [
        [0, 1],
        [1.4, 1.6],
        [2.6, 5.3],
      ],
    },
  };
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_EVENTS: JSON.stringify(events),
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.deepEqual(motion(fx, "steps").dead, [
    {
      start: +(steps.start + 1).toFixed(3),
      end: +(steps.start + 2.6).toFixed(3),
    },
  ]);
  assert.deepEqual(motion(fx, "gate").dead, []);
});
