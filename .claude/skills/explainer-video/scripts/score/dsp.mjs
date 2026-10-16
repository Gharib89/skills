// The score's DSP core, pure Node. Ported from MotionCraft's engine
// (github.com/ahmdd4vd/MotionCraft, MIT, notice in LICENSE-motioncraft),
// trimmed to what the score uses. Stereo buffers are {L, R} Float32Arrays.
import fs from "node:fs";

export const SR = 48000;

let seed = 7;
export function setSeed(s) {
  seed = s >>> 0 || 7;
}
// mulberry32
export function rand() {
  seed |= 0;
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
export const randn = () => {
  let u = 0;
  while (!u) u = rand();
  const v = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};
export const db = (x) => Math.pow(10, x / 20);
export const toDb = (x) => 20 * Math.log10(Math.max(1e-12, x));
export const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);
export const NOTE = { C: 0, D: 2, Eb: 3, F: 5, G: 7, A: 9, Bb: 10 };

export function stereo(n) {
  return { L: new Float32Array(n), R: new Float32Array(n) };
}
export function fromMono(x) {
  return { L: x, R: Float32Array.from(x) };
}
function len(b) {
  return b.L.length;
}
function clone(b) {
  return { L: Float32Array.from(b.L), R: Float32Array.from(b.R) };
}

export function place(buf, x, t, g = 1, panPos = 0) {
  const i0 = Math.round(t * SR);
  const n = len(buf);
  if (i0 >= n) return;
  const l = Math.cos(((panPos + 1) * Math.PI) / 4) * Math.SQRT2;
  const r = Math.sin(((panPos + 1) * Math.PI) / 4) * Math.SQRT2;
  for (let k = Math.max(0, -i0); k < x.L.length && i0 + k < n; k++) {
    buf.L[i0 + k] += x.L[k] * g * l;
    buf.R[i0 + k] += x.R[k] * g * r;
  }
}
export function mixInto(dst, src) {
  const n = Math.min(len(dst), len(src));
  for (let i = 0; i < n; i++) {
    dst.L[i] += src.L[i];
    dst.R[i] += src.R[i];
  }
}
export function gain(b, g) {
  for (let i = 0; i < len(b); i++) {
    b.L[i] *= g;
    b.R[i] *= g;
  }
  return b;
}
export function peak(b) {
  let p = 0;
  for (let i = 0; i < len(b); i++)
    p = Math.max(p, Math.abs(b.L[i]), Math.abs(b.R[i]));
  return p;
}

export function adsr(n, a, d, s, r) {
  const A = Math.max(1, Math.round(a * SR));
  const D = Math.max(1, Math.round(d * SR));
  const Rl = Math.max(1, Math.round(r * SR));
  const H = Math.max(0, n - A - D - Rl);
  const e = new Float32Array(n);
  let i = 0;
  for (let k = 0; k < A && i < n; k++) e[i++] = k / A;
  for (let k = 0; k < D && i < n; k++) e[i++] = 1 + ((s - 1) * k) / D;
  for (let k = 0; k < H && i < n; k++) e[i++] = s;
  for (let k = 0; k < Rl && i < n; k++) e[i++] = s * (1 - k / Rl);
  return e;
}

// Biquads from the RBJ cookbook.
export function biquadCoefs(type, f, q = 0.707, gainDb = 0) {
  f = Math.min(f, SR / 2.2);
  const w = (2 * Math.PI * f) / SR;
  const c = Math.cos(w);
  const al = Math.sin(w) / (2 * q);
  const A = Math.pow(10, gainDb / 40);
  let b0, b1, b2, a0, a1, a2;
  switch (type) {
    case "lp":
      [b0, b1, b2] = [(1 - c) / 2, 1 - c, (1 - c) / 2];
      [a0, a1, a2] = [1 + al, -2 * c, 1 - al];
      break;
    case "hp":
      [b0, b1, b2] = [(1 + c) / 2, -(1 + c), (1 + c) / 2];
      [a0, a1, a2] = [1 + al, -2 * c, 1 - al];
      break;
    case "bp":
      [b0, b1, b2] = [al, 0, -al];
      [a0, a1, a2] = [1 + al, -2 * c, 1 - al];
      break;
    case "peak":
      [b0, b1, b2] = [1 + al * A, -2 * c, 1 - al * A];
      [a0, a1, a2] = [1 + al / A, -2 * c, 1 - al / A];
      break;
    case "lowshelf": {
      const sq = 2 * Math.sqrt(A) * al;
      b0 = A * (A + 1 - (A - 1) * c + sq);
      b1 = 2 * A * (A - 1 - (A + 1) * c);
      b2 = A * (A + 1 - (A - 1) * c - sq);
      a0 = A + 1 + (A - 1) * c + sq;
      a1 = -2 * (A - 1 + (A + 1) * c);
      a2 = A + 1 + (A - 1) * c - sq;
      break;
    }
    default:
      throw new Error(`biquad type ${type}`);
  }
  return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
}
export function biquadMono(x, co) {
  const [b0, b1, b2, a1, a2] = co;
  let x1 = 0,
    x2 = 0,
    y1 = 0,
    y2 = 0;
  const y = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) {
    const v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x[i];
    y2 = y1;
    y1 = v;
    y[i] = v;
  }
  return y;
}
export function filt(b, type, f, q, g) {
  const co = biquadCoefs(type, f, q, g);
  return { L: biquadMono(b.L, co), R: biquadMono(b.R, co) };
}

