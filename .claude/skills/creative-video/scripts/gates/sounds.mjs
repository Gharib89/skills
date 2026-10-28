// The sounds gate, and the scene seconds the warnings judge a sound at. The
// probe gives each scene's sounds as `{ id, start, authored }`: `start` the
// live data-start after the scripts ran, `authored` the data-start in the scene
// file of the <audio> with that id, null for one a script created. HyperFrames
// 0.8.206 renders a static <audio> at its scene file's start in scene seconds,
// whatever a script sets later, a created one at its live start in video
// seconds, and no <audio> it cannot tell apart: one with no id, or one a script
// created with an id another <audio> carries (measured, #1028).

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
      if (!id)
        return [
          `${sc.id}: an <audio> with no id: the render cannot place it, so give it an id`,
        ];
      if (authored === null)
        return carried.get(id) > 1
          ? [
              `${audio} is created by its script with an id another <audio> carries: the render drops it, so give it an id no other <audio> has`,
            ]
          : [];
      return Math.abs(start - authored) > 1e-3
        ? [
            `${audio} starts at ${authored} s in its scene file and ${start} s after its script ran: the render plays ${authored} s, so create the sound in the script instead`,
          ]
        : [];
    }),
  );
}
