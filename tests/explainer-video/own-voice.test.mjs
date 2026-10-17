// Own voice through its process doors: enrollment (own-voice.mjs), the brief
// accepting `own:<name>`, and the voice stage speaking through it. The canned
// backend writes a clip of EXPLAINER_VIDEO_FAKE_CLIP_SECONDS seconds whose
// samples come from the input file's bytes.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

function fixture() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-own-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const input = path.join(tmp, "me.m4a");
  fs.writeFileSync(input, "my voice, take one");
  return { tmp, dir, input, log: path.join(tmp, "calls.jsonl") };
}

function node(fx, stage, args, extra = {}) {
  const r = spawnSync(process.execPath, [path.join(scripts, stage), ...args], {
    env: {
      ...extra,
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CONFIG_HOME: path.join(fx.tmp, "config"),
      XDG_DATA_HOME: path.join(fx.tmp, "data"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const FEMALE = ["--gender", "female", "--consent", "I am Maya and I agree."];
const enroll = (fx, name = "maya", extra = {}, args = FEMALE) =>
  node(fx, "voice/own-voice.mjs", ["enroll", name, fx.input, ...args], extra);
const remove = (fx, name = "maya") =>
  node(fx, "voice/own-voice.mjs", ["remove", name]);
const brief = (fx, args) => node(fx, "brief/brief.mjs", [fx.dir, ...args]);
const voices = (fx) => path.join(fx.tmp, "data", "explainer-video", "voices");
const consent = (fx, name = "maya") =>
  JSON.parse(
    fs.readFileSync(path.join(voices(fx), name, "consent.json"), "utf8"),
  );

test("enroll writes a 24 kHz mono 16-bit clip and a consent record naming the voice, statement, hash and length", () => {
  const fx = fixture();
  const r = enroll(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const dir = path.join(voices(fx), "maya");
  assert.equal(
    r.out.trim(),
    `own-voice maya: enrolled 12 s, 24 kHz mono, consent recorded at ${dir}`,
  );
  const wav = fs.readFileSync(path.join(dir, "clip.wav"));
  assert.equal(wav.toString("ascii", 0, 4), "RIFF");
  assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.readUInt32LE(24), 24000);
  assert.equal(wav.readUInt16LE(34), 16);
  const c = consent(fx);
  assert.deepEqual(Object.keys(c).sort(), [
    "clip",
    "date",
    "gender",
    "name",
    "seconds",
    "statement",
  ]);
  assert.equal(c.name, "maya");
  assert.equal(c.gender, "female");
  assert.equal(c.statement, "I am Maya and I agree.");
  assert.equal(c.seconds, 12);
  assert.equal(c.clip, crypto.createHash("sha256").update(wav).digest("hex"));
  assert.ok(!Number.isNaN(Date.parse(c.date)));
  assert.deepEqual(fs.readdirSync(dir).sort(), ["clip.wav", "consent.json"]);
});

for (const [seconds, ok] of [
  ["5", false],
  ["31", false],
  ["8", true],
  ["30", true],
]) {
  test(`a ${seconds} s clip is ${ok ? "enrolled" : "refused with its length, leaving nothing on disk"}`, () => {
    const fx = fixture();
    const r = enroll(fx, "maya", {
      EXPLAINER_VIDEO_FAKE_CLIP_SECONDS: seconds,
    });
    if (ok) return assert.equal(r.code, 0, r.out + r.err);
    assert.equal(r.code, 1, r.out + r.err);
    assert.equal(
      r.err.trim(),
      `own-voice: the clip is ${seconds} s; enroll 8 to 30 s of one speaker`,
    );
    assert.ok(!fs.existsSync(voices(fx)) || !fs.readdirSync(voices(fx)).length);
  });
}

test("remove deletes the clip and the consent record; an unknown name exits 1", () => {
  const fx = fixture();
  assert.equal(enroll(fx).code, 0);
  const r = remove(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "own-voice maya: removed clip and consent record");
  assert.ok(!fs.existsSync(path.join(voices(fx), "maya")));
  const again = remove(fx);
  assert.equal(again.code, 1);
  assert.equal(again.err.trim(), "own-voice: no enrolled voice maya");
});

test("a bad name, a missing consent statement or a bad gender is a usage error", () => {
  const fx = fixture();
  for (const [name, args] of [
    ["Maya", FEMALE],
    ["-maya", FEMALE],
    ["maya", ["--gender", "female"]],
    ["maya", ["--gender", "other", "--consent", "yes"]],
    ["maya", ["--consent", "yes"]],
  ]) {
    const r = enroll(fx, name, {}, args);
    assert.equal(r.code, 2, `${name} ${args}: ${r.out + r.err}`);
    assert.match(r.err, /^usage: node own-voice\.mjs/m);
  }
  assert.equal(node(fx, "voice/own-voice.mjs", []).code, 2);
});

test("the brief takes own:<name> for Arabic once enrolled, and refuses it before, after remove, and for English", () => {
  const fx = fixture();
  let r = brief(fx, ["language=ar", "voice=own:maya"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /own:maya/);
  assert.match(r.err, /or own:<name> for an enrolled own voice/);
  assert.equal(enroll(fx).code, 0);
  r = brief(fx, ["language=ar", "voice=own:maya"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(
    JSON.parse(fs.readFileSync(path.join(fx.dir, "brief.json"), "utf8")).voice,
    "own:maya",
  );
  r = brief(fx, ["language=en", "voice=own:maya"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /own:maya/);
  assert.doesNotMatch(r.err, /own:<name>/);
  assert.equal(remove(fx).code, 0);
  r = brief(fx, ["language=ar", "voice=own:maya"]);
  assert.equal(r.code, 1, r.out + r.err);
});

const AR_SCENES = [
  {
    id: "hook",
    narration: ["شيب بياخد مهمة واحدة ويوصلها لحد pull request متراجع."],
  },
  {
    id: "recap",
    narration: ["كل تغيير بيدخل من خلال review قبل الـ merge."],
  },
];
const KEY = { GEMINI_API_KEY: "test-key" };
const script = (fx) =>
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({
      language: "ar",
      narrator: "own:maya",
      scenes: AR_SCENES,
    }),
  );
const voice = (fx, extra = KEY) => node(fx, "voice/voice.mjs", [fx.dir], extra);
const synths = (fx) =>
  fs
    .readFileSync(fx.log, "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l))
    .filter((c) => c.call === "synthesize");

test("the voice stage speaks an Arabic script through the own voice, caches by the clip, and refuses once it is removed", () => {
  const fx = fixture();
  assert.equal(enroll(fx).code, 0);
  script(fx);
  let r = voice(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const calls = synths(fx);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].backend, "own");
  assert.equal(calls[0].base, "ar-eg-csagent-2");
  assert.equal(calls[0].clipHash, consent(fx).clip);
  assert.equal(
    JSON.parse(fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"))
      .narrator,
    "own:maya",
  );
  r = voice(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(synths(fx).length, 1);
  assert.match(r.out, /2 scene\(s\), 0 voiced in 0 call\(s\), 2 cached/);
  // A different clip under the same name is a different voice.
  fs.writeFileSync(fx.input, "my voice, take two");
  assert.equal(enroll(fx).code, 0);
  r = voice(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /2 scene\(s\), 2 voiced in 1 call\(s\), 0 cached/);
  assert.equal(synths(fx).length, 2);
  assert.equal(remove(fx).code, 0);
  r = voice(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: own voice maya is not enrolled with a consent record for its clip: enroll it \(own-voice\.mjs enroll\) or choose another narrator in the brief$/m,
  );
  assert.equal(synths(fx).length, 2);
});

test("an own voice with no GEMINI_API_KEY is refused with the Gemini message naming it, before any synthesis", () => {
  const fx = fixture();
  assert.equal(enroll(fx).code, 0);
  script(fx);
  const r = voice(fx, {});
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: narrator own:maya needs GEMINI_API_KEY: get a free key at https:\/\/aistudio\.google\.com\/apikey, or choose another narrator in the brief$/m,
  );
  assert.ok(!fs.existsSync(fx.log) || !synths(fx).length);
});

test("a clip changed after enrollment has no consent record for it: the voice stage refuses before any synthesis", () => {
  const fx = fixture();
  assert.equal(enroll(fx).code, 0);
  script(fx);
  fs.appendFileSync(path.join(voices(fx), "maya", "clip.wav"), "another voice");
  const r = voice(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: own voice maya is not enrolled with a consent record for its clip: /m,
  );
  assert.ok(!fs.existsSync(fx.log) || !synths(fx).length);
});

const INTEL_MAC = { EXPLAINER_VIDEO_FAKE_PLATFORM: "darwin/x64/14.5" };
const TORCH_26 =
  "unavailable on darwin/x64 14.5: no torch 2.6 wheel for Intel macOS; torch's last is 2.2.2";

test("on Intel macOS enroll is refused with the own-voice row's reason before any clip or consent is written", () => {
  const fx = fixture();
  const r = enroll(fx, "maya", INTEL_MAC);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(r.err.trim(), `own-voice: ${TORCH_26}`);
  assert.ok(!fs.existsSync(voices(fx)), "nothing written");
  assert.ok(!fs.existsSync(fx.log), "no clip was made");
});

test("on Intel macOS the brief refuses an own voice and score=ace-step, each naming the platform and reason; score on and off still pass", () => {
  const fx = fixture();
  assert.equal(enroll(fx).code, 0);
  const onMac = (args) =>
    node(fx, "brief/brief.mjs", [fx.dir, ...args], INTEL_MAC);
  let r = onMac(["language=ar", "voice=own:maya"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(r.err.trim(), `brief voice own:maya: ${TORCH_26}`);
  r = onMac(["score=ace-step"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    r.err.trim(),
    "brief score ace-step: unavailable on darwin/x64 14.5: no torch 2.10 or torchcodec 0.10 wheel for Intel macOS; torch's last is 2.2.2",
  );
  for (const s of ["on", "off"]) assert.equal(onMac([`score=${s}`]).code, 0, s);
  assert.equal(brief(fx, ["score=ace-step"]).code, 0, "linux takes it");
});
