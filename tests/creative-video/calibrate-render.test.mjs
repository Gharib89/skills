// The render-rate calibration's process door (maintainer/calibrate-render-
// rates.mjs): its usage and its refusal with a tool row missing; the renders
// themselves need real Chrome and run outside the suite, and the arithmetic is
// estimate.test.mjs's.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fixture, here } from "./voice-lib.mjs";

const script = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "maintainer",
  "calibrate-render-rates.mjs",
);

// The script run on a temp machine with PATH holding only stand-ins for `tools`.
function run(args, tools = []) {
  const fx = fixture();
  const bin = path.join(fx.tmp, "bin");
  fs.mkdirSync(bin);
  for (const t of tools)
    fs.writeFileSync(path.join(bin, t), "#!/bin/sh\n", { mode: 0o755 });
  return spawnSync(process.execPath, [script, ...args], {
    env: {
      PATH: bin,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
    },
    encoding: "utf8",
    timeout: 60000,
  });
}

test("a bad --runs or --seconds, an unknown flag or a second file is usage, and nothing is written", () => {
  for (const args of [
    ["--runs", "0"],
    ["--runs", "two"],
    ["--seconds", "3"],
    ["--nope"],
    ["a.json", "b.json"],
  ]) {
    const r = run(args);
    assert.equal(r.status, 2, args.join(" "));
    assert.match(r.stderr, /^usage: node calibrate-render-rates\.mjs /);
  }
});

test("with the render rows not installed it exits 2 naming each one", () => {
  const r = run([], ["ffmpeg", "ffprobe"]);
  assert.equal(r.status, 2, r.stdout + r.stderr);
  assert.match(
    r.stderr,
    /^calibrate-render: npm-packages, chrome not installed/,
  );
});
