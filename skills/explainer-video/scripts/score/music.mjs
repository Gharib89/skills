// The music engine: a calm-with-punch instrumental arranged to the scenes,
// one section per scene starting at the scene's own start. Ported from
// MotionCraft's engine (github.com/ahmdd4vd/MotionCraft, MIT, notice in
// LICENSE-motioncraft); the port places sections at absolute times rather
// than back to back in whole bars, so the arrangement turns on every cut.
import * as D from "./dsp.mjs";
import * as V from "./voices.mjs";

const { SR } = D;

// [semitones from the key, chord quality] per bar.
const PROGRESSIONS = {
  "warm-lift": [
    [0, "maj7"],
    [4, "m7"],
    [5, "maj7"],
    [7, "sus"],
  ],
  dreamy: [
    [9, "m7"],
    [5, "maj7"],
    [0, "add9"],
    [7, "sus"],
  ],
  "soft-pop": [
    [0, "add9"],
    [7, "sus"],
    [9, "m7"],
    [5, "maj7"],
  ],
  hopeful: [
    [5, "maj7"],
    [7, "sus"],
    [9, "m7"],
    [0, "add9"],
  ],
  "lofi-desk": [
    [2, "m9"],
    [7, "9"],
    [0, "maj9"],
    [9, "m7"],
  ],
  "minimal-dark": [
    [9, "m9"],
    [5, "maj7"],
    [2, "m7"],
    [4, "m7"],
  ],
  "tech-bright": [
    [0, "add9"],
    [9, "m7"],
    [5, "add9"],
    [7, "sus"],
  ],
};
const Q = {
  maj7: [0, 4, 7, 11],
  m7: [0, 3, 7, 10],
  sus: [0, 5, 7, 10],
  9: [0, 4, 7, 10, 14],
  add9: [0, 4, 7, 14],
  m9: [0, 3, 7, 10, 14],
  maj9: [0, 4, 7, 11, 14],
};

export const PRESETS = {
  "calm-punch": {
    bpm: 102,
    key: "F",
    progression: "warm-lift",
    swing: 0.57,
    lead: "marimba",
    comp: "syncopated",
    drums: "soft",
    brightness: 1.0,
    levels: {},
  },
  dreamy: {
    bpm: 93,
    key: "D",
    progression: "dreamy",
    swing: 0.62,
    lead: "marimba",
    comp: "syncopated",
    drums: "soft",
    brightness: 0.85,
    levels: { bell: -9, keys: -6, pad: -9, hats: -7 },
  },
  "warm-major": {
    bpm: 98,
    key: "G",
    progression: "soft-pop",
    swing: 0.55,
    lead: "glock",
    comp: "offbeat",
    drums: "soft",
    brightness: 1.0,
    levels: {},
  },
  "lofi-desk": {
    bpm: 84,
    key: "Eb",
    progression: "lofi-desk",
    swing: 0.64,
    lead: "pluck",
    comp: "lazy",
    drums: "lofi",
    brightness: 0.7,
    levels: { hats: -9 },
  },
  "tech-bright": {
    bpm: 112,
    key: "A",
    progression: "tech-bright",
    swing: 0.52,
    lead: "pluck",
    comp: "eighths",
    drums: "tight",
    brightness: 1.15,
    levels: {},
  },
  "dark-minimal": {
    bpm: 90,
    key: "C",
    progression: "minimal-dark",
    swing: 0.54,
    lead: "glock",
    comp: "sustain",
    drums: "soft",
    brightness: 0.75,
    levels: { bell: -10 },
  },
  "cinematic-soft": {
    bpm: 88,
    key: "Bb",
    progression: "hopeful",
    swing: 0.5,
    lead: "glock",
    comp: "sustain",
    drums: "sparse",
    brightness: 0.9,
    levels: { pad: -7 },
  },
};

// [sixteenth, length in sixteenths] per hit.
const COMP = {
  syncopated: [
    [0, 3],
    [3, 2],
    [6, 3],
    [10, 2],
    [12, 3],
  ],
  offbeat: [
    [2, 2],
    [6, 2],
    [10, 2],
    [14, 2],
  ],
  lazy: [
    [0, 5],
    [7, 3],
    [11, 5],
  ],
  eighths: [
    [0, 2],
    [2, 2],
    [4, 2],
    [6, 2],
    [8, 2],
    [10, 2],
    [12, 2],
    [14, 2],
  ],
  sustain: [[0, 16]],
};
const DRUMS = {
  soft: {
    kick: [0, 8],
    kickMain: [7],
    kickOdd: [10],
    hats: 2,
    snare: true,
    shaker: true,
  },
  tight: {
    kick: [0, 8],
    kickMain: [6, 11],
    kickOdd: [10],
    hats: 1,
    snare: true,
    shaker: false,
  },
  lofi: {
    kick: [0, 7],
    kickMain: [10],
    kickOdd: [],
    hats: 2,
    snare: true,
    shaker: false,
  },
  sparse: {
    kick: [0],
    kickMain: [8],
    kickOdd: [],
    hats: 4,
    snare: false,
    shaker: false,
  },
};
// Section types: intro, groove, main, breakdown, outro.
const SECTION_GAIN = { intro: 1.5, breakdown: -1.0 };

