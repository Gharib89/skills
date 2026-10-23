// Maintainer only: which of FIXTURE's scenes the rows of real-render.mjs look
// at. Each list comes from the fixture's scenes, so a scene added there is
// covered with no other edit (#937).
import { FPS } from "../scripts/render/compose.mjs";

// The settled moment a saved frame is taken: 3 s into the scene, or its last
// frame when the scene is shorter.
const SETTLED = 3.0;

// The video seconds of each scene's saved frame, `scenes` the composed
// timeline's (`id`, `start`, `duration`).
export const savedFrames = (scenes) =>
  scenes.map(({ id, start, duration }) => ({
    id,
    t: +(start + Math.min(SETTLED, duration - 1 / FPS)).toFixed(3),
  }));

// The scenes the layout gate judges on the real backend: all of them.
export const layoutIds = (fixture) => fixture.map((p) => p.scene.id);

// The scenes whose numbers count up as they are said: stats and charts.
export const countingIds = (fixture) =>
  fixture
    .map((p) => p.scene)
    .filter((s) => ["stat", "chart"].includes(s.visual.component))
    .map((s) => s.id);
