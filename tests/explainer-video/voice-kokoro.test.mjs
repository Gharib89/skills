// The voice stage through its process door, part 1: the English voice, its
// cache, QC and the length check.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  SCENES,
  fixture,
  line,
  run,
  synths,
  voice,
  write,
} from "./voice-lib.mjs";

// Seconds of 16-bit mono PCM in a WAV file, read from its header.
function wavSeconds(file) {
  const b = fs.readFileSync(file);
  assert.equal(b.toString("ascii", 0, 4), "RIFF");
  assert.equal(b.toString("ascii", 8, 12), "WAVE");
  const rate = b.readUInt32LE(24);
  return b.readUInt32LE(40) / 2 / rate;
}

test("a first run voices the whole narration in one call and writes a WAV and word timings per scene", () => {
  const fx = fixture();
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(synths(fx).length, 1);
  assert.equal(
    synths(fx)[0].text,
    SCENES.flatMap((s) => s.narration).join(" "),
  );
  assert.match(synths(fx)[0].model, /models\/kokoro-82m@1939ad2a8e41$/);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.narrator, "bf_emma");
  assert.deepEqual(
    timeline.scenes.map((s) => s.id),
    SCENES.map((s) => s.id),
  );
  for (const [i, s] of timeline.scenes.entries()) {
    assert.match(line(r.out, s.id), /voiced/);
    const seconds = wavSeconds(path.join(fx.dir, s.audio));
    assert.ok(Math.abs(seconds - s.duration) < 0.01, `${s.id} duration`);
    const words = SCENES[i].narration.join(" ").split(" ");
    assert.deepEqual(
      s.words.map((w) => w.text),
      words,
    );
    let t = 0;
    for (const w of s.words) {
      assert.ok(w.start >= t && w.end > w.start, JSON.stringify(w));
      t = w.end;
    }
    assert.ok(t <= s.duration);
  }
});

test("changing one scene's text re-voices only that scene; the others are cache hits", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const changed = structuredClone(SCENES);
  changed[1].narration[1] =
    "Then it takes the issue so no other run claims it.";
  write(fx, changed);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "hook"), /: cached ·/);
  assert.match(line(r.out, "context"), /: voiced ·/);
  assert.match(line(r.out, "recap"), /: cached ·/);
  assert.match(r.out, /3 scene\(s\), 1 voiced in 1 call\(s\), 2 cached/);
  const calls = synths(fx);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].text, changed[1].narration.join(" "));
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.scenes[1].words[7].text, "takes");
});

test("a scene whose cached WAV is gone is voiced again, not reported cached", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  fs.rmSync(path.join(fx.dir, timeline.scenes[0].audio));
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "hook"), /: voiced ·/);
  assert.match(line(r.out, "context"), /: cached ·/);
  assert.ok(fs.existsSync(path.join(fx.dir, timeline.scenes[0].audio)));
});

test("a scene with no narration is refused by name before anything is voiced", () => {
  const scenes = structuredClone(SCENES);
  scenes[1].narration = [];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /scene context has no narration/);
  assert.equal(synths(fx).length, 0);
});

// Each misrender the fake can make, the floor it misses, and the value the
// verdict line must carry: worked from the fake's frame layout.
for (const [name, sentence, why] of [
  [
    "a garbled render",
    "This garbled sentence comes out as noise.",
    /recall 0 under 0\.8/,
  ],
  [
    "a looped render",
    "This looped sentence plays its words twice.",
    /precision 0\.5 under 0\.85/,
  ],
  [
    "a dragged render",
    "This sentence reads slowly.",
    /rate \d+(\.\d+)? chars\/s outside 7 to 18/,
  ],
]) {
  test(`voice QC blocks ${name} with the measured value, writes no timeline and caches nothing for it`, () => {
    const scenes = structuredClone(SCENES);
    scenes[2].narration = [sentence];
    const fx = fixture(scenes);
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(line(r.out, "recap"), /· fail: /);
    assert.match(line(r.out, "recap"), why);
    assert.match(line(r.out, "hook"), /· pass$/);
    assert.match(r.out, /^voice QC failed: 1 scene\(s\)/m);
    assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
    const again = run(fx);
    assert.match(line(again.out, "recap"), /: voiced ·/);
    assert.match(line(again.out, "hook"), /: cached ·/);
  });
}

