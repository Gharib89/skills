// The sound kit's gates: every sound but the narration has a licence record in
// sound.json, and the bed sits 15 LU under the voice wherever words play (the
// canned backend's loudness is in fake-backend-sound.mjs); a dropped sound is
// a warning.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  bedLevel,
  effectLevel,
} from "../../skills/creative-video/scripts/gates/sound-kit.mjs";
import { EFFECT_GAIN } from "../../skills/creative-video/scripts/lib/kit.mjs";
import { bedVolume } from "../../skills/creative-video/scripts/render/bed.mjs";
import { DUCK } from "../../skills/creative-video/scripts/render/bed.mjs";
import { gateLine, only, runGates, timed } from "./gates-lib.mjs";
import { exec, project, timing } from "./timing-lib.mjs";

const BED = {
  query: "kitchen ambience",
  level: -7,
  source: "openverse:bed-1",
  file: "assets/sounds/bed-1.mp3",
  licence: "CC0-1.0",
};
const DING = {
  event: "ticket",
  query: "bell ding",
  source: "kenney:rpg-audio/bell1.ogg",
  file: "assets/sounds/ding.ogg",
  licence: "CC0-1.0",
};

// A timed run folder with `kit` as its sound.json, each sound's file in the
// project, timed again so the root holds the bed.
function withKit(kit, bodies) {
  const fx = timed(bodies);
  fs.mkdirSync(project(fx, "assets", "sounds"), { recursive: true });
  for (const s of [kit.bed, ...(kit.palette ?? [])].filter(Boolean))
    fs.writeFileSync(project(fx, s.file), "sound");
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "sound.json"), JSON.stringify(kit));
  assert.equal(exec(timing, fx).code, 0);
  return fx;
}

test("a project with no sounds passes licence and bed level", () => {
  const r = runGates(timed());
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(
    gateLine(r, "licence"),
    "pass: 0 finding(s) vs every <audio> but the narration has a licence record in sound.json",
  );
  assert.equal(gateLine(r, "bed level"), "pass: no bed vs 15 to 20 LU");
});

test("a correct mix passes: each sound licensed in the kit, the bed well under the voice, its closest margin logged", () => {
  const fx = withKit(
    { bed: BED, palette: [DING] },
    {
      hook: `<p>a line</p><audio id="ding" src="assets/sounds/ding.ogg" data-sound="0.1" data-volume="${bedVolume(EFFECT_GAIN)}"></audio>`,
    },
  );
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(gateLine(r, "licence"), /^pass: /);
  const closest = gateLine(r, "bed level").match(
    /^pass: (\d+\.\d) LU under the voice at its closest \(window \d+ s\) vs 15 to 20 LU$/,
  );
  assert.ok(closest && +closest[1] >= 15, r.out);
});

test("the bed's margin is the voice's loudness less the bed file's moved by its level and the lane", async () => {
  const proj = fs.mkdtempSync(path.join(os.tmpdir(), "creative-bed-"));
  fs.mkdirSync(path.join(proj, "assets", "sounds"), { recursive: true });
  fs.writeFileSync(path.join(proj, BED.file), "bed");
  // Words every 0.5 s across the 9 s, so the bed is ducked throughout.
  const words = [...Array(18)].map((_, i) => ({
    text: "w",
    start: i / 2,
    end: i / 2 + 0.45,
  }));
  const timeline = {
    total: 9,
    scenes: [{ id: "one", start: 0, duration: 9, words }],
  };
  const backend = {
    shortTerm: async (f, seconds) =>
      [...Array(seconds * 10)].map((_, i) => [
        (i + 1) / 10,
        f.endsWith("narration.wav") ? -16 : -20,
      ]),
  };
  const level = (level) =>
    bedLevel({ proj, timeline, kit: { bed: { ...BED, level } }, backend });
  // -16 - (-20 - 5 + 20 log10 0.35) = 18.1, every window alike.
  assert.deepEqual(await level(-5), {
    evidence: [],
    measured: "18.1 LU under the voice at its closest (window 0 s)",
  });
  // 41.1 LU under the voice is out of earshot: over the ceiling, and the
  // finding names the raise that brings the closest window into the band.
  assert.deepEqual(await level(-28), {
    evidence: [
      "window 0 s: the bed is 41.1 LU under the voice even at its closest, over 20 LU: raise its level by 21.1 to 26.1 dB",
    ],
    measured: "41.1 LU under the voice at its closest (window 0 s)",
  });
  assert.equal((await level(-6.8)).evidence.length, 0);
  assert.equal((await level(-6.9)).evidence.length, 1);
  assert.deepEqual((await level(0)).evidence, [
    "window 0 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 3 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 6 s: the bed is 13.1 LU under the voice, under 15 LU",
  ]);
  fs.rmSync(proj, { recursive: true });
  assert.deepEqual((await level(-5)).evidence, [
    `${BED.file} is missing: run sound/sounds.mjs`,
  ]);
});

