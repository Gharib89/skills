// The style card's live build: the sample scenes in one composition, each
// 2.4 s back to back with the draft's own seams between them, as the board
// plays a video. `liveBuild` writes it to a scratch folder and returns the
// `live.js` the page loads, and the loop each frame plays: a sample's own scene
// through its exit seam, and a sixth frame across the title-to-diagram seam.
import fs from "node:fs";
import path from "node:path";
import { compositionAssets } from "../lib/tools.mjs";
import { sceneFile, videoPage } from "../render/compose.mjs";
import { frames, written } from "../render/grid.mjs";
import { liveScript } from "../render/live.mjs";
import { seamPlan, slot } from "../render/seams.mjs";

const SECONDS = 2.4;
// What the seam frame shows either side of the seam, in seconds.
const PAD = 0.5;
// The caption sample's words: the first at 0.4 s, one every 0.15 s.
const FIRST = 0.4;
const EVERY = 0.15;
const r6 = (x) => +x.toFixed(6);

export async function liveBuild({ comp, draft, samples, fontRows, backend }) {
  fs.rmSync(comp, { recursive: true, force: true });
  fs.mkdirSync(path.join(comp, "scenes"), { recursive: true });
  const fonts = compositionAssets(fontRows, comp);
  const plan = seamPlan(samples, draft);
  const own = frames(SECONDS);
  const scenes = samples.map((s, i) => ({
    id: s.id,
    start: written(i * own),
    duration: written(own),
    slot: slot(own, plan[i]),
  }));
  const cues = [];
  for (const [i, s] of samples.entries()) {
    const sc = scenes[i];
    const words = s.cue?.split(/\s+/) ?? [];
    if (words.length)
      cues.push({
        start: r6(sc.start + FIRST),
        end: r6(sc.start + FIRST + words.length * EVERY + 0.3),
        tokens: words.map((text, w) => ({
          text,
          start: r6(sc.start + FIRST + w * EVERY),
        })),
      });
    fs.writeFileSync(
      path.join(comp, "scenes", `${s.id}.html`),
      await sceneFile(
        s,
        {
          duration: sc.duration,
          slot: sc.slot,
          sentences: [FIRST],
          words: [],
        },
        draft,
        { backend, dir: s.dir, seam: plan[i] },
      ),
    );
  }
  fs.writeFileSync(
    path.join(comp, "index.html"),
    videoPage({
      title: draft.label ?? draft.name,
      profile: draft,
      fonts,
      scenes,
      cues,
      total: written(samples.length * own),
    }),
  );
  const loops = Object.fromEntries(
    scenes.map((sc) => [sc.id, [sc.start, r6(sc.start + sc.slot)]]),
  );
  const seam = scenes[1].start;
  loops.seam = [r6(seam - PAD), r6(seam + (plan[0].out?.duration ?? 0) + PAD)];
  return { script: liveScript(comp), loops };
}