// Feed-forward compressor, peak detector, stereo linked.
export function compress(b, thrDb, ratio, attMs, relMs) {
  const at = Math.exp(-1 / ((attMs * SR) / 1000));
  const rt = Math.exp(-1 / ((relMs * SR) / 1000));
  let env = 0;
  const out = clone(b);
  for (let i = 0; i < len(b); i++) {
    const lv = Math.max(Math.abs(b.L[i]), Math.abs(b.R[i]));
    env = lv > env ? at * env + (1 - at) * lv : rt * env + (1 - rt) * lv;
    const over = toDb(env) - thrDb;
    const g = db(-(over > 0 ? over * (1 - 1 / ratio) : 0));
    out.L[i] *= g;
    out.R[i] *= g;
  }
  return out;
}

// Freeverb-style reverb, wet only.
const COMBS = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const ALLPASSES = [556, 441, 341, 225];
export function reverb(b, room = 0.5, damp = 0.5, wet = 0.25) {
  const n = len(b);
  const scale = SR / 44100;
  const fb = 0.7 + room * 0.28;
  const out = stereo(n);
  for (const [ch, spread] of [
    ["L", 0],
    ["R", 23],
  ]) {
    const input = b[ch];
    const acc = new Float32Array(n);
    for (const ct of COMBS) {
      const L = Math.round((ct + spread) * scale);
      const buf = new Float32Array(L);
      let idx = 0,
        store = 0;
      for (let i = 0; i < n; i++) {
        const o = buf[idx];
        store = o * (1 - damp) + store * damp;
        buf[idx] = input[i] * 0.015 + store * fb;
        acc[i] += o;
        idx = (idx + 1) % L;
      }
    }
    for (const at of ALLPASSES) {
      const L = Math.round((at + spread) * scale);
      const buf = new Float32Array(L);
      let idx = 0;
      for (let i = 0; i < n; i++) {
        const bo = buf[idx];
        const o = -acc[i] + bo;
        buf[idx] = acc[i] + bo * 0.5;
        acc[i] = o;
        idx = (idx + 1) % L;
      }
    }
    out[ch] = acc;
  }
  return gain(out, wet);
}
export function withReverb(b, room, damp, wet, dry = 1) {
  const o = gain(clone(b), dry);
  mixInto(o, reverb(b, room, damp, wet));
  return o;
}

export function delay(b, timeS, fbk = 0.3, mix = 0.2) {
  const d = Math.round(timeS * SR);
  const n = len(b);
  const o = clone(b);
  for (const ch of ["L", "R"]) {
    const y = new Float32Array(n);
    for (let i = 0; i < n; i++) y[i] = b[ch][i] + (i >= d ? y[i - d] * fbk : 0);
    for (let i = d; i < n; i++) o[ch][i] += y[i - d] * mix;
  }
  return o;
}
export function chorus(b, rate = 0.9, depthMs = 3, mix = 0.35) {
  const n = len(b);
  const o = clone(b);
  const base = 0.012 * SR;
  const dep = (depthMs / 1000) * SR;
  for (const [ch, ph] of [
    ["L", 0],
    ["R", Math.PI / 2],
  ]) {
    const x = b[ch];
    for (let i = 0; i < n; i++) {
      const p = i - (base + dep * Math.sin((2 * Math.PI * rate * i) / SR + ph));
      const k = Math.floor(p);
      const fr = p - k;
      const v = k >= 1 ? x[k] * (1 - fr) + x[k + 1] * fr : 0;
      o[ch][i] = x[i] * (1 - mix) + v * mix;
    }
  }
  return o;
}

export function fadeOut(b, sec) {
  const n = len(b);
  const f = Math.min(n, Math.round(sec * SR));
  for (let i = 0; i < f; i++) {
    const g = 1 - i / f;
    b.L[n - f + i] *= g;
    b.R[n - f + i] *= g;
  }
}

// 24-bit stereo PCM WAV at SR.
export function writeWav(file, b) {
  const n = len(b);
  const data = n * 6;
  const buf = Buffer.alloc(44 + data);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + data, 4);
  buf.write("WAVEfmt ", 8);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 6, 28);
  buf.writeUInt16LE(6, 32);
  buf.writeUInt16LE(24, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(data, 40);
  let o = 44;
  for (let i = 0; i < n; i++)
    for (const v of [b.L[i], b.R[i]]) {
      buf.writeIntLE(Math.round(Math.max(-1, Math.min(1, v)) * 8388607), o, 3);
      o += 3;
    }
  fs.writeFileSync(file, buf);
}
