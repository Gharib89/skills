// Sound effects, synthesised and placed on the timeline. Ported from
// MotionCraft's SFX engine (github.com/ahmdd4vd/MotionCraft, MIT, notice in
// LICENSE-motioncraft), trimmed to the two the score uses: its whoosh_in and
// logo_sting, at its tested levels (dB) and high-pass (Hz).
import * as D from "./dsp.mjs";
import * as V from "./voices.mjs";

const RULES = {
  whoosh: {
    db: -9,
    hp: 150,
    sound: () => D.gain(V.noiseSweep(0.32, 400, 7000, true, 0.8), 0.5),
  },
  sting: {
    db: -8,
    hp: 200,
    sound: () => D.gain(V.chime([77, 84, 89, 96], 2.0, 0.05), 0.8),
  },
};

// cues: [{type, t}]. A whoosh rises into its time, so it lands on the cut.
export function renderSfx(cues, total, { seed, offset }) {
  D.setSeed(seed);
  const out = D.stereo(Math.round(total * D.SR));
  for (const c of cues) {
    const r = RULES[c.type];
    const x = D.filt(r.sound(), "hp", r.hp);
    const t = c.type === "whoosh" ? c.t - x.L.length / D.SR : c.t;
    D.place(out, x, Math.max(0, t), D.db(r.db + offset));
  }
  D.mixInto(out, D.reverb(out, 0.2, 0.6, 0.18));
  return out;
}
