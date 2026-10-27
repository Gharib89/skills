// The maintainer real-render's fixture and frame comparison, and its refusal
// with a tool row missing; the renders themselves need real Chrome and run
// outside the suite.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  FPS,
  gridScenes,
  written,
} from "../../skills/creative-video/scripts/render/grid.mjs";
import { HOLD } from "../../skills/creative-video/scripts/lib/length.mjs";
import { lockHash } from "../../skills/creative-video/scripts/lib/tools.mjs";
import {
  differing,
  runFolder,
} from "../../skills/creative-video/maintainer/real-render-lib.mjs";
import { exec, install, readJson, timing } from "./timing-lib.mjs";
import { fixture, here } from "./voice-lib.mjs";

const script = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "maintainer",
  "real-render.mjs",
);

test("a fixture run folder times through the timing stage onto the grid its scene frames give, every scene authored", () => {
  const fx = fixture();
  install(fx);
  const run = runFolder(fx.tmp, "grid", [
    { id: "one", frames: 50 },
    { id: "two", frames: 42 },
  ]);
  const r = exec(timing, { ...fx, dir: run });
  assert.equal(r.code, 0, r.out + r.err);
  assert.doesNotMatch(r.out, /to author/);
  const tl = readJson(path.join(run, "timeline.json"));
  const grid = gridScenes([50 / FPS, 42 / FPS], HOLD);
  assert.equal(tl.total, written(grid.total));
  assert.deepEqual(
    tl.scenes.map((s) => s.duration),
    grid.map((g) => written(g.frames)),
  );
});

test("differing names each frame whose hash differs, and each frame past the shorter list's end", () => {
  assert.deepEqual(differing(["a", "b", "c"], ["a", "b", "c"]), []);
  assert.deepEqual(differing(["a", "b", "c"], ["a", "x", "c"]), [1]);
  assert.deepEqual(differing(["a", "b"], ["a", "b", "c", "d"]), [2, 3]);
  assert.deepEqual(differing(["a", "b", "c"], ["a"]), [1, 2]);
  assert.deepEqual(differing([], []), []);
});

test("with the render rows not installed it exits 2 naming each one", () => {
  const fx = fixture();
  const r = exec(script, fx, []);
  assert.equal(r.code, 2, r.out + r.err);
  assert.match(r.err, /npm-packages, chrome not installed/);
});

test("with ffmpeg off PATH it exits 2 naming the ffmpeg row alone", () => {
  const fx = fixture();
  install(fx);
  const chrome = path.join(
    fx.tmp,
    "cache",
    "creative-video",
    "chrome",
    lockHash,
  );
  fs.mkdirSync(chrome, { recursive: true });
  fs.writeFileSync(path.join(chrome, ".stamp"), "");
  const bin = path.join(fx.tmp, "bin");
  fs.mkdirSync(bin);
  const r = spawnSync(process.execPath, [script], {
    env: {
      PATH: bin,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
    },
    encoding: "utf8",
    timeout: 60000,
  });
  assert.equal(r.status, 2, r.stdout + r.stderr);
  assert.match(r.stderr, /: ffmpeg not installed/);
});
