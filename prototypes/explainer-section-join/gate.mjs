// PROTOTYPE: the determinism gate's check against a section composition: the
// same frame seeked twice in two browsers from the section, and once from the
// whole composition at the same absolute time, compared as decoded pixels.
// usage: node gate.mjs <work dir>
import fs from "node:fs";
import path from "node:path";
const lib = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "../../.claude/skills/explainer-video/scripts/lib",
);
const backend = await import(path.join(lib, "backend.mjs"));
const { hyperframesEnv } = await import(path.join(lib, "tools.mjs"));
const env = hyperframesEnv();
const [work] = process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(path.join(work, "plan.json"), "utf8"));
const out = path.join(work, "gate");
fs.mkdirSync(out, { recursive: true });
// One moment a few seconds into each section, on the frame grid.
const rows = [];
for (const [i, s] of plan.snapped.sections.entries()) {
  const local = 150 / 30;
  const shots = [
    ["section-a", `s${i + 1}`, local],
    ["section-b", `s${i + 1}`, local],
    ["whole", "whole", s.start + local],
  ];
  const hashes = {};
  for (const [name, dir, t] of shots) {
    const f = path.join(out, `s${i + 1}-${name}.png`);
    await backend.frame(path.join(work, "snapped", dir), t, f, { env });
    hashes[name] = await backend.framePixels(f);
  }
  rows.push({
    section: i + 1,
    t: local,
    a_eq_b: hashes["section-a"] === hashes["section-b"],
    section_eq_whole: hashes["section-a"] === hashes.whole,
  });
}
console.log(JSON.stringify(rows));
