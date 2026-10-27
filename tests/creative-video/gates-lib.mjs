// Shared fixtures of the gates tests: a timed run folder whose scene files are
// authored from markup the canned backend reads (fake-backend-gates.mjs), and
// the runner of the gates stage.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { here, SCENES } from "./voice-lib.mjs";
import { exec, project, readJson, timing, voiced } from "./timing-lib.mjs";

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

// A voiced, timed run folder with every scene authored: `bodies` maps a scene
// id to its markup, the others show one readable line; `brief` is written
// before timing, `scenes` replace the fixture's script.
export function timed(bodies = {}, { brief, scenes = SCENES } = {}) {
  const fx = voiced(scenes);
  if (brief)
    fs.writeFileSync(path.join(fx.dir, "brief.json"), JSON.stringify(brief));
  const t = exec(timing, fx);
  assert.equal(t.code, 0, t.out + t.err);
  for (const { id } of scenes)
    compose(fx, id, bodies[id] ?? `<p>${id} line</p>`);
  return fx;
}

export const runGates = (fx, extra = {}) => exec(gates, fx, [fx.dir], extra);
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
