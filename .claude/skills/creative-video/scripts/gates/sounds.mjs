// The sounds gate, and the scene seconds the warnings judge a sound at. The
// probe gives each scene's sounds as `{ id, start, authored }`: `start` the
// live data-start after the scripts ran, `authored` the data-start in the scene
// file of the <audio> with that id, null for one a script created. HyperFrames
// 0.8.206 renders a static <audio> at its scene file's start in scene seconds,
// whatever a script sets later, and a created one at its live start in video
// seconds. It refuses a static one with no id (a --strict lint error), and
// never plays a created one with no id or with an id another <audio> carries
// (measured, #1028).

// A sound's start in its scene's seconds.
export const sceneSeconds = (sc, s) =>
  s.authored === null ? s.start - sc.start : s.start;

// One finding per sound the render plays elsewhere than the gates judge it.
export function soundFindings(plan, events) {
  const carried = new Map();
  for (const { sounds } of Object.values(events))
    for (const { id } of sounds) carried.set(id, (carried.get(id) ?? 0) + 1);
  return plan.flatMap(({ sc }) =>
    (events[sc.id]?.sounds ?? []).flatMap(({ id, start, authored }) => {
      const audio = `${sc.id}: <audio id="${id}">`;
      const end = sc.start + sc.duration;
      if (!id)
        return [
          `${sc.id}: an <audio> with no id: the render refuses one written in the scene file and never plays one a script created, so give it an id`,
        ];
      if (authored === null) {
        if (carried.get(id) > 1)
          return [
            `${audio} is created by its script with an id another <audio> carries: the render drops it, so give it an id no other <audio> has`,
          ];
        // The scene start is on the frame grid, the probe's start rounded to
        // the millisecond, so one placed on the scene's first word may read
        // up to 0.5 ms early.
        return start < sc.start - 1e-3 || start > end
          ? [
              `${audio} is created by its script at ${start} s, outside its scene (${sc.start.toFixed(3)} s to ${end.toFixed(3)} s): a created <audio>'s data-start counts seconds of the whole video, so add TIMING.scenes["${sc.id}"].start to it`,
            ]
          : [];
      }
      return start !== authored
        ? [
            `${audio} starts at ${authored} s in its scene file and ${start} s after its script ran: the render plays ${authored} s, so remove it from the scene file and create it in the script at data-start ${(sc.start + start).toFixed(3)} (the scene's start plus ${start} s)`,
          ]
        : [];
    }),
  );
}
