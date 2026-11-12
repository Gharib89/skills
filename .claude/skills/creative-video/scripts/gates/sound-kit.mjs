// The sound kit's gates: licence (every sound the project plays but the
// narration has a licence record in sound.json), bed level (the bed at
// least BED_LU under the voice in each 3 s window holding a word, and at its
// closest no more than BED_MAX_LU under it, so it is heard) and effect level
// (each palette sound at least EFFECT_LU under the voice where it plays).
import fs from "node:fs";
import path from "node:path";
import { kitSounds } from "../lib/kit.mjs";
import { bedLane, laneAt } from "../render/bed.mjs";
import { sceneSeconds } from "./sounds.mjs";

export const BED_LU = 15;
export const BED_MAX_LU = 20;
export const EFFECT_LU = 6;
const WINDOW = 3;

// One finding per file an <audio> plays, in a scene, over.html (the probe's
// `events`) or the root (`root`, its HTML) but the narration, that no kit
// sound of that `file` carries a licence for.
export function licenceFindings(events, root, kit) {
  const licensed = new Set(
    kitSounds(kit)
      .filter((s) => s.file && s.licence)
      .map((s) => s.file),
  );
  const played = [
    ...Object.values(events).flatMap((e) => e.sounds.map((s) => s.src)),
    ...[
      ...root.matchAll(/<audio id="(?!narration")[^>]*?\ssrc="([^"]*)"/g),
    ].map((m) => m[1]),
  ]
    .filter(Boolean)
    .map((s) => s.replace(/^\.\//, "").split(/[?#]/)[0]);
  return [...new Set(played)]
    .filter((s) => !licensed.has(s))
    .map(
      (s) =>
        `${s}: no licence record in sound.json; play a sound.json file, or add it there and run sound/sounds.mjs`,
    );
}

// The bed against the voice, `{ evidence, measured }`: a window under BED_LU
// is a finding, and so is a bed over BED_MAX_LU at its closest. In each 3 s
// window of the video holding a word, the voice is narration.wav's short-term loudness
// over the window, and the bed its file's (looped) moved by its gain there:
// its level plus the lane's power mean over the window in dB, the lane read
// every 0.1 s. A loudness moves with gain in dB, so one measure of the file
// serves every level.
export async function bedLevel({ proj, timeline, kit, backend }) {
  const bed = kit?.bed;
  if (!bed?.file) return { evidence: [], measured: "no bed" };
  if (!fs.existsSync(path.join(proj, bed.file)))
    return {
      evidence: [`${bed.file} is missing: run sound/sounds.mjs`],
    };
  const { total, scenes } = timeline;
  const lane = bedLane(timeline, bed.out);
  const words = scenes.flatMap((s) => s.words);
  const [voice, bedLoudness] = await Promise.all(
    [path.join(proj, "assets", "narration.wav"), path.join(proj, bed.file)].map(
      (f) => backend.shortTerm(f, total),
    ),
  );
  const at = (series, t) =>
    series.findLast(([s]) => s <= t + 1e-6)?.[1] ?? -Infinity;
  const evidence = [];
  let closest;
  for (let a = 0; a < total; a += WINDOW) {
    const e = Math.min(a + WINDOW, total);
    if (
      !words.some((w) => w.start < e && w.end > a) ||
      at(voice, e) === -Infinity
    )
      continue;
    const steps = Math.max(1, Math.round((e - a) * 10));
    let power = 0;
    for (let i = 0; i < steps; i++)
      power += laneAt(lane, a + ((i + 0.5) * (e - a)) / steps) ** 2;
    const gain = bed.level + 10 * Math.log10(power / steps);
    const margin = at(voice, e) - at(bedLoudness, e) - gain;
    if (!closest || margin < closest.margin) closest = { a, margin };
    if (margin < BED_LU)
      evidence.push(
        `window ${a} s: the bed is ${margin.toFixed(1)} LU under the voice, under ${BED_LU} LU`,
      );
  }
  // The bed is heard where it is closest: every window sits at least that far.
  if (closest?.margin > BED_MAX_LU)
    evidence.push(
      `window ${closest.a} s: the bed is ${closest.margin.toFixed(1)} LU under the voice even at its closest, over ${BED_MAX_LU} LU: raise its level by ${(closest.margin - BED_MAX_LU).toFixed(1)} to ${(closest.margin - BED_LU).toFixed(1)} dB`,
    );
  return {
    evidence,
    measured: closest
      ? `${closest.margin.toFixed(1)} LU under the voice at its closest (window ${closest.a} s)`
      : "no window holds a word",
  };
}

// The palette sounds against the voice, `{ evidence, measured }`. Each palette
// sound a scene plays (`events`, the probe's) is judged in the 3 s window of the
// video its start falls in: the voice is narration.wav's short-term loudness
// at the window's end, the effect its file's, looped to fill a window, moved by
// the volume it plays at. A sound played where the voice is silent has nothing
// to sit under, and a file the kit does not carry is the licence gate's.
export async function effectLevel({ proj, timeline, kit, events, backend }) {
  const files = new Set((kit?.palette ?? []).map((s) => s.file));
  const plays = Object.entries(events).flatMap(([id, e]) =>
    e.sounds
      .map((s) => ({
        scene: id,
        s,
        file: s.src?.replace(/^\.\//, "").split(/[?#]/)[0],
      }))
      .filter((p) => files.has(p.file)),
  );
  if (!plays.length) return { evidence: [], measured: "no effect" };
  const { total, scenes } = timeline;
  const voice = await backend.shortTerm(
    path.join(proj, "assets", "narration.wav"),
    total,
  );
  const loud = new Map();
  for (const { file } of plays)
    if (!loud.has(file))
      loud.set(
        file,
        (await backend.shortTerm(path.join(proj, file), WINDOW + 0.5)).at(
          -1,
        )[1],
      );
  const evidence = [];
  let closest;
  for (const { scene, s, file } of plays) {
    const start = scenes.find((x) => x.id === scene)?.start ?? 0;
    const t = start + sceneSeconds({ start }, s);
    const a = Math.floor(t / WINDOW) * WINDOW;
    const e = Math.min(a + WINDOW, total);
    const heard = voice.findLast(([at]) => at <= e + 1e-6)?.[1] ?? -Infinity;
    if (heard === -Infinity) continue;
    const margin = heard - (loud.get(file) + 20 * Math.log10(s.volume));
    const at = +t.toFixed(3);
    if (!closest || margin < closest.margin)
      closest = { margin, where: `${scene}'s ${s.id} at ${at} s` };
    if (margin < EFFECT_LU)
      evidence.push(
        `${scene}: <audio id="${s.id}"> (${file}) is ${margin.toFixed(1)} LU under the voice at ${at} s, under ${EFFECT_LU} LU: set its data-volume to ${+(s.volume * 10 ** ((margin - EFFECT_LU) / 20)).toFixed(3)} or lower`,
      );
  }
  return {
    evidence,
    measured: closest
      ? `${closest.margin.toFixed(1)} LU under the voice at its closest (${closest.where})`
      : "no effect plays where the voice does",
  };
}

// The level gates' rows for gates.mjs, `{ name: [evidence, floor, measured] }`.
export async function levelGates(args) {
  const [bed, effects] = await Promise.all([bedLevel(args), effectLevel(args)]);
  return {
    "bed level": [bed.evidence, `${BED_LU} to ${BED_MAX_LU} LU`, bed.measured],
    "effect level": [effects.evidence, `${EFFECT_LU} LU`, effects.measured],
  };
}
