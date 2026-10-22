// The `canvas` component at compile: items placed on a map the camera visits
// in turn, each on its cue. It is rich (it draws its own camera), so a
// `camera` key is refused on it, and a profile that bans `camera` bans it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  VISUALS,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";

const said = ["Start with the source.", "Then the build.", "Then the release."];
const canvas = (props) => ({
  component: "canvas",
  props: {
    items: [
      { at: 1, title: "Source", body: "Where the change begins" },
      { at: 2, on: "the build", title: "Build", body: "Compiled and tested" },
      { at: 3, title: "Release", body: "Shipped to 1,200 users" },
    ],
    ...props,
  },
});
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("a canvas of titled items on cues compiles", () => {
  assert.doesNotThrow(() => checkVisual(canvas(), said));
});

test("a canvas holds 2 to 6 items, each with a title and a body", () => {
  bad(canvas({ items: [{ at: 1, title: "A", body: "b" }] }), /items/);
  bad(
    canvas({
      items: Array.from({ length: 7 }, () => ({
        at: 1,
        title: "A",
        body: "b",
      })),
    }),
    /items/,
  );
  bad(
    canvas({
      items: [
        { at: 1, body: "b" },
        { at: 2, title: "B", body: "b" },
      ],
    }),
    /canvas needs a title per item/,
  );
  bad(
    canvas({
      items: [
        { at: 1, title: "A" },
        { at: 2, title: "B", body: "b" },
      ],
    }),
    /canvas needs a body per item/,
  );
});

test("an item cues on a sentence the scene has, and takes no unknown prop", () => {
  bad(
    canvas({
      items: [
        { at: 1, title: "A", body: "a" },
        { at: 9, title: "B", body: "b" },
      ],
    }),
    /at 9/,
  );
  bad(
    canvas({
      items: [
        { at: 1, title: "A", body: "a", icon: "x" },
        { at: 2, title: "B", body: "b" },
      ],
    }),
    /icon/,
  );
  bad(canvas({ zoom: 2 }), /zoom/);
});

test("the camera visits the items in the order written, so a cue never runs backwards", () => {
  bad(
    canvas({
      items: [
        { at: 2, title: "A", body: "a" },
        { at: 1, title: "B", body: "b" },
      ],
    }),
    /canvas item 2 cues before item 1/,
  );
});

test("a canvas draws its own camera, so a camera key is refused", () => {
  bad(
    { ...canvas(), camera: { at: 2 } },
    /canvas draws its own camera, so it takes no camera key/,
  );
});

test("a canvas lists its items for the readers and its numbers for the script gate", () => {
  const v = VISUALS.canvas;
  const p = canvas().props;
  assert.deepEqual(
    v.items(p).map(([name, at]) => [name, at]),
    [
      ["item 1", 1],
      ["item 2", 2],
      ["item 3", 3],
    ],
  );
  assert.deepEqual(v.numbers(p), ["1,200"]);
});

test("a profile that bans camera bans the canvas component", () => {
  assert.match(
    banReason(["camera"], "canvas", "plain"),
    /canvas uses camera, which style profile plain bans/,
  );
  assert.equal(banReason([], "canvas", "plain"), null);
});
