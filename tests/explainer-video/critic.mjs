// The critic's part in a test: what the critic subagents write, a verdict per
// contact sheet, in the folder the last gates run named in gates.json.
import fs from "node:fs";
import path from "node:path";

export const CLEAN = {
  failures: [],
  scores: { clarity: 4, legibility: 5, fit: 4, motion: 3 },
  worst: [],
};

// A verdict for every contact sheet the last gates run left without one,
// `verdict(id)` giving each scene's. Returns the scene ids it judged.
export function critique(run, verdict = () => CLEAN) {
  const record = JSON.parse(
    fs.readFileSync(path.join(run, "gates.json"), "utf8"),
  );
  const dir = path.join(run, record.gates.critic.sheets);
  const ids = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".png"))
    .map((f) => path.basename(f, ".png"))
    .filter((id) => !fs.existsSync(path.join(dir, `${id}.json`)));
  for (const id of ids)
    fs.writeFileSync(path.join(dir, `${id}.json`), JSON.stringify(verdict(id)));
  return ids;
}

// A render stage run: when the critic alone held it, a clean critic round and
// the render again, as a run does; `held` is then the run the critic held.
export function judged(run, again) {
  const r = again();
  if (
    !/^gate critic: pending/m.test(r.out) ||
    !/^gates: \d+ pass, 0 fail/m.test(r.out)
  )
    return r;
  critique(run);
  return { ...again(), held: r };
}