test("a short last window is judged over its own length, and a margin of exactly 15 LU passes", async () => {
  const proj = fs.mkdtempSync(path.join(os.tmpdir(), "creative-bed-"));
  fs.mkdirSync(path.join(proj, "assets", "sounds"), { recursive: true });
  fs.writeFileSync(path.join(proj, BED.file), "bed");
  // 10 s of words every 0.5 s: three 3 s windows and a last one of 1 s.
  const words = [...Array(20)].map((_, i) => ({
    text: "w",
    start: i / 2,
    end: i / 2 + 0.45,
  }));
  const timeline = {
    total: 10,
    scenes: [{ id: "one", start: 0, duration: 10, words }],
  };
  const backend = (bed) => ({
    shortTerm: async (f, seconds) =>
      [...Array(seconds * 10)].map((_, i) => [
        (i + 1) / 10,
        f.endsWith("narration.wav") ? -16 : bed,
      ]),
  });
  const judge = (level, bed) =>
    bedLevel({
      proj,
      timeline,
      kit: { bed: { ...BED, level } },
      backend: backend(bed),
    });
  assert.deepEqual((await judge(0, -20)).evidence, [
    "window 0 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 3 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 6 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 9 s: the bed is 13.1 LU under the voice, under 15 LU",
  ]);
  // A level that cancels the ducked lane's power mean, summed as the gate
  // sums it, leaves the margin the voice less the bed: -16 - -31 = 15.
  let power = 0;
  for (let i = 0; i < 30; i++) power += DUCK ** 2;
  const unity = -10 * Math.log10(power / 30);
  assert.deepEqual(await judge(unity, -31), {
    evidence: [],
    measured: "15.0 LU under the voice at its closest (window 0 s)",
  });
  assert.equal((await judge(unity, -30.9)).evidence.length, 4);
  fs.rmSync(proj, { recursive: true });
});

test("a sound with no licence record fails licence, by file, naming how to give it one", () => {
  const fx = withKit(
    { bed: { ...BED, licence: "" }, palette: [DING] },
    {
      context:
        '<p>a line</p><audio id="pop" src="./assets/pop.wav" data-sound="0.1"></audio>',
    },
  );
  const r = runGates(fx);
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "licence");
  assert.match(
    gateLine(r, "licence"),
    /^fail: 2 finding\(s\), first: assets\/pop\.wav: no licence record in sound\.json; play a sound\.json file, or add it there and run sound\/sounds\.mjs vs /,
  );
  assert.match(
    r.out,
    /^ {2}assets\/sounds\/bed-1\.mp3: no licence record in sound\.json; play a sound\.json file, or add it there and run sound\/sounds\.mjs$/m,
  );
});

test("a bed too loud fails bed level, naming each window under 15 LU", () => {
  const r = runGates(withKit({ bed: { ...BED, level: 0 } }));
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "bed level");
  assert.match(
    gateLine(r, "bed level"),
    /^fail: \d+ finding\(s\), first: window 0 s: the bed is \d+\.\d LU under the voice, under 15 LU vs 15 to 20 LU$/,
  );
});

test("each dropped sound is a warning", () => {
  const r = runGates(
    withKit({
      palette: [],
      dropped: [{ event: "ticket", query: "bell ding", why: "found nowhere" }],
    }),
  );
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^warn dropped sound: ticket: found nowhere$/m);
});

