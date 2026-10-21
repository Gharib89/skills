// The `stack3d` component drawn: a canvas Three.js draws into, its labels as DOM
// text beside it, and one tween on the scene's paused timeline that redraws the
// whole frame from the scene's time, so a seek renders the frame it names.
import { test } from "node:test";
import assert from "node:assert/strict";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = ["The issue is the base.", "A test sits on it.", "Then the code."];
const timing = {
  duration: 9,
  slot: 9,
  sentences: [0, 3, 6],
  words: Array.from({ length: 12 }, (_, i) => +(i * 0.7).toFixed(6)),
};
const props = {
  layers: [
    { at: 1, label: "Issue" },
    { at: 2, label: "Test" },
    { at: 3, label: "Code" },
  ],
};
const drawn = (dir = "ltr") =>
  sceneFile(
    { id: "a", narration: said, visual: { component: "stack3d", props } },
    timing,
    claude,
    { backend: {}, seam: {}, dir },
  );

test("the scene is a canvas and one DOM label per layer, drawn by a WebGL renderer", async () => {
  const html = await drawn();
  assert.match(html, /<canvas class="gl" width="1680" height="772">/);
  for (const [i, label] of ["Issue", "Test", "Code"].entries())
    assert.match(html, new RegExp(`<div class="lb b${i}">${label}</div>`));
  assert.match(html, /new THREE\.WebGLRenderer\(/);
  assert.match(html, /preserveDrawingBuffer: true/);
});

test("the redraw hangs on the paused timeline and reads no clock but the scene's", async () => {
  const html = await drawn();
  assert.match(html, /tl\.to\(clock, \{ t: 9, duration: 9, ease: "none"/);
  for (const clock of [
    "requestAnimationFrame",
    "Date.now",
    "performance.now",
    "Math.random",
  ])
    assert.ok(!html.includes(clock), `${clock} in the scene`);
});

test("a right to left scene puts each label before its slab, mirrored", async () => {
  assert.match(await drawn("ltr"), /translate\(0, -50%\)/);
  assert.match(await drawn("rtl"), /translate\(-100%, -50%\)/);
});
