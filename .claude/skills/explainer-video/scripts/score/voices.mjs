// The score's synth voices: every sound generated here, no samples. Ported
// from MotionCraft's engine (github.com/ahmdd4vd/MotionCraft, MIT, notice in
// LICENSE-motioncraft), trimmed to what the score uses.
import {
  SR,
  adsr,
  biquadCoefs,
  biquadMono,
  filt,
  fromMono,
  midiHz,
  rand,
  randn,
  stereo,
} from "./dsp.mjs";

const N = (d) => Math.max(1, Math.round(d * SR));

export function norm(b, to = 1) {
  let p = 0;
  for (let i = 0; i < b.L.length; i++)
    p = Math.max(p, Math.abs(b.L[i]), Math.abs(b.R[i]));
  const g = to / (p + 1e-9);
  for (let i = 0; i < b.L.length; i++) {
    b.L[i] *= g;
    b.R[i] *= g;
  }
  return b;
}

// FM electric piano.
export function epNote(midi, dur, vel = 0.8, bright = 1) {
  const n = N(dur);
  const f = midiHz(midi);
  const e = adsr(n, 0.002, 0.05, 1, 0.08);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const mod =
      Math.sin(2 * Math.PI * f * t) * (1.1 * bright * Math.exp(-t * 6) + 0.3) +
      Math.sin(2 * Math.PI * f * 7 * t) * 0.12 * bright * Math.exp(-t * 25);
    x[i] =
      Math.sin(2 * Math.PI * f * t + mod) * Math.exp(-t * 2.2) * vel * e[i];
  }
  return fromMono(x);
}

export function supersaw(
  midis,
  dur,
  { bright = 1600, env = [0.4, 0.3, 0.8, 0.5], spread = 0.007 } = {},
) {
  const voices = 3;
  const n = N(dur);
  const L = new Float32Array(n);
  const R = new Float32Array(n);
  for (const m of midis) {
    const f = midiHz(m);
    for (let v = 0; v < voices; v++) {
      // Three voices: detuned down, centre and up, panned left, centre, right.
      const d = spread * (v - 1);
      const p = v - 1;
      const ph = rand();
      for (let i = 0; i < n; i++) {
        const s = 2 * (((f * (1 + d) * i) / SR + ph) % 1) - 1;
        L[i] += (s * (1 - p)) / 2;
        R[i] += (s * (1 + p)) / 2;
      }
    }
  }
  const k = 2.2 / (midis.length * voices);
  const b = filt(
    filt({ L, R }, "lp", bright, 0.707),
    "lp",
    bright * 1.3,
    0.707,
  );
  const e = adsr(n, ...env);
  for (let i = 0; i < n; i++) {
    b.L[i] *= e[i] * k;
    b.R[i] *= e[i] * k;
  }
  return b;
}

export function roundBass(freq, dur) {
  const n = N(dur);
  const e = adsr(n, 0.006, 0.15, 0.75, 0.06);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const w = 2 * Math.PI * freq * (i / SR);
    const v = Math.sin(w) + 0.18 * Math.sin(2 * w) + 0.06 * Math.sin(3 * w);
    x[i] = Math.tanh(v * 1.1) * e[i];
  }
  return fromMono(x);
}

export function softKick(dur = 0.35, tone = 52) {
  const n = N(dur);
  const x = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    ph += (2 * Math.PI * (tone + 90 * Math.exp(-t * 45))) / SR;
    x[i] = Math.tanh(
      (Math.sin(ph) * Math.exp(-t * 11) +
        randn() * Math.exp(-t * 1200) * 0.12) *
        1.3,
    );
  }
  return fromMono(x);
}

function noiseBurst(dur, decay, type, f, q) {
  const n = N(dur);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) x[i] = randn() * Math.exp(-(i / SR) * decay);
  return biquadMono(x, biquadCoefs(type, f, q));
}
export function snap() {
  const a = noiseBurst(0.18, 38, "bp", 1900, 1.4);
  const b = noiseBurst(0.18, 60, "hp", 3500, 0.7);
  const x = new Float32Array(a.length);
  for (let i = 0; i < x.length; i++) x[i] = a[i] * 0.8 + b[i] * 0.4;
  return norm(fromMono(x));
}
// Three fast bursts and a tail.
export function clap() {
  const n = N(0.3);
  const x = new Float32Array(n);
  for (const off of [0, 0.011, 0.022]) {
    const o = Math.round(off * SR);
    for (let i = 0; i + o < n; i++)
      x[i + o] += randn() * Math.exp(-(i / SR) * (off < 0.02 ? 180 : 22));
  }
  return norm(fromMono(biquadMono(x, biquadCoefs("bp", 1300, 0.9))));
}
export function hat(open = false) {
  const x = noiseBurst(open ? 0.35 : 0.06, open ? 9 : 70, "hp", 7500, 0.7);
  return norm(fromMono(biquadMono(x, biquadCoefs("peak", 10000, 1, 4))));
}
export function shaker() {
  const n = N(0.09);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    x[i] = randn() * Math.min(1, t * 300) * Math.exp(-t * 45);
  }
  return norm(fromMono(biquadMono(x, biquadCoefs("hp", 5000, 0.8))));
}

