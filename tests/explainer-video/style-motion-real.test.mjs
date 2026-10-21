// measure.mjs on a real video, read by the real ffmpeg: a 6 s clip of three
// shots, so a few seconds of CPU and no HyperFrames. Skipped where ffmpeg is
// not on PATH.
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { candidates, fixture, node } from "./style-lib.mjs";

const has = spawnSync("ffmpeg", ["-version"]).status === 0;
const half = (left, right) =>
  `color=c=${left}:s=1440x810:r=25:d=2,drawbox=x=720:y=0:w=720:h=810:c=${right}:t=fill`;

// Three 2 s shots, a cream half beside a dark one and then the reverse, then
// the first again: cuts at 2 s and 4 s. `blur` softens the 0.4 s before each
// cut, `grain` adds luma noise; frames are intra-coded so neither is smoothed
// away.
function clip(file, { blur = false, grain = false }) {
  const filters = [
    `${half("0xf5f4ed", "0x141413")}[a]`,
    `${half("0x141413", "0xf5f4ed")}[b]`,
    `${half("0xf5f4ed", "0x141413")}[c]`,
    "[a][b][c]concat=n=3:v=1:a=0" +
      (blur
        ? ",gblur=sigma=12:enable='between(t,1.6,1.99)+between(t,3.6,3.99)'"
        : "") +
      (grain ? ",noise=alls=12:allf=t" : "") +
      "[o]",
  ].join(";");
  const r = spawnSync("ffmpeg", [
    ...["-v", "error", "-y", "-filter_complex", filters, "-map", "[o]"],
    ...["-c:v", "mjpeg", "-q:v", "2", file],
  ]);
  assert.equal(r.status, 0, r.stderr?.toString());
}

function measure(opts) {
  const { run, docs, env } = fixture();
  delete env.EXPLAINER_VIDEO_BACKEND;
  const file = path.join(docs, "ref.mkv");
  clip(file, opts);
  const r = node("measure.mjs", [run, file], env);
  assert.equal(r.status, 0, r.stderr);
  return {
    motion: candidates(run).motion,
    refs: path.join(run, "style-draft", "refs"),
  };
}

test("a real clip's cuts, blur and grain are measured", { skip: !has }, () => {
  const { motion: sharp, refs } = measure({});
  assert.equal(sharp.cutsPerMinute, 20);
  assert.ok(sharp.blurAtCuts < 0.1, `blur ${sharp.blurAtCuts}`);
  assert.ok(sharp.grain < 0.05, `grain ${sharp.grain}`);
  // The frames before, at and after each cut stay as reference images.
  const names = fs.readdirSync(refs);
  for (const cut of [1, 2])
    for (const w of ["before", "at", "after"])
      assert.ok(names.includes(`ref-cut${cut}-${w}.png`), names.join());

  const { motion: soft } = measure({ blur: true, grain: true });
  assert.equal(soft.cutsPerMinute, 20);
  assert.ok(soft.blurAtCuts > 0.3, `blur ${soft.blurAtCuts}`);
  assert.ok(soft.grain > 0.15, `grain ${soft.grain}`);
});
