// The render stage through its process door: a scene that draws WebGL needs an
// NVIDIA card (the `gpu-3d` row), takes HyperFrames' host GPU for every render,
// and keys its caches on that mode; no other scene changes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCRIPT, STACK3D } from "./scene-file.mjs";
import { calls, comp, fixture, render } from "./render-lib.mjs";
import { renderInputs } from "../../skills/explainer-video/scripts/lib/tools.mjs";

const card = { EXPLAINER_VIDEO_FAKE_GPU: "7.5" };

test("a stack3d scene on a machine with no card is refused with the row's reason before anything renders", () => {
  for (const [what, env, why] of [
    ["no card", {}, /no card found/],
    [
      "a failed probe",
      { EXPLAINER_VIDEO_FAKE_GPU: "failed" },
      /nvidia-smi failed/,
    ],
  ]) {
    const fx = fixture(STACK3D);
    const r = render(fx, env);
    assert.equal(r.code, 1, `${what}: ${r.out}${r.err}`);
    assert.match(r.err, /^render: gpu-3d: unavailable without an NVIDIA GPU/m);
    assert.match(r.err, why);
    assert.equal(calls(fx).length, 0, `${what} rendered`);
  }
});

test("every HyperFrames render of a scene that draws WebGL carries --browser-gpu, the stills too", () => {
  const fx = fixture(STACK3D);
  const r = render(fx, card);
  assert.equal(r.code, 0, r.out + r.err);
  const drawn = calls(fx);
  assert.deepEqual(
    drawn.map((c) => [
      c.args.includes("png-sequence"),
      c.args.includes("--browser-gpu"),
    ]),
    [
      [true, true],
      [false, true],
    ],
  );
});

test("a run with no scene that draws WebGL never asks for the host GPU, card or none", () => {
  for (const env of [card, {}]) {
    const fx = fixture(SCRIPT);
    const r = render(fx, env);
    assert.equal(r.code, 0, r.out + r.err);
    assert.ok(calls(fx).length > 0);
    for (const c of calls(fx)) assert.ok(!c.args.includes("--browser-gpu"));
    assert.ok(!fs.existsSync(path.join(fx.dir, "composition", "three.min.js")));
  }
});

test("three is bundled to a classic script beside GSAP and the page loads it, only for a WebGL run", () => {
  const fx = fixture(STACK3D);
  const r = render(fx, card);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    comp(fx, "three.min.js"),
    /bundle of \/three\/build\/three\.module\.js as THREE/,
  );
  const page = comp(fx);
  assert.ok(
    page.indexOf('src="gsap.min.js"') < page.indexOf('src="three.min.js"'),
  );
  const plain = fixture(SCRIPT);
  render(plain);
  assert.doesNotMatch(comp(plain), /three\.min\.js/);
});

test("the render cache key names the GPU mode: the inputs differ for a WebGL run", () => {
  const inputs = (webgl) => renderInputs([], {}, webgl);
  assert.notDeepEqual(inputs(true), inputs(false));
  assert.deepEqual(inputs(false), renderInputs([], {}));
  assert.ok(inputs(true).includes("browser-gpu"));
});

test("the determinism gate renders a WebGL scene's two frames on SwiftShader and every other scene's as before", () => {
  const plain = `
## Scene hook · The promise

### Narration
1. Ship takes one issue to a reviewed pull request. [ex-1]

### Visual
\`\`\`json
{ "component": "title", "props": { "kicker": "Ship", "title": "From issue to pull request", "subtitle": "One run, one merge" } }
\`\`\`
`;
  const fx = fixture(STACK3D + plain);
  const r = render(fx, card);
  assert.equal(r.code, 0, r.out + r.err);
  const frames = calls(fx, "frame");
  assert.deepEqual(
    frames.map((c) => [path.basename(c.out).split("-")[0], c.software]),
    [
      ["stack", true],
      ["stack", true],
      ["hook", false],
      ["hook", false],
    ],
  );
});