// #725: a failed scene kept no record of what the aligner heard, so the
// misheard word had to be guessed.
test("a failed scene keeps what the aligner heard beside its voice outputs and names it", () => {
  const scenes = structuredClone(SCENES);
  scenes[2].narration = ["This looped sentence plays its words twice."];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  const m = line(r.out, "recap").match(
    /heard: (\.cache\/voice\/\w+\.heard\.txt)$/,
  );
  assert.ok(m, line(r.out, "recap"));
  assert.equal(
    fs.readFileSync(path.join(fx.dir, m[1]), "utf8").trim(),
    "this looped sentence plays its words twice this looped sentence plays its words twice",
  );
});

test("a rerun that fails QC removes the timeline the last pass wrote", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const scenes = structuredClone(SCENES);
  scenes[2].narration = ["This garbled sentence comes out as noise."];
  write(fx, scenes);
  assert.equal(run(fx).code, 1);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
});

test("a rerun refused for its input removes the timeline the last pass wrote", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  write(fx, SCENES, "en", { narrator: "nobody" });
  const r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /no narrator nobody/);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
});

// Five scenes, the i-th of `n[i]` sentences, or each of `n[0]`; the fake voices
// a sentence in about 2.95 s, so four a scene voice about 59 s, six 88.6 s,
// and 4, 4, 4, 3, 3 about 53.5 s.
const long = (...n) =>
  ["one", "two", "three", "four", "five"].map((w, i) => ({
    id: `scene-${w}`,
    narration: new Array(n[i] ?? n[0]).fill(
      `Scene ${w} reads the issue and then writes it.`,
    ),
  }));

test("with a brief, the voiced timeline and the closing hold must land within 10 percent of the brief's length", () => {
  const fx = fixture(long(4));
  fs.writeFileSync(
    path.join(fx.dir, "brief.json"),
    JSON.stringify({
      focus: "the demo",
      length: 1,
      audience: "developers",
      language: "en",
      style: "claude",
      voice: "bf_emma",
      aspect: "16:9",
      score: "on",
      must: [],
      avoid: [],
    }),
  );
  let r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^voice length: pass: the scenes voice /m);
  assert.ok(fs.existsSync(path.join(fx.dir, "voice.json")));

  write(fx, long(6));
  r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^voice length: fail: the scenes voice 88\.6 s \(scene-one 17\.5 s, scene-two 17\.4 s, scene-three 18\.1 s, scene-four 17\.8 s, scene-five 17\.9 s\) and the 1 s hold vs the brief's 60 s ±10%$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));

  // Short of the band by less than the hold: the hold brings it inside.
  write(fx, long(4, 4, 4, 3, 3));
  r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^voice length: pass: the scenes voice 53\.5 s \(scene-one 11\.7 s, scene-two 11\.6 s, scene-three 12\.1 s, scene-four 9\.1 s, scene-five 9\.1 s\) and the 1 s hold vs the brief's 60 s ±10%$/m,
  );
});

test("with no brief, as when voicing a narration alone, no length is checked", () => {
  const fx = fixture(long(6));
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.doesNotMatch(r.out, /^voice length:/m);
});

test("voice on a mistyped run folder says which stage to run and writes nothing", () => {
  const fx = fixture();
  const r = run({ ...fx, dir: path.join(fx.tmp, "typo") });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^voice: no script\.json: run the compile stage first/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, ".gitignore")));
  assert.ok(!fs.existsSync(path.join(fx.tmp, "typo")));
});

test("two scenes with the same narration share one WAV that matches both entries", () => {
  const fx = fixture([SCENES[0], { ...SCENES[0], id: "again" }, SCENES[2]]);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  for (const s of timeline.scenes) {
    const seconds = wavSeconds(path.join(fx.dir, s.audio));
    assert.ok(Math.abs(seconds - s.duration) < 0.01, `${s.id} duration`);
  }
});

test("a narration of function words only passes QC when the transcript matches", () => {
  const scenes = structuredClone(SCENES);
  scenes[1].narration = ["Here we are."];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "context"), /· pass$/);
});
