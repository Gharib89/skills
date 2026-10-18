// The gates stage's critic inputs: per scene, a contact sheet, a motion strip
// and a motion record, cut from the MP4 into the verdict folder `dir`.
import fs from "node:fs";
import path from "node:path";
import { sceneFrames, stripEnd, stripStart } from "../lib/motion.mjs";
import { FPS } from "../render/compose.mjs";

const r3 = (n) => +n.toFixed(3);

export async function cutSheets({ run, mp4, dir, plan, backend, orFail }) {
  for (const p of plan) {
    const { sc } = p;
    const png = path.join(run, dir, `${sc.id}.png`);
    if (!fs.existsSync(png))
      await orFail(() =>
        backend.sheet(path.join(run, mp4), png, {
          start: sc.start,
          duration: sc.duration,
          fps: FPS,
        }),
      );
    // The motion strip is 12 frames from just before the scene's peak-motion
    // frame; a still scene has none. The record carries what the strip's tiles
    // and the scene's dead beats are in video seconds.
    const m = p.found.motion;
    const { first, n } = sceneFrames({ ...sc, fps: FPS });
    const from = stripStart(m.frame, first, n);
    const strip = path.join(run, dir, `${sc.id}.motion.png`);
    if (!m.still && !fs.existsSync(strip))
      await orFail(() =>
        backend.strip(path.join(run, mp4), strip, { first: from, fps: FPS }),
      );
    const record = path.join(run, dir, `${sc.id}.motion.json`);
    if (!fs.existsSync(record))
      fs.writeFileSync(
        record,
        JSON.stringify(
          {
            still: m.still,
            peak: m.still ? null : { frame: m.frame, t: m.t },
            strip: m.still
              ? null
              : {
                  first: r3(from / FPS),
                  last: r3(stripEnd(from, first, n) / FPS),
                },
            stills: m.stills,
          },
          null,
          2,
        ) + "\n",
      );
  }
}
