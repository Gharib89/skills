// Maintainer only: the check of real-render.mjs that proves the `canvas` seams
// family composes a video on one map. Two short videos, each rendered twice, one
// reading left to right and one right to left, give the composer's frames and 0
// differing frames; the camera is travelling over the start of the second scene
// and has settled a travel later, so those two frames differ.
import path from "node:path";

const IDS = {
  ltr: ["hook", "canvas", "steps"],
  rtl: ["arabic-canvas", "arabic-timeline"],
};

export async function mapChecks({
  FIXTURE,
  profile,
  work,
  compose,
  render,
  framemd5,
  seek,
  check,
}) {
  const mapped = { ...profile, grammar: { seams: { family: "canvas" } } };
  for (const [dir, names] of Object.entries(IDS)) {
    const part = names.map((id) => FIXTURE.find((p) => p.scene.id === id));
    const map = await compose(`map-${dir}`, part, true, { prof: mapped, dir });
    const [x, y] = ["a", "b"].map((n) =>
      path.join(work, `map-${dir}-${n}.mp4`),
    );
    const ok = (await render(map.comp, x)) && (await render(map.comp, y));
    const [fx, fy] = ok ? [x, y].map(framemd5) : [[], []];
    const apart = fx.filter((l, i) => l !== fy[i]).length;
    const next = map.scenes[1];
    const travel = next.slot - next.duration;
    const at = (t) => seek(t, `map-${dir}-${t}`, false, map.comp);
    const [during, after] = ok
      ? [
          await at(+(next.start + 0.1).toFixed(3)),
          await at(+(next.start + travel + 0.4).toFixed(3)),
        ]
      : [Buffer.alloc(0), Buffer.alloc(0)];
    check(
      `canvas map ${dir}`,
      ok &&
        fx.length === map.frames &&
        fx.length === fy.length &&
        apart === 0 &&
        !during.equals(after),
      `${ok ? fx.length : 0} frames rendered, the composer's grid is ${map.frames}; ${apart} differing frames of ${fx.length} in a second render; the camera ${during.equals(after) ? "draws NO motion" : "moves"} over the second scene's start`,
    );
  }
}
