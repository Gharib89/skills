// The voice stage with a cast: script.json's `roles` name who speaks each
// sentence, <run>/project/kit/cast.json each role's voice and style.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, line, run, synths, write, writeCast } from "./voice-lib.mjs";

const SCENES = [
  {
    id: "hook",
    narration: [
      "Ship drives one issue to a merged pull request.",
      "Why not merge it by hand?",
      "Because the review comes first.",
    ],
    roles: [null, "learner", "narrator"],
  },
  {
    id: "recap",
    narration: ["Every change lands through a reviewed pull request."],
  },
];

const CAST = {
  narrator: { voices: { en: "af_heart" } },
  learner: { voices: { en: "am_fenrir", ar: "ar-eg-commercial-11" } },
};

const cast = (fx, value = CAST) => writeCast(fx, value);

const voiceJson = (fx) =>
  JSON.parse(fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"));

test("each run of sentences is voiced by its role's narrator in order, and voice.json names each sentence's role", () => {
  const fx = fixture(SCENES);
  cast(fx);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    synths(fx).map((c) => [c.voice, c.text]),
    [
      ["af_heart", "Ship drives one issue to a merged pull request."],
      ["am_fenrir", "Why not merge it by hand?"],
      [
        "af_heart",
        "Because the review comes first. Every change lands through a reviewed pull request.",
      ],
    ],
  );
  const v = voiceJson(fx);
  assert.deepEqual(
    v.scenes.map((s) => s.roles),
    [["narrator", "learner", "narrator"], ["narrator"]],
  );
  assert.deepEqual(
    v.scenes[0].words.map((w) => w.text),
    SCENES[0].narration.join(" ").split(" "),
  );
  assert.equal(v.narrator, "af_heart");
});

test("a scene re-voices when a run's voice or style changes, and stays cached otherwise", () => {
  const fx = fixture(SCENES);
  cast(fx);
  assert.equal(run(fx).code, 0);
  const same = run(fx);
  assert.match(line(same.out, "hook"), /: cached ·/);
  cast(fx, { ...CAST, learner: { voices: { en: "bf_emma" } } });
  const voice = run(fx);
  assert.equal(voice.code, 0, voice.out + voice.err);
  assert.match(line(voice.out, "hook"), /: voiced ·/);
  assert.match(line(voice.out, "recap"), /: cached ·/);
  assert.equal(synths(fx).at(-2).voice, "bf_emma");
  cast(fx, {
    ...CAST,
    learner: { voices: { en: "bf_emma" }, style: "an eager student" },
  });
  assert.match(line(run(fx).out, "hook"), /: voiced ·/);
});

test("a one-voice scene keys its cache as before the cast, so a cast naming the same narrator keeps it", () => {
  const fx = fixture([SCENES[1]]);
  assert.equal(run(fx).code, 0);
  cast(fx, { narrator: { voices: { en: "af_heart" } } });
  const r = run(fx);
  assert.match(line(r.out, "recap"), /: cached ·/);
  assert.deepEqual(voiceJson(fx).scenes[0].roles, ["narrator"]);
});

test("roles that do not fit the narration or the cast are refused before anything is voiced", () => {
  const refused = (scenes, value) => {
    const fx = fixture(scenes);
    if (value) cast(fx, value);
    const r = run(fx);
    assert.equal(r.code, 1, r.out);
    assert.equal(synths(fx).length, 0);
    assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
    return r.err.trim();
  };
  const short = [{ ...SCENES[0], roles: ["learner"] }];
  assert.equal(
    refused(short, CAST),
    "voice: script.json: scene hook has 3 sentence(s), 1 role(s)",
  );
  assert.equal(
    refused(SCENES),
    "voice: script.json: scene hook names role learner, and project/kit/cast.json is missing",
  );
  assert.equal(
    refused(SCENES, { narrator: CAST.narrator }),
    "voice: script.json: scene hook names role learner, which project/kit/cast.json does not cast",
  );
  assert.equal(
    refused(SCENES, {
      ...CAST,
      learner: { voices: { ar: "ar-eg-csagent-2" } },
    }),
    "voice: project/kit/cast.json: role learner has no en voice",
  );
  assert.equal(
    refused(SCENES, { ...CAST, learner: { voices: { en: "nobody" } } }),
    "voice: project/kit/cast.json: role learner's voice nobody is no en narrator in narrators.json",
  );
  assert.match(
    refused(SCENES, { learner: { voices: "am_fenrir" } }),
    /^voice: project\/kit\/cast\.json: learner\.voices is not an object$/,
  );
});

test("a script with no roles and no cast voices as one narrator, every sentence its role", () => {
  const fx = fixture([SCENES[1]]);
  write(fx, [SCENES[1]], "en", { narrator: "am_fenrir" });
  assert.equal(run(fx).code, 0);
  assert.deepEqual(
    synths(fx).map((c) => c.voice),
    ["am_fenrir"],
  );
  assert.deepEqual(voiceJson(fx).scenes[0].roles, ["narrator"]);
});

test("a cast narrator with no key is refused naming cast.json as where to choose another", () => {
  const fx = fixture(SCENES);
  cast(fx, { learner: { voices: { en: "elevenlabs-george" } } });
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: narrator elevenlabs-george needs ELEVENLABS_API_KEY: get a free key at \S+, or choose another narrator in project\/kit\/cast\.json$/m,
  );
  assert.equal(synths(fx).length, 0);
});

test("a quota stop with a cast names cast.json beside script.json as where to choose another narrator", () => {
  const fx = fixture(SCENES);
  cast(fx, { learner: { voices: { en: "elevenlabs-george" } } });
  const r = run(fx, {
    ELEVENLABS_API_KEY: "fake",
    CREATIVE_VIDEO_FAKE_QUOTA: "0",
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: ElevenLabs quota reached .*; or choose another narrator in script\.json or project\/kit\/cast\.json$/m,
  );
});