// The canned backend's voice is -16 LUFS and any other file -20, so an effect
// at full volume is 4 LU under the voice and one at the default gain 22.
const QUIET = bedVolume(EFFECT_GAIN);
const play = (volume) =>
  `<p>a line</p><audio id="ding" src="assets/sounds/ding.ogg" data-sound="0.1"${volume === undefined ? "" : ` data-volume="${volume}"`}></audio>`;

test("an effect at its gain passes effect level, its closest margin logged", () => {
  const r = runGates(withKit({ palette: [DING] }, { hook: play(QUIET) }));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    gateLine(r, "effect level"),
    /^pass: 22\.0 LU under the voice at its closest \(hook's ding at 0\.1 s\) vs 6 LU$/,
  );
});

test("an effect left at full volume fails effect level, naming the volume that passes", () => {
  const r = runGates(withKit({ palette: [DING] }, { hook: play() }));
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "effect level");
  assert.match(
    gateLine(r, "effect level"),
    /^fail: 1 finding\(s\), first: hook: <audio id="ding"> \(assets\/sounds\/ding\.ogg\) is 4\.0 LU under the voice at 0\.1 s, under 6 LU: set its data-volume to 0\.794 or lower vs 6 LU$/,
  );
});

test("a project with no palette sound passes effect level as no effect", () => {
  const r = runGates(withKit({ bed: BED }));
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(gateLine(r, "effect level"), "pass: no effect vs 6 LU");
});

test("an effect's margin is the voice's loudness in its 3 s window less the effect file's moved by its volume, a margin of exactly 6 LU passing", async () => {
  const proj = fs.mkdtempSync(path.join(os.tmpdir(), "creative-effect-"));
  fs.mkdirSync(path.join(proj, "assets", "sounds"), { recursive: true });
  fs.writeFileSync(path.join(proj, DING.file), "ding");
  const timeline = {
    total: 9,
    scenes: [{ id: "one", start: 2, duration: 7, words: [] }],
  };
  // The voice sits at -16 for 3 s after each 3 s mark, silent before 3 s.
  const backend = {
    shortTerm: async (f, seconds) =>
      [...Array(Math.round(seconds * 10))].map((_, i) => [
        (i + 1) / 10,
        f.endsWith("narration.wav")
          ? (i + 1) / 10 <= 6
            ? -Infinity
            : -16
          : -10,
      ]),
  };
  const judge = (volume, start = 7, authored = null) =>
    effectLevel({
      proj,
      timeline,
      kit: { palette: [DING] },
      events: {
        one: {
          tweens: [],
          sounds: [{ id: "d", start, authored, src: DING.file, volume }],
        },
      },
      backend,
    });
  // Created at 7 s of the video: the window 6 s to 9 s, the voice -16, the
  // effect -10 + 20 log10 0.5 = -16, a margin of 0.
  assert.deepEqual((await judge(0.5)).evidence, [
    'one: <audio id="d"> (assets/sounds/ding.ogg) is 0.0 LU under the voice at 7 s, under 6 LU: set its data-volume to 0.251 or lower',
  ]);
  const exact = 10 ** (-12 / 20);
  assert.deepEqual((await judge(exact)).evidence, []);
  assert.equal((await judge(exact * 1.01)).evidence.length, 1);
  // Written in its scene file at 1 s (scene seconds, so 3 s of the video), the
  // window 3 s to 6 s holds no voice: nothing to judge it against.
  assert.deepEqual(await judge(1, 1, 1), {
    evidence: [],
    measured: "no effect plays where the voice does",
  });
  // A data-volume outside 0 to 1, or no number, would pass as NaN: it is a
  // finding, wherever the voice is silent too.
  for (const bad of [NaN, -0.5, 1.5])
    assert.deepEqual((await judge(bad)).evidence, [
      'one: <audio id="d"> has a data-volume that is no number from 0 to 1: set one',
    ]);
  assert.equal((await judge(NaN, 1, 1)).evidence.length, 1);
  fs.rmSync(proj, { recursive: true });
});
