// What moves in a scene, read off the encoded video's content band: the one
// helper the determinism gate and the critic's motion strip both take their
// frame from. Pure over `diffs`, the mean absolute difference between each
// frame and the one before it (backend.bandMotion), where diffs[k] compares
// frame first+k+1 with frame first+k, so a scene's own first frame, which
// follows another scene, is never the peak.

// A mean difference on the 0 to 255 grey scale at or under this is no motion:
// an encode's noise floor is never exactly zero.
export const STILL = 0.5;
// A stretch of the scene this long with no tween running is a dead beat.
export const DEAD_BEAT_SECONDS = 1.5;
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

// A scene's sample times: every 15 frames from its first (the 0.5 s grid at 30
// fps), the frame each of `events` (video seconds: tween ends, camera and seam
// edges) first shows in, and its last frame, one sample per whole frame.
export function sampleTimes({ start, duration, fps, events = [] }) {
  const first = Math.round(start * fps);
  const last = first + Math.round(duration * fps) - 1;
  const frames = new Set([last]);
  for (let f = first; f < last; f += 15) frames.add(f);
  for (const e of events) {
    const f = Math.ceil(e * fps - 1e-6);
    if (f >= first && f <= last) frames.add(f);
  }
  return [...frames].sort((a, b) => a - b).map((f) => frameTime(f, fps));
}

// The sample a scene is fullest at: the most readable words at once, the latest
// on a tie. `samples` is [{ t, words }] in time order; a scene with no readable
// word in any sample is fullest at its last.
export function fullest(samples) {
  let best = null;
  for (const s of samples)
    if (s.words > 0 && (!best || s.words >= best.words)) best = s;
  return (best ?? samples.at(-1)).t;
}

export function meanDiff(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += Math.abs(a[i] - b[i]);
  return sum / a.length;
}

// Whether frame `f` shows inside one of `windows`, [from, to) in video seconds.
const inWindows = (f, fps, windows) =>
  windows.some(([a, b]) => f / fps >= a && f / fps < b);

// The frame with the largest difference from the frame before it, the earliest
// on a tie; a scene whose largest difference is under STILL is still and gives
// its middle frame. Frames inside a seam window (`seams`, video seconds as
// [from, to)) are not candidates: the peak is the scene's own motion, and a
// still scene's frame is the allowed one nearest its middle.
export function peak(diffs, first, fps, seams = []) {
  const inSeam = (f) => inWindows(f, fps, seams);
  const ks = diffs.map((_, k) => k).filter((k) => !inSeam(first + k + 1));
  // A seam over every frame after the first leaves the first frame: take it,
  // and only a scene wholly inside a seam is judged unfiltered.
  if (!ks.length && diffs.length) {
    const p = peak(diffs, first, fps);
    return inSeam(first) ? p : { ...p, frame: first, t: first / fps };
  }
  let at = ks[0] ?? 0;
  for (const k of ks) if (diffs[k] > diffs[at]) at = k;
  const still = !(diffs[at] > STILL);
  const middle = Math.floor((diffs.length + 1) / 2) - 1;
  const near = ks.reduce(
    (best, k) => (Math.abs(k - middle) < Math.abs(best - middle) ? k : best),
    ks[0] ?? middle,
  );
  const frame = first + (still ? near : at) + 1;
  return { still, frame, t: frame / fps, diff: diffs[at] ?? 0 };
}

// Each stretch of DEAD_BEAT_SECONDS or more of the scene in which no tween runs,
// as video seconds: `windows` is [from, to] of every tween that moves content
// (the camera's push-in and the page's texture are drift, so they are left
// out). Read off the timeline: pixel difference would count the push-in and
// the grain as motion.
export function deadBeats({ start, duration }, windows) {
  const end = start + duration;
  const out = [];
  let at = start;
  const close = (to) => {
    if (to - at >= DEAD_BEAT_SECONDS - 1e-6)
      out.push({ start: +at.toFixed(3), end: +to.toFixed(3) });
  };
  for (const [a, b] of [...windows].sort((x, y) => x[0] - y[0])) {
    if (a >= end) break;
    if (a > at) close(a);
    at = Math.max(at, b);
  }
  if (at < end) close(end);
  return out;
}

// The strip's first frame: STRIP_LEAD before the peak, inside the scene's `n`
// frames from `first`, moved to the nearest start (the earlier of two) whose
// 12 frames all sit outside `seams`. Where no start does, the unmoved one.
export function stripStart(peakFrame, first, n, fps, seams = []) {
  const last = Math.max(first, first + n - STRIP_FRAMES);
  const want = Math.max(first, Math.min(peakFrame - STRIP_LEAD, last));
  const clear = (s) =>
    Array.from({ length: STRIP_FRAMES }, (_, k) => s + k).every(
      (f) => !inWindows(f, fps, seams),
    );
  let best = null;
  for (let s = first; s <= last; s++)
    if (
      clear(s) &&
      (best === null || Math.abs(s - want) < Math.abs(best - want))
    )
      best = s;
  return best ?? want;
}

// The first frame of a seam's strip: its window's frames in the middle of the
// strip's STRIP_FRAMES, so the move is seen before, through and after.
export function seamStripStart([from, to], fps) {
  const at = (t) => Math.ceil(t * fps - 1e-6);
  const lead = Math.max(
    0,
    Math.floor((STRIP_FRAMES - (at(to) - at(from))) / 2),
  );
  return Math.max(0, at(from) - lead);
}

// The strip's last frame: STRIP_FRAMES on from its first, or the scene's last
// when the scene owns fewer frames than a strip holds.
export const stripEnd = (from, first, n) =>
  Math.min(from + STRIP_FRAMES - 1, first + n - 1);