// `sections`: [{type, start}] in time order, the first at 0; each runs to the
// next one's start, the last to `total` seconds. A section's last bar is cut
// at its end: no note starts past it.
export function renderMusic({ sections, total, preset, seed }) {
  const s = PRESETS[preset];
  const chords = PROGRESSIONS[s.progression];
  D.setSeed(seed);
  const key = D.NOTE[s.key];
  const beat = 60 / s.bpm;
  const bar = beat * 4;
  const six = beat / 4;
  const n = Math.round(total * SR);
  // Each track is a list of [voice, t, gain, pan] notes, built into a
  // full-length buffer only when its chain runs, so one track is live at a
  // time rather than eight (a 300 s stereo track is 115 MB). A note's voice is
  // made where the arrangement reaches it, to move the generator on, then
  // dropped; `make` and the generator state it started from make it again.
  const T = Object.fromEntries(
    ["kick", "bass", "snare", "hats", "keys", "pad", "bell", "fx"].map((k) => [
      k,
      [],
    ]),
  );
  const voice = (make) => {
    const state = D.seedState();
    make();
    return { make, state };
  };
  const build = (notes) => {
    const x = D.stereo(n);
    for (const [v, t, g, pan] of notes) {
      if (v.make) D.restoreSeed(v.state);
      D.place(x, v.make ? v.make() : v, t, g, pan);
    }
    return x;
  };
  const swingT = (st) =>
    Math.floor(st / 2) * (beat / 2) + (st % 2) * (beat / 2) * s.swing;
  const K = {
    snap: V.snap(),
    clap: V.clap(),
    hat: V.hat(),
    shaker: V.shaker(),
  };
  const dr = DRUMS[s.drums];
  const kicks = [];
  let bars = 0;
  sections.forEach((sec, si) => {
    const name = sec.type;
    const end = sections[si + 1]?.start ?? total;
    const count = Math.max(1, Math.ceil((end - sec.start) / bar - 1e-6));
    const put = (buf, x, t, g, pan) => {
      if (t < end) buf.push([x, t, g, pan]);
    };
    for (let b = 0; b < count; b++) {
      const t0 = sec.start + b * bar;
      const [r, q] = chords[(bars + b) % chords.length];
      const pc = (key + r) % 12;
      const voic = Q[q].map((iv) =>
        48 + pc + iv >= 53 ? 48 + pc + iv : 60 + pc + iv,
      );
      const bassM = pc < 8 ? 36 + pc : 24 + pc;
      const drums = name === "groove" || name === "main";
      const last = b === count - 1;
      const pat =
        name === "outro"
          ? [[0, 16]]
          : name === "intro"
            ? [
                [0, 6],
                [6, 4],
                [10, 6],
              ]
            : COMP[s.comp];
      for (const [p, L] of pat)
        for (const m of voic)
          put(
            T.keys,
            voice(() => V.epNote(m, L * six * 1.1, 0.55, s.brightness)),
            t0 + swingT(p),
            0.3,
          );
      put(
        T.pad,
        voice(() =>
          V.supersaw(voic, bar * 1.1, { bright: 1600 * s.brightness }),
        ),
        t0,
        0.22,
      );
      if (["groove", "main", "breakdown"].includes(name)) {
        const bl =
          name === "breakdown"
            ? [[0, 16]]
            : [
                [0, 6],
                [6, 4],
                [10, 6],
              ];
        for (const [p, L] of bl)
          put(
            T.bass,
            voice(() => V.roundBass(D.midiHz(bassM), L * six * 0.95)),
            t0 + swingT(p),
            0.7,
          );
        if (drums && b % 2 === 1)
          put(
            T.bass,
            voice(() => V.roundBass(D.midiHz(bassM + 7), six * 1.8)),
            t0 + swingT(14),
            0.5,
          );
      }
      if (drums) {
        const kp = [
          ...dr.kick,
          ...(name === "main" ? dr.kickMain : []),
          ...(b % 2 ? dr.kickOdd : []),
        ];
        for (const p of kp) {
          const t = t0 + swingT(p);
          if (t >= end) continue;
          T.kick.push([voice(V.softKick), t, 0.9]);
          kicks.push(t);
        }
        if (dr.snare)
          for (const qn of [1, 3]) {
            put(T.snare, K.snap, t0 + qn * beat, 0.45);
            put(T.snare, K.clap, t0 + qn * beat + 0.006, 0.2);
          }
        for (let p = 0; p < 16; p += dr.hats)
          put(T.hats, K.hat, t0 + swingT(p), p % 4 ? 0.16 : 0.22, 0.15);
        if (name === "main" && dr.shaker)
          for (let p = 1; p < 16; p += 2)
            put(T.hats, K.shaker, t0 + swingT(p), 0.07, -0.2);
        if (last && si + 1 < sections.length)
          for (const p of [12, 13, 14, 15])
            put(T.snare, K.snap, t0 + swingT(p), 0.12 + 0.05 * (p - 12));
      }
      if (name === "main") {
        const mel =
          b % 2 === 0
            ? [
                [0, 12],
                [3, 14],
                [6, 16],
                [10, 19],
              ]
            : [
                [0, 17],
                [4, 16],
                [6, 14],
                [8, 12],
                [12, 11],
              ];
        for (const [p, iv] of mel) {
          const m = 60 + ((key + iv) % 24) + (key + iv < 12 ? 12 : 0);
          const v = voice(() =>
            s.lead === "glock"
              ? V.glock(m + 12, 1.0, 0.5)
              : s.lead === "pluck"
                ? V.pluck(m, 0.7, 0.55)
                : V.marimba(m, 0.9),
          );
          put(T.bell, v, t0 + swingT(p), 0.35, ((p % 3) - 1) * 0.25);
        }
      }
    }
    bars += count;
    // A swell into the next section when the drums come in on it.
    const nxt = sections[si + 1]?.type;
    if (
      (nxt === "groove" || nxt === "main") &&
      (name === "intro" || name === "breakdown")
    ) {
      const [nr, nq] = chords[bars % chords.length];
      const npc = (key + nr) % 12;
      const sw = V.swell(
        bar * 0.9,
        Q[nq].map((iv) =>
          48 + npc + iv >= 53 ? 48 + npc + iv : 60 + npc + iv,
        ),
      );
      T.fx.push([sw, Math.max(sec.start, end - sw.L.length / SR), 0.25]);
      T.fx.push([D.filt(V.hat(true), "lp", 7000), end, 0.3]);
    }
  });
  const chain = {
    kick: (x) => D.compress(D.filt(x, "lowshelf", 70, 0.707, 2), -14, 3, 3, 80),
    bass: (x) => D.compress(D.filt(x, "lp", 1500), -16, 3, 8, 100),
    snare: (x) =>
      D.withReverb(
        D.compress(D.filt(x, "hp", 300), -18, 2.5, 3, 100),
        0.35,
        0.6,
        0.2,
        0.85,
      ),
    hats: (x) => D.filt(D.filt(x, "hp", 6000), "lp", 14000),
    keys: (x) =>
      D.withReverb(
        D.compress(
          D.chorus(
            D.filt(D.filt(x, "hp", 150), "lp", 6500 * s.brightness),
            0.9,
            3,
            0.35,
          ),
          -18,
          2,
          10,
          150,
        ),
        0.45,
        0.5,
        0.18,
        0.85,
      ),
    pad: (x) => D.withReverb(D.filt(x, "hp", 200), 0.8, 0.5, 0.35, 0.7),
    bell: (x) =>
      D.withReverb(
        D.delay(D.filt(x, "hp", 300), beat * 0.75, 0.3, 0.2),
        0.5,
        0.5,
        0.25,
        0.8,
      ),
    fx: (x) => D.withReverb(D.filt(x, "hp", 150), 0.7, 0.5, 0.3, 0.8),
  };
  const levels = {
    kick: -2,
    bass: -3,
    snare: -3,
    hats: -6,
    keys: -8,
    pad: -11,
    bell: -5,
    fx: -9,
    ...s.levels,
  };
  // Sidechain: bass, keys and pad dip 3 dB on each kick.
  const sc = new Float32Array(n).fill(1);
  const rel = Math.round(beat * 0.4 * SR);
  for (const kt of kicks) {
    const i = Math.round(kt * SR);
    for (let k = 0; k < rel && i + k < n; k++) {
      const v = 1 - (1 - D.db(-3)) * Math.pow(1 - k / rel, 1.5);
      if (v < sc[i + k]) sc[i + k] = v;
    }
  }
  const mix = D.stereo(n);
  for (const [k, notes] of Object.entries(T)) {
    const x = build(notes);
    const y = D.peak(x) > 0 ? chain[k](x) : x;
    D.gain(y, D.db(levels[k]));
    if (["bass", "keys", "pad"].includes(k))
      for (let i = 0; i < n; i++) {
        y.L[i] *= sc[i];
        y.R[i] *= sc[i];
      }
    D.mixInto(mix, y);
  }
  sections.forEach((sec, si) => {
    if (SECTION_GAIN[sec.type] == null) return;
    const a = Math.round(sec.start * SR);
    const L = Math.round(((sections[si + 1]?.start ?? total) - sec.start) * SR);
    const g = D.db(SECTION_GAIN[sec.type]);
    const r = Math.min(Math.round(0.08 * SR), L >> 2);
    for (let i = 0; i < L && a + i < n; i++) {
      let gg = g;
      if (i < r) gg = 1 + ((g - 1) * i) / r;
      else if (i > L - r) gg = g + ((1 - g) * (i - (L - r))) / r;
      mix.L[a + i] *= gg;
      mix.R[a + i] *= gg;
    }
  });
  D.fadeOut(mix, 2.0);
  return mix;
}
