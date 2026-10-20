// The reading time video gate, read off the layout probe's samples: each text
// box of a scene is judged on its longest single stretch of being readable
// (fully shown, outside a seam, not carried by the camera) against its words.
// Two short stretches never add up. A kinetic line revealed word by word on its
// own spoken words is read along with the voice, so it is one box judged whole,
// exempt from words per second: it must read whole for ALONG_SECONDS.
import { readable } from "../lib/layout.mjs";

// A text of at most three words is a label, 0.8 s; a longer one 0.3 s a word
// and 1.2 s at least.
export const readingFloor = (n) => (n <= 3 ? 0.8 : Math.max(1.2, 0.3 * n));
export const ALONG_SECONDS = 0.8;
// Probe times are 3-place values and a stretch is a whole number of frames.
const EPS = 1e-3;

// Findings for scene `p.sc`, from the probe's `frames` at `p.times` (video
// seconds, `p.end` the scene's end). A box is a line (the elements sharing a
// `line`, readable only when every one is) or the text of an element, readable
// when any element with that text is. A finding is led by the scene's start,
// as layout's lines are, so the storyboard's gate stop reopens the scene's card.
export function readingFindings(p, frames, moving) {
  const boxes = new Map();
  p.times.forEach((t, i) => {
    const mine = frames
      .find((f) => f.t === t)
      .elements.filter((e) => e.scene === p.sc.id);
    const seen = new Map();
    for (const e of mine) {
      const key = e.line == null ? `text ${e.text}` : `line ${e.line}`;
      if (!seen.has(key)) seen.set(key, []);
      seen.get(key).push(e);
    }
    for (const [key, els] of seen) {
      const box = boxes.get(key) ?? {
        along: false,
        words: 0,
        parts: [],
        read: Array(p.times.length).fill(false),
        full: Array(p.times.length).fill(0),
      };
      boxes.set(key, box);
      box.along = box.along || els.some((e) => e.along);
      if (key.startsWith("line")) {
        if (els.length > box.parts.length) {
          box.parts = els.map((e) => e.text);
          box.words = els.reduce((n, e) => n + e.words, 0);
        }
        box.full[i] = els.filter((e) => readable(e, t, moving)).length;
      } else {
        box.parts = [els[0].text];
        box.words = Math.max(...els.map((e) => e.words));
        box.read[i] = els.some((e) => readable(e, t, moving));
      }
    }
  });
  const out = [];
  for (const [key, box] of boxes) {
    // A line reads when every one of its elements does, at the most it showed.
    const line = key.startsWith("line");
    const read = line ? box.full.map((n) => n >= box.parts.length) : box.read;
    let longest = 0;
    let from = null;
    read.forEach((on, i) => {
      if (on && from === null) from = p.times[i];
      if (from !== null && (!on || i === read.length - 1)) {
        const to = on ? p.end : p.times[i];
        longest = Math.max(longest, to - from);
        from = null;
      }
    });
    const need = box.along ? ALONG_SECONDS : readingFloor(box.words);
    if (longest + EPS < need)
      out.push(
        `${p.sc.start.toFixed(2)} s ${p.sc.id}: "${box.parts.join(" ")}": ${longest.toFixed(1)} s readable${box.along ? " whole" : ""} vs ${need.toFixed(1)} s ${box.along ? "after its last word" : "to read"}`,
      );
  }
  return out;
}
