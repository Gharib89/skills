// The reading time gate, read off the probe's frames: a scene's text must stay
// readable long enough to be read.

// A text of at most three words is a label, 0.8 s; a longer one 0.3 s a word and
// 1.2 s at least.
export const readingFloor = (n) => (n <= 3 ? 0.8 : Math.max(1.2, 0.3 * n));

// Probe times are 3-place values.
const EPS = 1e-3;

// A text is readable once it is fully drawn.
export const readable = (e) => e.opacity >= 0.99;

// Findings for scene `id` ending at `end`: `frames` are its probe frames in time
// order, `samples` the times the stills are judged at. Each text readable in a
// sample must have been readable in one unbroken run, from the first probe
// frame of the run to the first frame after it, the scene's end if none, of at
// least its floor. Two short runs never add up.
export function readingFindings({ id, end, frames, samples }) {
  const keyed = frames.map((f) => {
    const seen = new Map();
    return new Map(
      f.texts.map((e) => {
        const n = (seen.get(e.text) ?? 0) + 1;
        seen.set(e.text, n);
        return [`${e.text}#${n}`, e];
      }),
    );
  });
  const out = [];
  const done = new Set();
  for (const s of samples) {
    const at = frames.findIndex((f) => f.t === s);
    for (const [key, e] of keyed[at]) {
      if (!readable(e)) continue;
      const on = (i) => keyed[i]?.get(key) && readable(keyed[i].get(key));
      let from = at;
      while (on(from - 1)) from--;
      let to = at + 1;
      while (on(to)) to++;
      const seconds = (frames[to]?.t ?? end) - frames[from].t;
      const floor = readingFloor(e.words);
      if (seconds + EPS < floor && !done.has(`${key} ${from}`)) {
        done.add(`${key} ${from}`);
        out.push(
          `${s.toFixed(2)} s ${id}: "${e.text}" is readable ${seconds.toFixed(1)} s vs ${floor.toFixed(1)} s to read`,
        );
      }
    }
  }
  return out;
}
