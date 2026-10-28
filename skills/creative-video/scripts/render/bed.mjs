// The bed in the mix: sound.json's bed as the root's <audio id="bed">, at its
// `level` (dB) with a media-use volume lane (`data-automation`) over the whole
// video: full level where no one speaks, ducked to DUCK while the words play
// (word runs closer than `gap` merged into one), 0 across each `out` scene. The
// lane is linear between its points, so each change ramps over RAMP s on its
// louder side: the bed is down by the first word, and up only after the last.
export const DUCK = 0.35;
const GAP = 0.6;
const RAMP = 0.2;
// media-use's limit on one lane.
const MAX_POINTS = 512;
const r3 = (n) => +n.toFixed(3);

// The bed's gain under its `level`, as data-volume takes it.
export const bedVolume = (level) => +(10 ** (level / 20)).toFixed(4);

// The lane's points `{ t, v }` for `timeline` (each scene's absolute word
// times) with the scenes `out` silenced; past MAX_POINTS the word runs merge
// over wider gaps, and out scenes that alone pass it are refused.
export function bedLane(timeline, out = [], gap = GAP) {
  const { total, scenes } = timeline;
  for (const id of out)
    if (!scenes.some((s) => s.id === id))
      throw new Error(
        `project/kit/sound.json: bed.out names ${id}, no scene of the timeline`,
      );
  const runs = [];
  for (const w of scenes.flatMap((s) => s.words)) {
    const last = runs.at(-1);
    if (last && w.start - last.end < gap) last.end = Math.max(last.end, w.end);
    else runs.push({ start: w.start, end: w.end });
  }
  const silent = scenes
    .filter((s) => out.includes(s.id))
    .map((s) => ({ start: s.start, end: s.start + s.duration }));
  const inside = (spans, t) => spans.some((s) => t >= s.start && t < s.end);
  const level = (t) => (inside(silent, t) ? 0 : inside(runs, t) ? DUCK : 1);
  const cuts = [
    ...new Set([
      0,
      total,
      ...[...runs, ...silent].flatMap((s) => [s.start, s.end]),
    ]),
  ]
    .filter((t) => t >= 0 && t <= total)
    .sort((a, b) => a - b);
  // Stretches of one level, neighbours of the same level joined.
  const parts = [];
  for (let i = 0; i < cuts.length - 1; i++) {
    const v = level((cuts[i] + cuts[i + 1]) / 2);
    if (parts.at(-1)?.v === v) parts.at(-1).end = cuts[i + 1];
    else parts.push({ start: cuts[i], end: cuts[i + 1], v });
  }
  const points = [{ t: 0, v: parts[0].v }];
  parts.slice(1).forEach((p, i) => {
    const prev = parts[i];
    const len = (s) => Math.min(RAMP, (s.end - s.start) / 2);
    if (p.v < prev.v)
      points.push(
        { t: r3(p.start - len(prev)), v: prev.v },
        { t: p.start, v: p.v },
      );
    else
      points.push(
        { t: p.start, v: prev.v },
        { t: r3(p.start + len(p)), v: p.v },
      );
  });
  points.push({ t: total, v: parts.at(-1).v });
  const lane = points.filter(
    (p, i) => !i || p.t !== points[i - 1].t || p.v !== points[i - 1].v,
  );
  if (lane.length <= MAX_POINTS) return lane;
  // A gap past the video already merges every word into one run: what is left
  // is the out scenes' own edges, which no gap moves.
  if (gap > total)
    throw new Error(
      `project/kit/sound.json: bed.out's ${out.length} scene(s) take the bed's volume lane past ${MAX_POINTS} points: silence fewer scenes, or neighbouring ones`,
    );
  return bedLane(timeline, out, gap * 1.5);
}

// The lane's value at `t`.
export function laneAt(points, t) {
  const i = points.findIndex((p) => p.t > t);
  if (i < 0) return points.at(-1).v;
  if (i === 0) return points[0].v;
  const [a, b] = [points[i - 1], points[i]];
  return a.v + ((b.v - a.v) * (t - a.t)) / (b.t - a.t);
}

// The root's <audio id="bed">, `total` seconds long and looped, since a bed
// shorter than the video would stop: HyperFrames 0.8.206 reads the HTML `loop`
// attribute of an <audio> and repeats the file to its clip's length.
export function bedHtml({ file, level, out }, timeline) {
  const lane = JSON.stringify({
    version: 1,
    lanes: [{ target: "volume", points: bedLane(timeline, out) }],
  }).replaceAll('"', "&quot;");
  return `<audio id="bed" class="clip" src="${file}" data-start="0" data-duration="${timeline.total}" data-volume="${bedVolume(level)}" data-track-index="5" loop data-automation="${lane}"></audio>`;
}
