// The sound kit's gates: every sound but the narration has a licence record in
// sound.json, and the bed sits 15 LU under the voice wherever words play (the
// canned backend's loudness is in fake-backend-sound.mjs); a dropped sound is
// a warning.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { bedLevel } from "../../skills/creative-video/scripts/gates/sound-kit.mjs";
import { gateLine, only, runGates, timed } from "./gates-lib.mjs";
import { exec, project, timing } from "./timing-lib.mjs";

const BED = {
  query: "kitchen ambience",
  level: -28,
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
  assert.equal(gateLine(r, "bed level"), "pass: no bed vs 15 LU");
});

test("a correct mix passes: each sound licensed in the kit, the bed well under the voice, its closest margin logged", () => {
  const fx = withKit(
    { bed: BED, palette: [DING] },
    {
      hook: '<p>a line</p><audio id="ding" src="assets/sounds/ding.ogg" data-sound="0.1"></audio>',
    },
  );
  const r = runGates(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(gateLine(r, "licence"), /^pass: /);
  const closest = gateLine(r, "bed level").match(
    /^pass: (\d+\.\d) LU under the voice at its closest \(window \d+ s\) vs 15 LU$/,
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
  // -16 - (-20 - 28 + 20 log10 0.35) = 41.1, every window alike.
  assert.deepEqual(await level(-28), {
    evidence: [],
    measured: "41.1 LU under the voice at its closest (window 0 s)",
  });
  assert.deepEqual((await level(0)).evidence, [
    "window 0 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 3 s: the bed is 13.1 LU under the voice, under 15 LU",
    "window 6 s: the bed is 13.1 LU under the voice, under 15 LU",
  ]);
  fs.rmSync(proj, { recursive: true });
  assert.deepEqual((await level(-28)).evidence, [
    `${BED.file} is missing: run sound/sounds.mjs`,
  ]);
});

test("a sound with no licence record fails licence, by file", () => {
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
    /^fail: 2 finding\(s\), first: assets\/pop\.wav: no licence record in the kit vs /,
  );
  assert.match(
    r.out,
    /^ {2}assets\/sounds\/bed-1\.mp3: no licence record in the kit$/m,
  );
});

test("a bed too loud fails bed level, naming each window under 15 LU", () => {
  const r = runGates(withKit({ bed: { ...BED, level: 0 } }));
  assert.equal(r.code, 1, r.out + r.err);
  only(r, "bed level");
  assert.match(
    gateLine(r, "bed level"),
    /^fail: \d+ finding\(s\), first: window 0 s: the bed is \d+\.\d LU under the voice, under 15 LU vs 15 LU$/,
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
