// The motion measures the determinism gate and the critic's motion strip share
// (lib/motion.mjs): pure functions over per-frame content-band differences,
// and the real backend's band reader against a video ffmpeg generates.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  STILL,
  meanDiff,
  peak,
  stillStretches,
  stripStart,
} from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { bandMotion } from "../../skills/explainer-video/scripts/lib/backend.mjs";

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

test("mean absolute difference reads two frames' bytes", () => {
  assert.equal(
    meanDiff(Buffer.from([0, 10, 20]), Buffer.from([0, 20, 10])),
    20 / 3,
  );
  assert.equal(meanDiff(Buffer.from([5, 5]), Buffer.from([5, 5])), 0);
});

test("a still stretch is a run of unchanged frames lasting at least 1.5 s", () => {
  // 10 fps keeps the arithmetic whole: 15 unchanged diffs are 1.5 s.
  const diffs = [
    ...Array(3).fill(5),
    ...Array(15).fill(0),
    ...Array(4).fill(5),
    ...Array(14).fill(0),
  ];
  assert.deepEqual(stillStretches(diffs, 0, 10), [{ start: 0.3, end: 1.8 }]);
});

test("the strip starts 5 frames before the peak and stays inside the scene", () => {
  assert.equal(stripStart(50, 0, 200), 45);
  assert.equal(stripStart(2, 0, 200), 0);
  assert.equal(stripStart(199, 0, 200), 188);
});

// The content band alone is read: a change in the caption rows moves nothing.
const ffmpeg = spawnSync("ffmpeg", ["-version"]).status === 0;
test(
  "a caption-only change does not move the peak, a content change does",
  { skip: !ffmpeg && "ffmpeg is not installed" },
  async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-motion-"));
    try {
      const video = (name, filter) => {
        const f = path.join(tmp, name);
        const r = spawnSync("ffmpeg", [
          ...["-hide_banner", "-v", "error", "-y"],
          ...["-f", "lavfi", "-i", "color=c=gray:s=1920x1080:r=30:d=2"],
          ...["-vf", filter, "-pix_fmt", "yuv420p", "-c:v", "libx264"],
          ...["-crf", "0", f],
        ]);
        assert.equal(r.status, 0, String(r.stderr));
        return f;
      };
      // A white box appears at 1 s: in the caption rows (top 900) or in the band.
      const box = (y) =>
        `drawbox=x=200:y=${y}:w=400:h=100:color=white:t=fill:enable='gte(t,1)'`;
      const opts = { start: 0, duration: 2, fps: 30 };
      const caption = await bandMotion(video("caption.mp4", box(900)), opts);
      assert.equal(peak(caption, 0, 30).still, true);
      const content = await bandMotion(video("content.mp4", box(400)), opts);
      const p = peak(content, 0, 30);
      assert.equal(p.still, false);
      assert.equal(p.frame, 30);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  },
);
