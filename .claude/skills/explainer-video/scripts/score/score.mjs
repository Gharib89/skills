// The score: music synthesised in code and arranged to the scene timings,
// ducked under speech from the word timings, with sound effects on the cuts.
// Deterministic: the same scenes, roles, seed and level give the same samples.
import * as D from "./dsp.mjs";
import { PRESETS, renderMusic } from "./music.mjs";
import { renderSfx } from "./sfx.mjs";

// The duck's levels (dB): no narration, a pause inside a scene's narration,
// and speech. Speech opens LEAD s before each word; spans closer than SMOOTH
// merge; the curve is a centred SMOOTH-wide average of those steps.
const OPEN = 0;
const PAUSE = -6;
const SPEECH = -15;
const LEAD = 0.15;
const SMOOTH = 0.4;
const RATE = 100;

// A scene's arrangement by its script role; without one the first scene is
// the intro, the last the outro and the rest main.
const SECTION = {
  hook: "intro",
  context: "groove",
  point: "main",
  recap: "breakdown",
  end: "outro",
};
// The music level (dBFS RMS) the sound effects' own levels are set against;
// they move with the score's music level by its distance from this.
const SFX_BED = -20;
// The music's RMS before the duck, in dB under the narration's speech RMS.
const UNDER = 8;
// What ACE-Step is asked for: music that sits under an explainer's narration.
export const ACE_CAPTION =
  "calm instrumental background music for a software tutorial video, soft electric piano, warm bass, light brushed drums, gentle and unobtrusive, steady groove, no vocals";

// The bed level (dBFS RMS) for a narration: its RMS over the words' spans,
// UNDER dB down. pcm: 16-bit mono samples at `rate`; scenes' times absolute.
export function bedLevel(pcm, rate, scenes) {
  let e = 0;
  let count = 0;
  for (const sc of scenes)
    for (const w of sc.words)
      for (
        let i = Math.round(w.start * rate);
        i < Math.min(pcm.length, Math.round(w.end * rate));
        i++
      ) {
        e += (pcm[i] / 32768) ** 2;
        count++;
      }
  return D.toDb(Math.sqrt(e / Math.max(1, count))) - UNDER;
}

// The duck curve over `total` s: {rate, db}, db[k] the gain in dB at k / rate s.
// scenes: [{start, duration, words: [{start, end}]}], times absolute.
export function duck(scenes, total) {
  const n = Math.round(total * RATE) + 1;
  const step = new Float32Array(n).fill(OPEN);
  const fill = (a, b, v) => {
    for (
      let k = Math.max(0, Math.round(a * RATE));
      k < Math.min(n, Math.round(b * RATE));
      k++
    )
      step[k] = v;
  };
  for (const sc of scenes) {
    const spans = [];
    for (const w of sc.words) {
      const a = w.start - LEAD;
      if (spans.length && a - spans.at(-1)[1] < SMOOTH) spans.at(-1)[1] = w.end;
      else spans.push([a, w.end]);
    }
    if (!spans.length) continue;
    fill(spans[0][0], spans.at(-1)[1], PAUSE);
    for (const [a, b] of spans) fill(a, b, SPEECH);
  }
  const half = Math.round((SMOOTH * RATE) / 2);
  const sum = new Float64Array(n + 1);
  for (let k = 0; k < n; k++) sum[k + 1] = sum[k] + step[k];
  const db = new Float32Array(n);
  for (let k = 0; k < n; k++) {
    const a = Math.max(0, k - half);
    const b = Math.min(n, k + half + 1);
    db[k] = (sum[b] - sum[a]) / (b - a);
  }
  return { rate: RATE, db };
}

// The score as a 48 kHz stereo buffer `total` s long, its music at `level`
// dBFS RMS before the duck. roles: each scene's script role, if any.
// perMinute: the sfx gate's floor; a cue is dropped when the minute ending at
// it already holds that many, so no minute holds more.
// music: a 48 kHz stereo buffer `total` s long made elsewhere (ACE-Step),
// levelled, ducked and given its effects in the synth's place.
// Returns {buf, cues: [{type, t}], spec: {preset, seed, sections}}, spec
// {seed} for given music.
export function score({
  scenes,
  roles = [],
  total,
  seed,
  level,
  perMinute,
  music,
}) {
  const names = Object.keys(PRESETS);
  const preset = names[seed % names.length];
  const sections = scenes.map((sc, i) => ({
    type:
      SECTION[roles[i]] ??
      (i === 0 ? "intro" : i === scenes.length - 1 ? "outro" : "main"),
    start: sc.start,
  }));
  const buf = music ?? renderMusic({ sections, total, preset, seed });
  let e = 0;
  for (let i = 0; i < buf.L.length; i++) e += buf.L[i] ** 2 + buf.R[i] ** 2;
  D.gain(buf, D.db(level - D.toDb(Math.sqrt(e / (2 * buf.L.length)))));
  const c = duck(scenes, total);
  for (let i = 0; i < buf.L.length; i++) {
    const p = (i / D.SR) * c.rate;
    const k = Math.min(Math.floor(p), c.db.length - 2);
    const g = D.db(c.db[k] + (c.db[k + 1] - c.db[k]) * (p - k));
    buf.L[i] *= g;
    buf.R[i] *= g;
  }
  const last = scenes.at(-1).words.at(-1);
  const cues = [];
  for (const c of [
    ...scenes.slice(1).map((sc) => ({ type: "whoosh", t: sc.start })),
    ...(last ? [{ type: "sting", t: last.end }] : []),
  ])
    if (cues.filter((k) => k.t > c.t - 60).length < perMinute) cues.push(c);
  D.mixInto(buf, renderSfx(cues, total, { seed, offset: level - SFX_BED }));
  return {
    buf,
    cues,
    spec: music ? { seed } : { preset, seed, sections },
  };
}
