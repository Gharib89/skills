// The `critic motion` row of real-render.mjs: the camera's own tween is left out
// of what the critic reads a dead beat against (#901), and a content tween over
// the same window stays in (the canvas dims a card as the camera leaves it).
// The rule is run on what the events gate makes of a timeline's tweens.
import { test } from "node:test";
import assert from "node:assert/strict";
import { sceneEvents } from "../../skills/explainer-video/scripts/gates/events.mjs";
import { cameraLeftOut } from "../../skills/explainer-video/maintainer/real-render-motion.mjs";

const scenes = [{ id: "s", start: 10 }];
const left = (raw) => cameraLeftOut(raw.s, sceneEvents(raw, scenes).moves.s);

test("a push-in's tween is left out, so a still stretch under it reads as a dead beat", () => {
  const raw = { s: { camera: [[0, 6]], tweens: [[0, 6]] } };
  assert.equal(left(raw), true);
});

test("a canvas travel's tween is left out while the card it dims, over the same window, stays", () => {
  const raw = {
    s: {
      camera: [[2, 3]],
      tweens: [
        [2, 3],
        [2, 3],
        [2, 3],
      ],
    },
  };
  assert.equal(left(raw), true);
});

test("a camera tween that stays in the list is refused", () => {
  const raw = { s: { camera: [[0, 6]], tweens: [[0, 6]] } };
  const { moves } = sceneEvents(raw, scenes);
  const stays = { ...moves.s, tweens: [[10, 16]] };
  assert.equal(cameraLeftOut(raw.s, stays), false);
});

test("a content tween dropped along with the camera's is refused", () => {
  const raw = {
    s: {
      camera: [[2, 3]],
      tweens: [
        [2, 3],
        [2, 3],
      ],
    },
  };
  const { moves } = sceneEvents(raw, scenes);
  assert.equal(cameraLeftOut(raw.s, { ...moves.s, tweens: [] }), false);
});
