// Maintainer only: which of FIXTURE's scenes the rows of real-render.mjs look
// at. Each list comes from the fixture's scenes, so a scene added there is
// covered with no other edit (#937).
import { frameTime, sceneFrames } from "../scripts/lib/motion.mjs";
import { FPS } from "../scripts/render/compose.mjs";

// The settled moment a saved frame is taken: 3 s into the scene, or its last
// frame when the scene is shorter.
const SETTLED = 3.0;

// The video seconds of each scene's saved frame, `scenes` the composed
// timeline's (`id`, `start`, `duration`). The frame is picked by index among
// the ones the scene owns and timed with `frameTime`, which rounds up: a time
// rounded to nearest can seek the frame before.
export const savedFrames = (scenes) =>
  scenes.map(({ id, start, duration }) => {
    const { first, n } = sceneFrames({ start, duration, fps: FPS });
    return {
      id,
      t: frameTime(first + Math.min(n - 1, SETTLED * FPS), FPS),
    };
  });

// The compositions the layout gate judges on the real backend, which hold every
// scene: a run's page has one reading direction for all its scenes, so the
// fixture's English scenes and its Arabic ones (`dir: "rtl"`) each get a page
// as a run in that language composes it.
export const layoutRuns = (fixture) =>
  ["ltr", "rtl"]
    .map((dir) => ({
      dir,
      part: fixture.filter((p) => (p.dir ?? "ltr") === dir),
    }))
    .filter(({ part }) => part.length);

// The scenes whose numbers count up as they are said: stats and charts.
export const countingIds = (fixture) =>
  fixture
    .map((p) => p.scene)
    .filter((s) => ["stat", "chart"].includes(s.visual.component))
    .map((s) => s.id);
