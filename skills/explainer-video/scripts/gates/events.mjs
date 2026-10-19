// The gates stage's reading of the scenes' timelines: what backend.events
// answered per scene (in the scene's own seconds) as video seconds.
const r3 = (n) => +n.toFixed(3);

// `raw` is backend.events' answer, `scenes` the timeline's. Returns
//   moves   scene id to the video-second windows its seam and camera run in
//   seams   every scene's seam windows, flat
//   times   every event: tween ends and window edges, of every scene
//   moving  (id, t) whether any scene's seam or the scene's own camera runs at
//           `t`, when its text does not read
// A seam is the transition between scenes and runs on past its own slot, so
// it holds the next scene's text back and its events fall in the next scene's
// samples too.
export function sceneEvents(raw, scenes) {
  const moves = {};
  const times = [];
  for (const sc of scenes) {
    const ev = raw[sc.id] ?? {};
    const at = (w) => w.map((x) => r3(sc.start + x));
    const seams = (ev.seams ?? []).map(at);
    const camera = (ev.camera ?? []).map(at);
    moves[sc.id] = { seams, camera };
    times.push(...at(ev.ends ?? []), ...seams.flat(), ...camera.flat());
  }
  const seams = Object.values(moves).flatMap((m) => m.seams);
  const moving = (id, t) =>
    [...seams, ...(moves[id]?.camera ?? [])].some(([a, b]) => t >= a && t < b);
  return { moves, seams, times, moving };
}