export function marimba(midi, dur = 0.8, vel = 0.7) {
  const n = N(dur);
  const f = midiHz(midi);
  const e = adsr(n, 0.001, 0.02, 1, 0.05);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    x[i] =
      (Math.sin(
        2 * Math.PI * f * t +
          0.8 * Math.exp(-t * 30) * Math.sin(2 * Math.PI * f * 4 * t),
      ) *
        Math.exp(-t * 5.5) +
        0.15 * Math.sin(2 * Math.PI * f * 3.99 * t) * Math.exp(-t * 18)) *
      vel *
      e[i];
  }
  return fromMono(x);
}
export function glock(midi, dur = 1.2, vel = 0.6) {
  const n = N(dur);
  const f = midiHz(midi);
  const x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    x[i] =
      (Math.sin(2 * Math.PI * f * t) +
        0.3 * Math.sin(2 * Math.PI * f * 2.01 * t) * Math.exp(-t * 6) +
        0.12 * Math.sin(2 * Math.PI * f * 3.98 * t) * Math.exp(-t * 10)) *
      Math.exp(-t * 3.5) *
      vel *
      Math.min(1, t * 2000);
  }
  return fromMono(x);
}
// Karplus-Strong.
export function pluck(midi, dur = 0.8, bright = 0.5) {
  const n = N(dur);
  const P = Math.max(2, Math.round(SR / midiHz(midi)));
  const buf = new Float32Array(P);
  const x = new Float32Array(n);
  const k = 0.5 + 0.49 * bright;
  for (let i = 0; i < P; i++) buf[i] = rand() * 2 - 1;
  for (let i = 0; i < n; i++) {
    const j = i % P;
    x[i] = buf[j];
    buf[j] = (k * buf[j] + (1 - k) * buf[(j + 1) % P]) * 0.996;
  }
  const e = adsr(n, 0.001, 0.05, 1, 0.03);
  for (let i = 0; i < n; i++) x[i] *= e[i];
  return fromMono(x);
}

export function chime(midis, dur = 1.2, spacing = 0.06) {
  const n = N(dur);
  const out = stereo(n);
  midis.forEach((m, k) => {
    const f = midiHz(m);
    const o = Math.round(k * spacing * SR);
    const p = midis.length > 1 ? -0.3 + (0.6 * k) / (midis.length - 1) : 0;
    const l = Math.cos(((p + 1) * Math.PI) / 4) * Math.SQRT2 * 0.5;
    const r = Math.sin(((p + 1) * Math.PI) / 4) * Math.SQRT2 * 0.5;
    for (let i = 0; i + o < n; i++) {
      const t = i / SR;
      const v =
        (Math.sin(2 * Math.PI * f * t) +
          0.3 * Math.sin(2 * Math.PI * f * 2.01 * t) +
          0.12 * Math.sin(2 * Math.PI * f * 3.98 * t)) *
        Math.exp(-t * 4.5);
      out.L[i + o] += v * l;
      out.R[i + o] += v * r;
    }
  });
  return out;
}
// Band-passed noise swept from f0 to f1, rising or falling in level.
export function noiseSweep(dur, f0, f1, rise = true, q = 1.2) {
  const n = N(dur);
  const L = new Float32Array(n);
  const R = new Float32Array(n);
  const blk = 256;
  for (const X of [L, R]) {
    let x1 = 0,
      x2 = 0,
      y1 = 0,
      y2 = 0;
    for (let s = 0; s < n; s += blk) {
      const [b0, b1, b2, a1, a2] = biquadCoefs(
        "bp",
        f0 * Math.pow(f1 / f0, s / n),
        q,
      );
      for (let i = s; i < Math.min(n, s + blk); i++) {
        const xin = randn();
        const v = b0 * xin + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = xin;
        y2 = y1;
        y1 = v;
        X[i] = v;
      }
    }
  }
  for (let i = 0; i < n; i++) {
    const fr = i / n;
    const e = rise ? fr * fr : Math.pow(1 - fr, 1.5);
    L[i] *= e;
    R[i] *= e;
  }
  return norm({ L, R });
}
export function swell(dur, midis) {
  const b = supersaw(midis, dur, {
    spread: 0.006,
    bright: 1800,
    env: [dur * 0.9, 0.01, 1, dur * 0.08],
  });
  const n = b.L.length;
  for (let i = 0; i < n; i++) {
    const g = (i / n) ** 2;
    b.L[i] *= g;
    b.R[i] *= g;
  }
  return b;
}
