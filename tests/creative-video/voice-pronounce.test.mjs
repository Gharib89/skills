// The spoken-form pass: the voice stage sends an acronym or command name to the
// narrator as its spoken form (built-in list, <run>/project/kit/pronounce.json
// over it), keys the cache on that form and holds QC to it, while voice.json
// keeps the written words and one timing each.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spokenForm } from "../../skills/creative-video/scripts/lib/pronounce.mjs";
import { fixture, line, run, synths, temps } from "./voice-lib.mjs";

const SCENES = [
  {
    id: "list",
    narration: ["Run aws, then check the API."],
  },
  { id: "plain", narration: ["Nothing here needs spelling out."] },
];

const writeMap = (fx, map) => {
  fs.mkdirSync(path.join(fx.dir, "project", "kit"), { recursive: true });
  fs.writeFileSync(
    path.join(fx.dir, "project", "kit", "pronounce.json"),
    typeof map === "string" ? map : JSON.stringify(map),
  );
};
const voiceJson = (fx) =>
  JSON.parse(fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"));

test("a command name or acronym is sent to the narrator as its letters, in lower or upper case, punctuation kept", () => {
  const fx = fixture(SCENES);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    synths(fx).map((c) => c.text),
    ["Run A W S, then check the A P I. Nothing here needs spelling out."],
  );
});

test("voice.json and QC keep the written words: one timed word per written word, its span the letters' span", () => {
  const fx = fixture(SCENES);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "list"), / · pass$/);
  const [list] = voiceJson(fx).scenes;
  assert.deepEqual(
    list.words.map((w) => w.text),
    ["Run", "aws,", "then", "check", "the", "API."],
  );
  const aws = list.words[1];
  assert.ok(aws.end > aws.start, JSON.stringify(aws));
  assert.ok(aws.start >= list.words[0].end - 1e-6);
  assert.ok(list.words[2].start >= aws.end - 1e-6);
});

test("a project map overrides the built-in list, and an edit re-voices only the scenes it changes", () => {
  const fx = fixture(SCENES);
  assert.equal(run(fx).code, 0);
  const again = run(fx);
  assert.match(line(again.out, "list"), /^voice list: cached/);

  writeMap(fx, { aws: "ay double you ess" });
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "list"), /^voice list: voiced/);
  assert.match(line(r.out, "plain"), /^voice plain: cached/);
  assert.equal(
    synths(fx).at(-1).text,
    "Run ay double you ess, then check the A P I.",
  );
  assert.deepEqual(
    voiceJson(fx).scenes[0].words.map((w) => w.text),
    ["Run", "aws,", "then", "check", "the", "API."],
  );
});

test("a spoken form is only the English narrators': another language's narration passes through", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-pron-"));
  temps.push(dir);
  assert.equal(spokenForm(dir, "en")("Run aws now."), "Run A W S now.");
  assert.equal(spokenForm(dir, "ar")("Run aws now."), "Run aws now.");
});

test("a malformed map is refused before any synthesis", () => {
  const fx = fixture(SCENES);
  writeMap(fx, { "a w s": "A W S" });
  let r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /pronounce\.json: "a w s" is more than one word/);
  writeMap(fx, "{");
  r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /pronounce\.json: is not valid JSON/);
  assert.deepEqual(synths(fx), []);
});
