// The gates stage's critic inputs: per scene, a contact sheet, a motion strip,
// a strip of the seam it hands over at and a motion record, cut from the MP4
// into the verdict folder `dir`.
import fs from "node:fs";
import path from "node:path";
import {
  STRIP_FRAMES,
  sceneFrames,
  seamStripStart,
  stripEnd,
  stripStart,
} from "../lib/motion.mjs";
import { FPS } from "../render/compose.mjs";

// The previous sheets folder's scene keys; {} when it has none. A malformed
// file stops the gates, naming it.
export function readPrevKeys(run, sheets, fail) {
  const file = path.join(run, sheets, "keys.json");
  if (!fs.existsSync(file)) return {};
  const bad = (why) =>
    fail(
      `critic keys ${sheets}/keys.json: ${why}; delete it to judge every scene again`,
    );
  let keys;
  try {
    keys = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    bad(e.message);
  }
  if (!keys || typeof keys !== "object" || Array.isArray(keys))
    bad("not an object of scene keys");
  return keys;
}

const r3 = (n) => +n.toFixed(3);

// A scene's verdict stands for what its critic read: its sheet, both strips
// and record, its span in the video (a worst moment must fall inside it), its
// visual, and `criticRead` (the title, every scene's narration, the script's
// cites and their text), and the format. Returns each scene's key; a scene whose key the previous render kept gets
// that render's verdict copied in.
export async function cutSheets({
  run,
  mp4,
  dir,
  plan,
  moves,
  seams,
  backend,
  orFail,
  script,
  criticRead,
  hash,
  format,
  prevSheets,
  prevKeys,
}) {
  const keys = {};
  for (const p of plan) {
    const { sc } = p;
    const png = path.join(run, dir, `${sc.id}.png`);
    if (!fs.existsSync(png))
      await orFail(() =>
        backend.sheet(path.join(run, mp4), png, {
          start: sc.start,
          duration: sc.duration,
          fps: FPS,
          fullest: p.found.fullest,
        }),
      );
    // The motion strip is 12 frames from just before the scene's peak-motion
    // frame, clear of every seam; a still scene has none. The scene's seam
    // strip is its exit seam's window: the one opening at the scene's own end,
    // which runs on into the next scene. The record carries what the tiles of
    // both strips and the scene's dead beats are in video seconds.
    const m = p.found.motion;
    const { first, n } = sceneFrames({ ...sc, fps: FPS });
    const from = stripStart(m.frame, first, n, FPS, seams);
    const window = (moves[sc.id]?.seams ?? []).find(
      ([a]) => a >= sc.start + sc.duration - 1e-3,
    );
    const seamFrom = window && seamStripStart(window, FPS);
    const seamPng = path.join(run, dir, `${sc.id}.seam.png`);
    if (window && !fs.existsSync(seamPng))
      await orFail(() =>
        backend.strip(path.join(run, mp4), seamPng, {
          first: seamFrom,
          fps: FPS,
        }),
      );
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
            seam: window
              ? {
                  first: r3(seamFrom / FPS),
                  last: r3((seamFrom + STRIP_FRAMES - 1) / FPS),
                  window,
                }
              : null,
            dead: m.dead,
          },
          null,
          2,
        ) + "\n",
      );
    keys[sc.id] = hash(
      fs.readFileSync(png),
      m.still ? "" : fs.readFileSync(strip),
      window ? fs.readFileSync(seamPng) : "",
      fs.readFileSync(record),
      [sc.start, sc.duration],
      script.scenes.find((s) => s.id === sc.id).visual,
      criticRead,
      format,
    );
    const verdict = path.join(run, dir, `${sc.id}.json`);
    const prevVerdict =
      prevSheets && path.join(run, prevSheets, `${sc.id}.json`);
    if (
      prevKeys[sc.id] === keys[sc.id] &&
      !fs.existsSync(verdict) &&
      fs.existsSync(prevVerdict)
    )
      fs.copyFileSync(prevVerdict, verdict);
  }
  return keys;
}
