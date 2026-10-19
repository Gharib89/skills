// What moves in a scene, read off the encoded video's content band: the one
// helper the determinism gate and the critic's motion strip both take their
// frame from. Pure over `diffs`, the mean absolute difference between each
// frame and the one before it (backend.bandMotion), where diffs[k] compares
// frame first+k+1 with frame first+k, so a scene's own first frame, which
// follows another scene, is never the peak.

// A mean difference on the 0 to 255 grey scale at or under this is no motion:
// an encode's noise floor is never exactly zero.
export const STILL = 0.5;
// A stretch of the band this long with nothing moving is a dead beat.
export const STILL_SECONDS = 1.5;
// The strip's tiles, and how many sit before the peak frame.
export const STRIP_FRAMES = 12;
export const STRIP_LEAD = 5;

// A scene owns the frames from the first at or after its start to the last
// before its end, so one starting between frames (28.25 s at 30 fps) never
// shows the next scene's first frame as its last: `first` is the first one's
// index into the video, `n` how many it owns.
export function sceneFrames({ start, duration, fps }) {
  const at = (t) => Math.ceil(t * fps - 1e-6);
  const first = at(start);
  return { first, n: at(start + duration) - first };
}

// The time to seek to frame `f`, rounded up to 3 places. Rounded to nearest, a
// time can sit before its frame (frame 283 is 9.43333 s, and 9.433 seeks to
// frame 282).
export const frameTime = (f, fps) =>
  (Math.ceil((f / fps) * 1000 - 1e-6) + 0) / 1000;

// A scene's sample times: every 15 frames from its first and at its last.
export function sampleTimes({ start, duration, fps }) {
  const first = Math.round(start * fps);
  const last = first + Math.round(duration * fps) - 1;
  const times = [];
  for (let f = first; f < last; f += 15) times.push(frameTime(f, fps));
  times.push(frameTime(last, fps));
  return times;
}

export function meanDiff(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += Math.abs(a[i] - b[i]);
  return sum / a.length;
}

// The frame with the largest difference from the frame before it, the earliest
// on a tie; a scene whose largest difference is under STILL is still and gives
// its middle frame.
export function peak(diffs, first, fps) {
  let at = 0;
  diffs.forEach((d, k) => {
    if (d > diffs[at]) at = k;
  });
  const still = !(diffs[at] > STILL);
  const frame = still
    ? first + Math.floor((diffs.length + 1) / 2)
    : first + at + 1;
  return { still, frame, t: frame / fps, diff: diffs[at] ?? 0 };
}

// Each run of unchanged frames lasting STILL_SECONDS or more, as video seconds.
export function stillStretches(diffs, first, fps) {
  const out = [];
  const close = (from, to) => {
    if (to - from >= STILL_SECONDS * fps - 1e-6)
      out.push({
        start: +((first + from) / fps).toFixed(3),
        end: +((first + to) / fps).toFixed(3),
      });
  };
  let from = null;
  diffs.forEach((d, k) => {
    if (d <= STILL) from ??= k;
    else if (from !== null) {
      close(from, k);
      from = null;
    }
  });
  if (from !== null) close(from, diffs.length);
  return out;
}

// The strip's first frame: STRIP_LEAD before the peak, inside the scene's `n`
// frames from `first`.
export const stripStart = (peakFrame, first, n) =>
  Math.max(first, Math.min(peakFrame - STRIP_LEAD, first + n - STRIP_FRAMES));

// The strip's last frame: STRIP_FRAMES on from its first, or the scene's last
// when the scene owns fewer frames than a strip holds.
export const stripEnd = (from, first, n) =>
  Math.min(from + STRIP_FRAMES - 1, first + n - 1);
