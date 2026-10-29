// Shared fixtures of the gates tests: a timed run folder whose scene files are
// authored from markup the canned backend reads (fake-backend-gates.mjs), its
// claims check passed, and the runner of the gates stage, which judges a
// pending critic.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { here, SCENES } from "./voice-lib.mjs";
import { exec, project, readJson, timing, voiced } from "./timing-lib.mjs";
import { cited, judge, pack, runCheck } from "./support-lib.mjs";

export const gates = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "gates",
  "gates.mjs",
);

// A scene file the way the agent writes one, `body` its markup and `js` the
// script that builds its timeline.
export const scene = (id, body, js = "") => `<template>
  <div id="root" data-composition-id="${id}" data-width="1920" data-height="1080">
    ${body}
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    ${js}
    window.__timelines["${id}"] = tl;
  </script>
</template>
`;

// Writes `compositions/<id>.html` from a scene's markup, or from `{ body, js }`.
export function compose(fx, id, body, js) {
  fs.mkdirSync(project(fx, "compositions"), { recursive: true });
  fs.writeFileSync(
    project(fx, "compositions", `${id}.html`),
    scene(id, body, js),
  );
}

// A voiced, timed run folder with every scene authored and the claims check
// passed: `bodies` maps a scene id to its markup, the others show one readable
// line; `brief` is written before timing, `scenes` replace the fixture's
// script, spoken in `language`.
export function timed(bodies = {}, { brief, scenes = SCENES, language } = {}) {
  const fx = voiced(cited(scenes), language);
  supported(fx);
  if (brief)
    fs.writeFileSync(path.join(fx.dir, "brief.json"), JSON.stringify(brief));
  const t = exec(timing, fx);
  assert.equal(t.code, 0, t.out + t.err);
  for (const { id } of scenes)
    compose(fx, id, bodies[id] ?? `<p>${id} line</p>`);
  return fx;
}

// The claims check passed on the run folder's script.json as it stands, every
// sentence judged supported or connective.
export function supported(fx) {
  pack(fx);
  judge(fx, readJson(path.join(fx.dir, "script.json")).scenes);
  const r = runCheck(fx);
  assert.equal(r.code, 0, r.out + r.err);
}

// The gates stage run to its verdict: a pending critic is judged by
// `critics` and the gates run again, the call log cleared first so it holds
// that one run. `{ critic: false }` returns the first run as it ends.
export function runGates(fx, extra = {}, { critic = true } = {}) {
  const r = exec(gates, fx, [fx.dir], extra);
  if (!critic || !/^gate critic: pending/m.test(r.out)) return r;
  critics(fx);
  fs.rmSync(fx.log, { force: true });
  return exec(gates, fx, [fx.dir], extra);
}

// The critic's verdict on each pending scene, as agents/critic.md writes it:
// every still described, and `failures` maps a scene id to its failures.
export function critics(fx, failures = {}) {
  const dir = path.join(fx.dir, record(fx).gates.critic.stills);
  const stills = readJson(path.join(dir, "stills.json"));
  for (const [id, list] of Object.entries(stills)) {
    const f = path.join(dir, `${id}.json`);
    if (fs.existsSync(f)) continue;
    fs.writeFileSync(
      f,
      JSON.stringify({
        stills: list.map((s) => ({ t: s.t, sees: `a frame of ${id}` })),
        failures: failures[id] ?? [],
      }),
    );
  }
}

export const timeline = (fx) => readJson(path.join(fx.dir, "timeline.json"));
export const record = (fx) => readJson(path.join(fx.dir, "gates.json"));

// A gate's printed line, or undefined.
export const gateLine = (r, name) =>
  r.out.match(new RegExp(`^gate ${name}: (.*)$`, "m"))?.[1];

// Asserts `name` is the only gate the run failed.
export function only(r, name) {
  const failing = [...r.out.matchAll(/^gate ([a-z ]+): fail/gm)].map(
    (m) => m[1],
  );
  assert.deepEqual(failing, [name], r.out + r.err);
}
