// The `stack3d` component at compile: lit layers drawn in 3D, each rising on
// its cue with its label. It is rich (it draws its own frame, camera included),
// it draws WebGL, and a `3d` ban bars it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  checkVisual,
  drawsWebgl,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";

const said = [
  "A request enters the edge.",
  "The gateway checks the token.",
  "Then the service reads the store.",
];
const stack = (layers) => ({ component: "stack3d", props: { layers } });
const layer = (at, label, more = {}) => ({ at, label, ...more });
const LAYERS = [
  layer(1, "Edge"),
  layer(2, "Gateway", { on: "the token" }),
  layer(3, "Store"),
];
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("a stack of labelled layers compiles", () => {
  assert.doesNotThrow(() => checkVisual(stack(LAYERS), said));
});

test("a stack holds two to six layers", () => {
  bad(stack([layer(1, "Edge")]), /stack3d needs 2 to 6 layers/);
  bad(
    stack(Array.from({ length: 7 }, (_, i) => layer(1, `L${i}`))),
    /stack3d needs 2 to 6 layers/,
  );
});

test("a layer needs a label, a cue said in its sentence and no stray prop", () => {
  bad(stack([layer(1, ""), layer(2, "B")]), /stack3d needs a label per layer/);
  bad(
    stack([layer(1, "A"), layer(2, "B", { on: "the ocean" })]),
    /on "the ocean" is not said in sentence 2/,
  );
  bad(
    stack([layer(1, "A"), layer(2, "B", { depth: 3 })]),
    /a stack3d layer has no prop depth/,
  );
});

test("a stack3d is rich: it draws its own camera, so a camera key is refused", () => {
  bad(
    { ...stack(LAYERS), camera: { at: 2 } },
    /stack3d draws its own camera, so it takes no camera key/,
  );
});

test("a profile that bans 3d bars the stack3d", () => {
  assert.match(
    banReason(["3d"], "stack3d", "plain"),
    /component stack3d uses 3d, which style profile plain bans/,
  );
});

test("a scene draws WebGL when its component says so, and no other does", () => {
  assert.equal(drawsWebgl([{ visual: { component: "stack3d" } }]), true);
  assert.equal(
    drawsWebgl([
      { visual: { component: "diagram" } },
      { visual: { component: "title" } },
    ]),
    false,
  );
  assert.equal(drawsWebgl([]), false);
});
