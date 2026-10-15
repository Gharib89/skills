// Word timing from a CTC model's frame logits (ADR 0016): the narration's words
// are force-aligned with a Viterbi pass, and a greedy decode of the same frames
// is the transcript voice QC reads. The model itself sits behind the backend
// switch; everything here is plain JS over its output.

// wav2vec2-style models read 16 kHz mono and emit one frame per 320 samples.
const SAMPLE_RATE = 16000;
const HOP = 320;
export const FRAME = HOP / SAMPLE_RATE;

// Windowed-sinc resampling, so a 24 kHz render reaches the model without the
// aliasing linear interpolation would fold into its speech band.
function resample(x, from, to = SAMPLE_RATE) {
  if (from === to) return x;
  const ratio = to / from;
  const fc = Math.min(1, ratio);
  const half = Math.ceil(16 / fc);
  const out = new Float32Array(Math.floor(x.length * ratio));
  for (let n = 0; n < out.length; n++) {
    const t = n / ratio;
    const k0 = Math.max(0, Math.ceil(t - half));
    const k1 = Math.min(x.length - 1, Math.floor(t + half));
    let sum = 0;
    for (let k = k0; k <= k1; k++) {
      const d = t - k;
      const s = d === 0 ? 1 : Math.sin(Math.PI * fc * d) / (Math.PI * fc * d);
      const w = 0.5 + 0.5 * Math.cos((Math.PI * d) / half);
      sum += x[k] * s * w;
    }
    out[n] = sum * fc;
  }
  return out;
}

// Log-probabilities per frame for a whole narration. The model sees 30 s
// windows with 1 s of context each side, since self-attention over minutes of
// audio costs memory quadratic in its length; the windows' frames line up
// because every offset is a whole number of hops.
const WINDOW = 1500 * HOP;
const MARGIN = 50 * HOP;
async function logProbs(x, logits) {
  const parts = [];
  let classes = 0;
  for (let s0 = 0; s0 < x.length; s0 += WINDOW) {
    const a = Math.max(0, s0 - MARGIN);
    const b = Math.min(x.length, s0 + WINDOW + MARGIN);
    const r = await logits(x.subarray(a, b));
    classes = r.classes;
    const skip = (s0 - a) / HOP;
    const keep = Math.min(WINDOW / HOP, r.frames - skip);
    if (keep > 0)
      parts.push(r.data.subarray(skip * classes, (skip + keep) * classes));
  }
  const frames = parts.reduce((n, p) => n + p.length, 0) / classes;
  const lp = new Float32Array(frames * classes);
  let o = 0;
  for (const p of parts) {
    for (let i = 0; i < p.length; i += classes) {
      let m = -Infinity;
      for (let c = 0; c < classes; c++) m = Math.max(m, p[i + c]);
      let z = 0;
      for (let c = 0; c < classes; c++) z += Math.exp(p[i + c] - m);
      const lz = m + Math.log(z);
      for (let c = 0; c < classes; c++) lp[o + c] = p[i + c] - lz;
      o += classes;
    }
  }
  return { lp, frames, classes };
}

// The vocabulary's ids for one word: upper case, letters and apostrophes only.
const spell = (word, vocab) =>
  [...word.toUpperCase()]
    .filter((ch) => /[A-Z']/.test(ch) && ch in vocab)
    .map((ch) => vocab[ch]);

// Start and end in seconds for every word, in order. A word with nothing the
// model can spell (a number, a symbol) takes the gap between its neighbours.
function forceAlign({ lp, frames, classes }, words, vocab) {
  const blank = vocab["<pad>"];
  const sep = vocab["|"];
  const tgt = [];
  const owner = [];
  words.forEach((w, i) => {
    const ids = spell(w, vocab);
    if (!ids.length) return;
    if (tgt.length) {
      tgt.push(sep);
      owner.push(-1);
    }
    for (const id of ids) {
      tgt.push(id);
      owner.push(i);
    }
  });
  const S = 2 * tgt.length + 1;
  const ext = Int32Array.from({ length: S }, (_, s) =>
    s % 2 ? tgt[(s - 1) >> 1] : blank,
  );
  if (frames < tgt.length)
    throw new Error(
      `audio too short to align: ${frames} frames for ${tgt.length} letters`,
    );
  // Two rolling rows of scores and one byte of backpointer per cell.
  const NEG = -1e30;
  let prev = new Float64Array(S).fill(NEG);
  let cur = new Float64Array(S);
  const bp = new Uint8Array(frames * S);
  prev[0] = lp[ext[0]];
  if (S > 1) prev[1] = lp[ext[1]];
  for (let t = 1; t < frames; t++) {
    cur.fill(NEG);
    const lo = Math.max(0, S - 2 * (frames - t));
    const hi = Math.min(S, 2 * t + 2);
    for (let s = lo; s < hi; s++) {
      let best = prev[s];
      let k = 0;
      if (s > 0 && prev[s - 1] > best) {
        best = prev[s - 1];
        k = 1;
      }
      if (
        s > 1 &&
        ext[s] !== blank &&
        ext[s] !== ext[s - 2] &&
        prev[s - 2] > best
      ) {
        best = prev[s - 2];
        k = 2;
      }
      cur[s] = best + lp[t * classes + ext[s]];
      bp[t * S + s] = k;
    }
    [prev, cur] = [cur, prev];
  }
  let s = S > 1 && prev[S - 2] > prev[S - 1] ? S - 2 : S - 1;
  const first = new Array(words.length).fill(-1);
  const last = new Array(words.length).fill(-1);
  for (let t = frames - 1; t >= 0; t--) {
    if (s % 2) {
      const w = owner[(s - 1) >> 1];
      if (w >= 0) {
        first[w] = t;
        if (last[w] < 0) last[w] = t;
      }
    }
    s -= bp[t * S + s];
  }
  const out = words.map((text, i) => ({
    text,
    start: first[i] < 0 ? null : +(first[i] * FRAME).toFixed(3),
    end: last[i] < 0 ? null : +((last[i] + 1) * FRAME).toFixed(3),
  }));
  out.forEach((w, i) => {
    if (w.start !== null) return;
    const before = out.slice(0, i).findLast((o) => o.end !== null);
    const after = out.slice(i + 1).find((o) => o.start !== null);
    w.start = before ? before.end : 0;
    w.end = after ? after.start : +(frames * FRAME).toFixed(3);
  });
  return out;
}

// Time `words` in audio at any sample rate with the backend's CTC model `ctc`:
// the frames' log-probabilities, which `transcribe` reads, and each word's
// start and end in seconds.
export async function align(samples, sampleRate, words, ctc) {
  const em = await logProbs(resample(samples, sampleRate), ctc.logits);
  return { em, words: forceAlign(em, words, ctc.vocab) };
}

// The model's own reading of frames [from, to): best class per frame, repeats
// merged, blanks dropped, the separator read as a space.
export function transcribe({ lp, classes }, vocab, from, to) {
  const chars = Object.fromEntries(
    Object.entries(vocab).map(([k, v]) => [v, k]),
  );
  const blank = vocab["<pad>"];
  let out = "";
  let last = -1;
  for (let t = from; t < to; t++) {
    let best = 0;
    for (let c = 1; c < classes; c++)
      if (lp[t * classes + c] > lp[t * classes + best]) best = c;
    if (best !== last && best !== blank)
      out +=
        chars[best] === "|" ? " " : chars[best].length === 1 ? chars[best] : "";
    last = best;
  }
  return out.replace(/\s+/g, " ").trim().toLowerCase();
}
