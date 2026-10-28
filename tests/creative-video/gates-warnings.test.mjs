// The advisory warnings: printed as `warn <name>: <detail>`, recorded in
// gates.json, and never changing the exit.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { warnings } from "../../skills/creative-video/scripts/gates/warnings.mjs";
import { narrator } from "../../skills/creative-video/scripts/lib/narrators.mjs";
import { project, readJson } from "./timing-lib.mjs";
import { compose, record, runGates, timed, timeline } from "./gates-lib.mjs";
import { writeCast } from "./voice-lib.mjs";

const warns = (r, name) =>
  [...r.out.matchAll(new RegExp(`^warn ${name}: (.*)$`, "gm"))].map(
    (m) => m[1],
  );
const sounds = (n, at = 1) =>
  Array.from(
    { length: n },
    (_, i) => `<audio id="s${i}" data-sound="${at}"></audio>`,
  ).join("");

test("pacing is always printed: the change events a minute, and no dead stretch on a scene tweening throughout", () => {
  const fx = timed();
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(warns(r, "pacing"), [
    "14.4 change events a minute; no dead stretch",
  ]);
  assert.deepEqual(record(fx).warnings, [
    "pacing: 14.4 change events a minute; no dead stretch",
  ]);
});

test("a stretch of 2 s or more with no running tween is a dead stretch, named by its video seconds and scene", () => {
  const r = runGates(
    timed({ context: '<p>a line</p><i data-tween="0-1"></i>' }),
  );
  assert.equal(r.code, 0, r.out);
  assert.match(warns(r, "pacing")[0], /; dead 4\.10-8\.13 s in context$/);
  // 1.9 s of gap is no dead stretch
  const short = runGates(
    timed({ context: '<p>a line</p><i data-tween="0-3.13"></i>' }),
  );
  assert.match(warns(short, "pacing")[0], /no dead stretch$/);
});

test("a gap of exactly 2 s is a dead stretch, one of 1.99 s is not", () => {
  const gap = (g) => {
    const fx = timed();
    const { duration } = timeline(fx).scenes[1];
    compose(
      fx,
      "context",
      `<p>a line</p><i data-tween="0-${(duration - g).toFixed(3)}"></i>`,
    );
    return warns(runGates(fx), "pacing")[0];
  };
  assert.match(gap(2), /; dead 6\.13-8\.13 s in context$/);
  assert.match(gap(1.99), /no dead stretch$/);
});

test("more than 24 sounds in a minute warns, 24 do not", () => {
  const over = runGates(timed({ context: `<p>a line</p>${sounds(25)}` }));
  assert.equal(over.code, 0, over.out);
  assert.match(
    warns(over, "effect rate")[0],
    /^25 sounds in the minute from 4\.10 s, over 24 a minute$/,
  );
  const at = runGates(timed({ context: `<p>a line</p>${sounds(24)}` }));
  assert.deepEqual(warns(at, "effect rate"), []);
});

test("a sound more than 0.15 s from the nearest tween start warns by scene and gap", () => {
  const off = runGates(
    timed({
      hook: '<p>a line</p><i data-tween="0.5-3"></i><audio id="ding" data-sound="0.9"></audio>',
    }),
  );
  assert.equal(off.code, 0, off.out);
  assert.deepEqual(warns(off, "effect onset"), [
    "hook: the sound at 0.90 s is 0.40 s from the nearest tween start",
  ]);
  const on = runGates(
    timed({
      hook: '<p>a line</p><i data-tween="0.5-3"></i><audio id="ding" data-sound="0.6"></audio>',
    }),
  );
  assert.deepEqual(warns(on, "effect onset"), []);
  const sound = (at) =>
    warns(
      runGates(
        timed({
          hook: `<p>a line</p><i data-tween="0.5-3"></i><audio id="ding" data-sound="${at}"></audio>`,
        }),
      ),
      "effect onset",
    );
  assert.deepEqual(sound(0.65), []);
  assert.deepEqual(sound(0.66), [
    "hook: the sound at 0.66 s is 0.16 s from the nearest tween start",
  ]);
});

test("a scene over 30 s warns, and so does a sentence over 25 words", () => {
  const long = Array.from({ length: 26 }, (_, i) => `word${"s".repeat(i % 3)}`);
  const scenes = [
    { id: "hook", narration: [`${long.join(" ")}.`, "A short one."] },
  ];
  const r = runGates(timed({}, { scenes }));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    warns(r, "sentences")[0],
    /^hook: "word words wordss word words\.\.\." is 26 words, over 25$/,
  );
  assert.deepEqual(warns(r, "scene length"), []);
  // 25 words is not over 25
  const edge = Array.from({ length: 25 }, () => "word").join(" ");
  const at = runGates(
    timed({}, { scenes: [{ id: "hook", narration: [`${edge}.`] }] }),
  );
  assert.deepEqual(warns(at, "sentences"), []);
  // 14 sentences of about 2.8 s each in the canned voice
  const slow = [
    {
      id: "hook",
      narration: Array(14).fill("The quick brown fox jumps over the lazy dog."),
    },
  ];
  const s = runGates(timed({}, { scenes: slow }));
  assert.match(warns(s, "scene length")[0], /^hook: \d+\.\d s, over 30 s$/);
  // ten of them and "Go." are 30.000 s in the canned voice, "Fox." 30.067 s
  const nearly = (tail) => ({
    id: "hook",
    narration: [
      ...Array(10).fill("The quick brown fox jumps over the lazy dog."),
      tail,
    ],
  });
  const exact = runGates(timed({}, { scenes: [nearly("Go.")] }));
  assert.deepEqual(warns(exact, "scene length"), []);
  const over = runGates(timed({}, { scenes: [nearly("Fox.")] }));
  assert.match(warns(over, "scene length")[0], /^hook: 30\.1 s, over 30 s$/);
});

