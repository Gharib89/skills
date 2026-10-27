// The render's frame grid. HyperFrames renders ceil(duration x fps) frames, so
// a time is counted in whole frames and written truncated: a time rounded up
// by a hair would cost a whole extra frame.

// The render's frame rate.
export const FPS = 30;

// Noise a WAV's sample count leaves on a duration that is whole frames.
const NOISE = 1e-4;

// Whole frames a duration of `seconds` takes, rounded up.
export const frames = (seconds) => Math.ceil(seconds * FPS - NOISE);

// The seconds to write for `n` frames, truncated to 6 places: 2 frames rounded
// to 0.066667 reads back as 2.00001 frames and renders as 3. A truncated value
// whose float product with FPS still lands above `n` (8.3 s x 30 is
// 249.00000000000003) steps down one microsecond.
export function written(n) {
  const whole = Math.trunc(n);
  let us = Math.floor((whole / FPS) * 1e6);
  while (Math.ceil((us / 1e6) * FPS) > whole) us--;
  return us / 1e6;
}

// Scenes back to back from the voice stage's durations, the hold added to the
// last, each `{ start, frames }` in frames; `total` is the whole in frames.
export function gridScenes(durations, hold) {
  let at = 0;
  const scenes = durations.map((d, i) => {
    const n = frames(d + (i === durations.length - 1 ? hold : 0));
    const scene = { start: at, frames: n };
    at += n;
    return scene;
  });
  scenes.total = at;
  return scenes;
}

// 16-bit mono PCM `data` followed by the silence that fills `n` frames.
export function padToFrames(data, rate, n) {
  const out = Buffer.alloc(Math.round((n * rate) / FPS) * 2);
  data.copy(out, 0, 0, Math.min(data.length, out.length));
  return out;
}
