// The timing stage with a cast: captions name a new role, and a voice.json
// voiced for other roles or another cast is refused.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  captionFindings,
  cuesOf,
} from "../../skills/creative-video/scripts/gates/captions.mjs";
import { srtText } from "../../skills/creative-video/scripts/render/delivery.mjs";
import { fixture, run, write, writeCast } from "./voice-lib.mjs";
import {
  exec,
  install,
  project,
  read,
  readJson,
  timing,
} from "./timing-lib.mjs";

const SCENES = [
  {
    id: "hook",
    narration: [
      "Ship drives one issue to a merged pull request.",
      "Why not merge it by hand?",
    ],
    roles: [null, "learner"],
  },
  {
    id: "recap",
    narration: [
      "Because the review comes first.",
      "Every change lands through a reviewed pull request.",
    ],
  },
];
const CAST = {
  narrator: { voices: { en: "af_heart" } },
  learner: { voices: { en: "am_fenrir" } },
};

function castVoiced(scenes = SCENES) {
  const fx = fixture(scenes);
  writeCast(fx, CAST);
  const v = run(fx);
  assert.equal(v.code, 0, v.out + v.err);
  install(fx);
  return fx;
}

test("a cue whose role changes opens with the role's name, in the composition and the SRT alike", () => {
  const fx = castVoiced();
  const t = exec(timing, fx);
  assert.equal(t.code, 0, t.out + t.err);
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  assert.deepEqual(
    tl.cues.map((c) => c.text),
    [
      "Narrator: Ship drives one issue to a merged pull request.",
      "Learner: Why not merge it by hand?",
      "Narrator: Because the review comes first.",
      "Every change lands through a reviewed pull request.",
    ],
  );
  const html = read(project(fx, "compositions", "captions.html"));
  assert.ok(
    html.includes(
      '<span class="who">Learner:</span> <span class="w">Why</span>',
    ),
  );
  assert.deepEqual(
    cuesOf(html).map((c) => c.text),
    tl.cues.map((c) => c.text),
  );
  assert.deepEqual(
    captionFindings({
      timeline: tl,
      cues: cuesOf(html),
      srtText: srtText(tl.cues),
    }),
    [],
  );
});

test("a voice.json voiced for other roles or another cast is refused", () => {
  const fx = castVoiced();
  write(fx, [{ ...SCENES[0], roles: ["learner", null] }, SCENES[1]]);
  const r = exec(timing, fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^timing: voice\.json does not match scene hook: run the voice stage again/,
  );
  write(fx, SCENES);
  writeCast(fx, { ...CAST, learner: { voices: { en: "bf_emma" } } });
  const c = exec(timing, fx);
  assert.equal(c.code, 1);
  assert.match(
    c.err,
    /^timing: voice\.json holds learner am_fenrir, the script asks for bf_emma: run the voice stage again/,
  );
  fs.rmSync(project(fx, "kit", "cast.json"));
  assert.match(
    exec(timing, fx).err,
    /^timing: script\.json: scene hook names role learner, and project\/kit\/cast\.json is missing/,
  );
});
