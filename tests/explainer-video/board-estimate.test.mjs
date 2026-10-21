// The storyboard's render estimate through board build: the board document
// carries it from the shipped rates table, and each rich card its added seconds.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCRIPT, STACK3D } from "./scene-file.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import { dest } from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { board, doc, fixture, ok, prep, skill } from "./board-lib.mjs";

const table = JSON.parse(
  fs.readFileSync(path.join(skill, "render-rates.json"), "utf8"),
);
const r1 = (x) => Math.round(x * 10) / 10;
const WORDS = SCRIPT.replace(
  /\{\n {2}"component": "cards"[\s\S]*?\n\}\n/,
  '{ "component": "words", "props": { "lines": [ { "at": 1, "text": "reads the issue", "on": "reads" } ] } }\n',
);

// The WebGL scene's stills bundle three with esbuild: stand-ins for both, as
// render-lib.mjs gives the render tests.
function stackFixture() {
  const fx = fixture(STACK3D);
  const dirs = userDirs({ platform: "linux", env: fx.env, home: fx.env.HOME });
  const modules = path.join(dest({ kind: "npm" }, dirs), "node_modules");
  fs.mkdirSync(path.join(modules, "three", "build"), { recursive: true });
  fs.writeFileSync(
    path.join(modules, "three", "build", "three.module.js"),
    "/* three */",
  );
  fs.mkdirSync(path.join(modules, "esbuild"), { recursive: true });
  fs.writeFileSync(
    path.join(modules, "esbuild", "index.js"),
    `exports.buildSync = (o) => ({ outputFiles: [{ text: "/* bundle */" }] });`,
  );
  // a stack3d scene renders only where an NVIDIA card is found
  fx.env.EXPLAINER_VIDEO_FAKE_GPU = "7.5";
  return fx;
}

test("the rates table names the HyperFrames version it was measured on and a positive rate for each cost", () => {
  assert.match(table.hyperframes, /^\d+\.\d+\.\d+$/);
  assert.deepEqual(Object.keys(table.rates).sort(), [
    "base",
    "gates",
    "live3d",
    "texture",
  ]);
  for (const v of Object.values(table.rates)) assert.ok(v > 0, String(v));
});

test("the board document carries the estimate worked from the table over the cards' voiced seconds", () => {
  const fx = fixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const d = doc(fx, 1);
  const video = d.scenes.reduce((n, c) => n + c.seconds, 0);
  const { base, gates, texture } = table.rates;
  // claude-code plays the default texture, and no scene draws WebGL
  assert.equal(d.estimate.seconds, r1(video * (base + gates + texture)));
  assert.equal(d.estimate.budget, r1(video * 5));
  assert.equal(d.estimate.over, false);
  assert.equal(d.estimate.hyperframes, table.hyperframes);
  for (const c of d.scenes) assert.ok(!("adds" in c), c.id);
});

test("a rich card carries its added seconds, none for a component with no cost of its own", () => {
  const fx = fixture(WORDS);
  prep(fx);
  ok(board(fx, "build"), "build");
  const d = doc(fx, 1);
  assert.deepEqual(
    d.scenes.map((c) => c.adds),
    [undefined, 0, undefined],
  );
});

test("a live 3D card adds its voiced seconds at the live 3D rate", () => {
  const fx = stackFixture();
  prep(fx);
  ok(board(fx, "build"), "build");
  const [c] = doc(fx, 1).scenes;
  assert.equal(c.adds, r1(c.seconds * table.rates.live3d));
  assert.ok(c.adds > 0);
});
