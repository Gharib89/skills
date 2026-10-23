// Maintainer only: the product's determinism gate (scripts/gates/scene.mjs) run
// by real-render.mjs on the real backend, as gates.mjs runs it: each scene's
// peak-motion frame, read off the encoded video, rendered twice in two
// browsers and compared as decoded pixels, from the scene's section
// composition on its own clock in a video in sections.
import path from "node:path";
import { sceneEvents } from "../scripts/gates/events.mjs";
import {
  motionAndDeterminism,
  renderedDifferently,
} from "../scripts/gates/scene.mjs";
import { grammar } from "../scripts/lib/style.mjs";
import { drawsWebgl } from "../scripts/lib/visuals.mjs";
import { contentBox } from "../scripts/render/compose.mjs";

// The gate over every scene of `timeline` (the composed scenes) in `mp4`, the
// frames of `comp` seeked into `<run>/.cache/gates/frames/`. `scenes` are the
// scripts', `raw` is `backend.events(comp)`, `section(id)` the scene's section
// (`{ dir, base }`) or null.
// Returns the gate's plan: `{ sc, found }` per scene.
export async function determinismGate({
  scenes,
  timeline,
  run,
  mp4,
  comp,
  raw,
  section = () => null,
  backend,
  env,
  profile,
}) {
  const { moves, seams } = sceneEvents(raw, timeline);
  const plan = [];
  for (const sc of timeline) {
    const p = { sc, file: `${sc.id}.json`, found: {} };
    await motionAndDeterminism(p, {
      run,
      mp4: path.relative(run, mp4),
      comp,
      section: section(sc.id),
      env,
      backend,
      orFail: (call) => call(),
      seams,
      tweens: moves[sc.id].tweens,
      band: contentBox(grammar(profile).layout),
      software: drawsWebgl(scenes.filter((s) => s.id === sc.id)),
    });
    plan.push(p);
  }
  return plan;
}

// The gate's row: its findings, or the count of scenes judged.
export const gateRow = (name, plan, check) => {
  const found = renderedDifferently(plan);
  check(
    name,
    found.length === 0,
    `${found.length} of ${plan.length} scene(s) differ between two renders${found.length ? `, first: ${found[0]}` : ""}`,
  );
};
