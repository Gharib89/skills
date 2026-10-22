// Maintainer only: the rule of real-render.mjs's `critic motion` row that the
// camera's own tween is left out of what a dead beat is read against. `raw` is
// backend.events' answer (a scene's own seconds), `moves` sceneEvents' (video
// seconds). Per camera window exactly one tween is left out: the camera's. A
// content tween over the same window (the canvas dims a card as the camera
// leaves it) stays, so it is one, not none.
const same = ([a, b], [x, y]) =>
  Math.abs(a - x) < 1e-3 && Math.abs(b - y) < 1e-3;

export const cameraLeftOut = (raw, moves) =>
  raw.camera.every(
    (c, i) =>
      raw.tweens.filter((t) => same(t, c)).length -
        moves.tweens.filter((t) => same(t, moves.camera[i])).length ===
      1,
  );
