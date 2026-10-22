// The maintainer render-rate calibration through its process door: a copy of
// render-rates.json, the canned backend, and the table it writes back.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { calls, fixture, skill, temps } from "./render-lib.mjs";
import { dest } from "../../skills/explainer-video/scripts/lib/tools.mjs";

const script = path.join(skill, "maintainer", "calibrate-render-rates.mjs");

// A fixture machine whose HyperFrames reads 9.9.9, and a copy of the table.
function machine(extra = {}) {
  const fx = fixture();
  const pkg = path.join(
    dest({ kind: "npm" }, fx.dirs),
    "node_modules",
    "hyperframes",
  );
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "package.json"),
    JSON.stringify({ name: "hyperframes", version: "9.9.9" }),
  );
  const table = path.join(fx.tmp, "render-rates.json");
  fs.copyFileSync(path.join(skill, "render-rates.json"), table);
  const calibrate = (...args) =>
    spawnSync(process.execPath, [script, table, ...args], {
      env: { ...fx.env, ...extra },
      encoding: "utf8",
    });
  return { fx, table, calibrate };
}
const stack3d = { EXPLAINER_VIDEO_FAKE_GPU: "7.5" };
const read = (f) => JSON.parse(fs.readFileSync(f, "utf8"));

test("calibration writes the four rates and the HyperFrames version it measured, and names that version in its output", () => {
  const { table, calibrate } = machine(stack3d);
  const r = calibrate("--runs", "1");
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const t = read(table);
  assert.equal(t.hyperframes, "9.9.9");
  assert.deepEqual(Object.keys(t.rates), [
    "base",
    "texture",
    "live3d",
    "gates",
  ]);
  for (const v of Object.values(t.rates))
    assert.ok(Number.isFinite(v) && v >= 0, String(v));
  assert.match(
    r.stdout,
    /^calibrate-render: HyperFrames 9\.9\.9: base \S+, texture \S+, live3d \S+, gates \S+ render s per video s$/m,
  );
});

test("every timed run renders its video afresh, for a flat, a textured and a live 3D video", () => {
  const { fx, calibrate } = machine(stack3d);
  const r = calibrate("--runs", "2");
  assert.equal(r.status, 0, r.stdout + r.stderr);
  // 3 videos x 2 runs: the render cache is cleared before each run, so the
  // timed work is the render, never a cache hit
  const videos = calls(fx).filter((c) => c.args.includes("looks"));
  assert.equal(videos.length, 6, JSON.stringify(videos.map((c) => c.args)));
  assert.equal(
    (r.stdout.match(/^calibrate-render \w+ run \d\/2: /gm) ?? []).length,
    6,
  );
});

test("every timed run cuts the critic's contact sheets afresh, so a rate carries that cost", () => {
  const { fx, calibrate } = machine(stack3d);
  const r = calibrate("--runs", "2");
  assert.equal(r.status, 0, r.stdout + r.stderr);
  // one sheet per scene: 3 + 3 + 4 scenes over the three videos, in each of 2 runs
  assert.equal(calls(fx, "sheet").length, 2 * (3 + 3 + 4));
});

test("the live 3D lines name the stack scene's seconds, so its rate can be recomputed from the output", () => {
  const { calibrate } = machine(stack3d);
  const r = calibrate("--runs", "1");
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(
    r.stdout,
    /^calibrate-render live3d run 1\/1: .* s of video, \d+(\.\d+)? s of it the stack scene$/m,
  );
  assert.doesNotMatch(r.stdout, /^calibrate-render (flat|textured) .*stack/m);
});

test("the stack scene's seconds are its voiced length, the amount the live 3D video grows over the textured one", () => {
  const { calibrate } = machine(stack3d);
  const r = calibrate("--runs", "1");
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const video = (name) =>
    Number(
      r.stdout.match(new RegExp(`${name} run .* over (\\S+) s of video`))[1],
    );
  const stack = Number(r.stdout.match(/, (\S+) s of it the stack scene/)[1]);
  // the closing hold moves from the last scene to the stack scene, so it is in
  // neither the growth nor the voiced length; the timeline's duration for the
  // stack scene, which adds it, is a second off
  assert.ok(
    Math.abs(stack - (video("live3d") - video("textured"))) < 0.2,
    `${stack} s against a growth of ${video("live3d") - video("textured")} s`,
  );
});

test("a measurement that cannot run leaves the table alone and says why", () => {
  // no NVIDIA card: the live 3D video is refused by the render stage
  const { table, calibrate } = machine();
  const before = fs.readFileSync(table, "utf8");
  const r = calibrate("--runs", "1");
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^calibrate-render: .*live3d.*gpu-3d/m);
  assert.equal(fs.readFileSync(table, "utf8"), before);
});

test("a live 3D video with no voiced stack scene leaves the table alone and names the file and scene", () => {
  const { fx, table } = machine(stack3d);
  // A copy of the skill whose calibration names its stack scene otherwise, so
  // voice.json holds no scene `stack`
  const copy = fs.mkdtempSync(path.join(os.tmpdir(), "calibrate-nostack-"));
  temps.push(copy);
  fs.cpSync(skill, copy, { recursive: true });
  const file = path.join(copy, "maintainer", "calibrate-render-rates.mjs");
  fs.writeFileSync(
    file,
    fs
      .readFileSync(file, "utf8")
      .replace("## Scene stack ·", "## Scene pile ·"),
  );
  const before = fs.readFileSync(table, "utf8");
  const r = spawnSync(process.execPath, [file, table, "--runs", "1"], {
    env: { ...fx.env, ...stack3d },
    encoding: "utf8",
  });
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /^calibrate-render: live3d: voice\.json: .*stack/m);
  assert.equal(fs.readFileSync(table, "utf8"), before);
});

test("calibration refuses a bad command line", () => {
  const { calibrate } = machine();
  for (const args of [
    ["--runs"],
    ["--runs", "0"],
    ["--runs", "two"],
    ["--x"],
  ]) {
    const r = calibrate(...args);
    assert.equal(r.status, 2, args.join(" "));
    assert.match(
      r.stderr,
      /^usage: node calibrate-render-rates\.mjs /,
      args.join(" "),
    );
  }
});
