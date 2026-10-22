// The real backend's band reader and contact sheet against videos the real
// ffmpeg generates, split from motion.test.mjs so the turn rung, which leaves
// this file out, spawns no ffmpeg. Skipped where ffmpeg is not installed.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { peak } from "../../skills/explainer-video/scripts/lib/motion.mjs";
import {
  bandMotion,
  sheet,
} from "../../skills/explainer-video/scripts/lib/backend.mjs";

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

// The sheet's fourth tile is the fullest frame whatever its place in time.
test(
  "the real contact sheet puts the fullest frame fourth, ahead of the quarter marks it precedes",
  { skip: !ffmpeg && "ffmpeg is not installed" },
  async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-sheet-"));
    try {
      // Frame N is a flat grey of 4N, so a tile's grey names its frame.
      const video = path.join(tmp, "v.mp4");
      let r = spawnSync("ffmpeg", [
        ...["-hide_banner", "-v", "error", "-y", "-f", "lavfi"],
        ...["-i", "nullsrc=s=1920x1080:r=30:d=2,geq=lum=4*N:cb=128:cr=128"],
        ...["-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "0", video],
      ]);
      assert.equal(r.status, 0, String(r.stderr));
      const png = path.join(tmp, "sheet.png");
      // 60 frames from 0: quarter marks 15, 30, 45; the fullest is frame 5.
      await sheet(video, png, { start: 0, duration: 2, fps: 30, fullest: 5 });
      r = spawnSync(
        "ffmpeg",
        [
          ...["-hide_banner", "-v", "error", "-i", png],
          ...["-vf", "format=gray", "-f", "rawvideo", "-"],
        ],
        { maxBuffer: 1 << 25 },
      );
      assert.equal(r.status, 0, String(r.stderr));
      const grey = (x, y) => r.stdout[y * 1920 + x];
      const tiles = [
        [480, 270],
        [1440, 270],
        [480, 810],
        [1440, 810],
      ].map(([x, y]) => grey(x, y));
      // Grey rises with the frame: the three marks in order, the earlier
      // frame 5 last.
      const [q1, q2, q3, full] = tiles;
      assert.ok(full < q1 && q1 < q2 && q2 < q3, `tiles ${tiles}`);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  },
);
