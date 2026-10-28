// The sound kit's gates: licence (every sound the project plays but the
// narration has a licence record in sound.json) and bed level (the bed at
// least BED_LU under the voice in each 3 s window holding a word).
import fs from "node:fs";
import path from "node:path";
import { kitSounds } from "../lib/kit.mjs";
import { bedLane, laneAt } from "../render/bed.mjs";

export const BED_LU = 15;
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
    .map((s) => `${s}: no licence record in the kit`);
}

// The bed against the voice, `{ evidence, measured }`. In each 3 s window of
// the video holding a word, the voice is narration.wav's short-term loudness
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
  const [voice, music] = await Promise.all(
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
    const margin = at(voice, e) - at(music, e) - gain;
    if (!closest || margin < closest.margin) closest = { a, margin };
    if (margin < BED_LU)
      evidence.push(
        `window ${a} s: the bed is ${margin.toFixed(1)} LU under the voice, under ${BED_LU} LU`,
      );
  }
  return {
    evidence,
    measured: closest
      ? `${closest.margin.toFixed(1)} LU under the voice at its closest (window ${closest.a} s)`
      : "no window holds a word",
  };
}
