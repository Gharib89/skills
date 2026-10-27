// The stream-copy join of the real backend, read by the real ffmpeg: two 1 s
// parts joined from paths relative to the working directory, the way a run
// folder given as `creative-videos/<slug>` names them. Skipped where ffmpeg is
// not on PATH.
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { concat } from "../../skills/creative-video/scripts/lib/backend/media.mjs";

const has = spawnSync("ffmpeg", ["-version"]).status === 0;

function part(file, color) {
  const r = spawnSync("ffmpeg", [
    ...["-v", "error", "-y", "-f", "lavfi", "-i"],
    `color=c=${color}:s=64x64:r=30:d=1`,
    ...["-c:v", "libx264", "-pix_fmt", "yuv420p", file],
  ]);
  assert.equal(r.status, 0, r.stderr?.toString());
}

const seconds = (file) =>
  +spawnSync("ffprobe", [
    ...["-v", "error", "-show_entries", "format=duration"],
    ...["-of", "default=nw=1:nk=1", file],
  ]).stdout.toString();

test(
  "a join from relative part paths reads the parts from the working directory, not from the list's folder",
  { skip: !has && "ffmpeg is not on PATH" },
  async () => {
    const dir = fs.mkdtempSync(path.join(process.cwd(), ".creative-join-"));
    try {
      const abs = ["one.mp4", "two.mp4"].map((f) => path.join(dir, f));
      part(abs[0], "red");
      part(abs[1], "blue");
      const rel = (f) => path.relative(process.cwd(), f);
      await concat(abs.map(rel), rel(path.join(dir, "joined.mp4")));
      assert.ok(
        Math.abs(seconds(path.join(dir, "joined.mp4")) - 2) < 0.1,
        "the two 1 s parts join into 2 s",
      );
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  },
);
