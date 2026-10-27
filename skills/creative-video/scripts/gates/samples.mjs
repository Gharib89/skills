// The three stills the gates judge a scene on: 0.3 s in, the middle, and the
// last frame.
import { FPS, frames } from "../render/grid.mjs";

// A whole frame's time, written to 3 places and rounded up: a seek that floors
// to a frame must still land on it, which a time rounded down does not.
export const ceil3 = (t) => Math.max(0, Math.ceil(t * 1000 - 1e-6)) / 1000;

// `{ in, key, out }` in video seconds for a timeline scene `{ start, duration }`,
// each on a frame of the scene and never before its start. A scene shorter than
// 0.6 s has no room to settle, so its in still is its middle.
export function sampleTimes({ start, duration }) {
  const n = frames(duration);
  const at = (k) => ceil3(start + k / FPS);
  const key = at(Math.floor(n / 2));
  return {
    in: duration < 0.6 ? key : at(Math.round(0.3 * FPS)),
    key,
    out: at(n - 1),
  };
}