// Writes `cast` as `fx`'s cast.json and gives its script.json the top-level
// `extra` fields and each scene the `roles` its id maps to.
function recast(fx, cast, roles, extra = {}) {
  const file = path.join(fx.dir, "script.json");
  const script = readJson(file);
  fs.writeFileSync(
    file,
    JSON.stringify({
      ...script,
      ...extra,
      scenes: script.scenes.map((s) => ({ ...s, roles: roles[s.id] })),
    }),
  );
  writeCast(fx, cast);
}

test("two roles on one Kokoro voice in the script's language warn whatever their style lines", () => {
  const fx = timed(
    {},
    {
      scenes: [
        {
          id: "hook",
          narration: [
            "Ship drives one issue to a merged pull request.",
            "Why not merge it by hand?",
            "Because the review comes first.",
          ],
        },
        {
          id: "context",
          narration: [
            "It reads the profile first.",
            "Then it claims the issue.",
            "So no other run takes it.",
          ],
        },
      ],
    },
  );
  recast(
    fx,
    {
      narrator: { voices: { en: "af_heart" } },
      learner: { voices: { en: "af_heart", ar: "ar-eg-csagent-2" } },
      rival: { voices: { en: "am_fenrir" }, style: "a smug rival" },
      critic: { voices: { en: "am_fenrir" }, style: "a smug rival" },
      host: { voices: { en: "am_fenrir" }, style: "a calm host" },
      guide: { voices: { ar: "ar-eg-csagent-2" } },
    },
    {
      hook: [null, "learner", "rival"],
      context: ["critic", "host", "rival"],
    },
  );
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const alike = [
    "narrator and learner both speak af_heart",
    "rival and critic both speak am_fenrir",
    "rival and host both speak am_fenrir",
    "critic and host both speak am_fenrir",
  ];
  assert.deepEqual(warns(r, "alike voices"), alike);
  assert.deepEqual(
    record(fx).warnings.filter((w) => w.startsWith("alike voices")),
    alike.map((a) => `alike voices: ${a}`),
  );
});

// The alike voices warnings for `voiced`, each speaking role's narrators.json
// entry.
const alike = (voiced) =>
  warnings({
    plan: [],
    events: {},
    script: { scenes: [] },
    voiced,
    sound: null,
    total: 60,
    proj: fileURLToPath(new URL("./no-project/", import.meta.url)),
  }).filter((w) => w.startsWith("alike voices"));

test("on Gemini, which acts the style line, two roles on one voice warn only when their style lines match", () => {
  const gemini = (style) => ({ ...narrator("ar-eg-csagent-2", "ar"), style });
  assert.deepEqual(
    alike({
      narrator: narrator("ar-eg-csagent-2", "ar"),
      host: gemini("a calm host"),
      rival: gemini("a calm host"),
      critic: gemini("a sharp critic"),
    }),
    [
      "alike voices: host and rival both speak ar-eg-csagent-2 in the same style",
    ],
  );
});

const alikeWarns = (fx) => warns(runGates(fx), "alike voices");

test("the narrator role a cast leaves out counts when it speaks: script.json's narrator, else the language's default", () => {
  const fx = timed();
  const learner = (id) => ({ learner: { voices: { en: id } } });
  const roles = { context: [null, "learner"] };
  recast(fx, learner("af_heart"), roles);
  assert.deepEqual(alikeWarns(fx), [
    "narrator and learner both speak af_heart",
  ]);
  recast(fx, learner("am_fenrir"), roles, { narrator: "am_fenrir" });
  assert.deepEqual(alikeWarns(fx), [
    "narrator and learner both speak am_fenrir",
  ]);
  recast(fx, learner("am_fenrir"), roles, { narrator: undefined });
  assert.deepEqual(alikeWarns(fx), []);
});

test("a role no sentence speaks never warns: a cast role, or the narrator role a cast leaves out", () => {
  const fx = timed();
  recast(
    fx,
    {
      host: { voices: { en: "af_heart" } },
      learner: { voices: { en: "am_fenrir" } },
      extra: { voices: { en: "am_fenrir" } },
    },
    { hook: ["host"], context: ["learner", "host"], recap: ["learner"] },
  );
  assert.deepEqual(alikeWarns(fx), []);
});

test("a scene or kit file reading the clock or a random draw is named, and captions.html is left alone", () => {
  const fx = timed({
    hook: "<p>a line</p><script>const a = Date.now(); new Date(); setTimeout(f, 1);</script>",
  });
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "devices.js"), "performance.now()");
  fs.appendFileSync(
    project(fx, "compositions", "captions.html"),
    "Math.random()",
  );
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(warns(r, "clock"), [
    "compositions/hook.html reads Date.now, new Date, setTimeout",
    "kit/devices.js reads performance.now",
  ]);
});
