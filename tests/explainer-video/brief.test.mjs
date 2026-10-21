// The brief through its process door: knobs laid over the defaults into
// <run>/brief.json, echoed one line per knob, a change naming only the stages
// that knob feeds, and the compile stage taking its header from the brief.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SCRIPT } from "./scene-file.mjs";

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
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-brief-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  return { tmp, dir };
}

function node(fx, stage, args = []) {
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, stage), fx.dir, ...args],
    {
      env: {
        PATH: process.env.PATH,
        HOME: path.join(fx.tmp, "home"),
        XDG_CONFIG_HOME: path.join(fx.tmp, "config"),
      },
      encoding: "utf8",
    },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const brief = (fx, args) => node(fx, "brief/brief.mjs", args);
const read = (fx, f) =>
  JSON.parse(fs.readFileSync(path.join(fx.dir, f), "utf8"));

test("a bare brief is the defaults, written to brief.json and echoed one line per knob", () => {
  const fx = fixture();
  const r = brief(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(read(fx, "brief.json"), {
    focus: "the source's main ideas",
    length: 2,
    audience: "a developer new to the source",
    language: "en",
    style: "claude-code",
    voice: "bf_emma",
    aspect: "16:9",
    score: "on",
    must: [],
    avoid: [],
  });
  assert.deepEqual(r.out.trim().split("\n"), [
    "brief focus: the source's main ideas",
    "brief length: 2 min",
    "brief audience: a developer new to the source",
    "brief language: en",
    "brief style: claude-code",
    "brief voice: bf_emma",
    "brief aspect: 16:9",
    "brief score: on",
    "brief must: none",
    "brief avoid: none",
    "brief: written -> brief.json",
  ]);
});

test("a new video's brief makes its run folder", () => {
  const fx = fixture();
  fs.rmSync(fx.dir, { recursive: true });
  const r = brief(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(read(fx, "brief.json").length, 2);
});

test("knobs and lists lay over the defaults, and the project's default style is the style default", () => {
  const fx = fixture();
  const styles = path.join(fx.tmp, "explainers", ".styles");
  fs.mkdirSync(styles);
  fs.copyFileSync(
    path.join(scripts, "..", "styles", "claude-code.json"),
    path.join(styles, "house.json"),
  );
  fs.writeFileSync(path.join(styles, "default"), "house\n");
  const r = brief(fx, [
    "focus=how Ship merges",
    "length=3.5",
    "voice=am_fenrir",
    "must=the local gate",
    "must=Codex review",
    "avoid=pricing",
  ]);
  assert.equal(r.code, 0, r.out + r.err);
  const b = read(fx, "brief.json");
  assert.equal(b.focus, "how Ship merges");
  assert.equal(b.length, 3.5);
  assert.equal(b.voice, "am_fenrir");
  assert.equal(b.style, "house");
  assert.deepEqual(b.must, ["the local gate", "Codex review"]);
  assert.deepEqual(b.avoid, ["pricing"]);
  assert.match(r.out, /^brief must: the local gate; Codex review$/m);
});

test("changing one knob keeps the rest and names only the stages it feeds", () => {
  const fx = fixture();
  const has = (f) => fs.existsSync(path.join(fx.dir, f));
  const stale = () =>
    ["script.json", "check.json"].forEach((f) =>
      fs.writeFileSync(path.join(fx.dir, f), "{}"),
    );
  assert.equal(brief(fx, ["must=the gate"]).code, 0);
  stale();
  let r = brief(fx, ["style=claude-code"]);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^brief: unchanged$/m);
  assert.ok(has("script.json") && has("check.json"));

  // The narrator's rate sets the scene budgets, so the script is checked again.
  r = brief(fx, ["voice=am_fenrir"]);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^brief: voice changed: redo script, voice, render$/m);
  assert.deepEqual(read(fx, "brief.json").must, ["the gate"]);
  // The compiled script carries the narrator, and the rewritten script's fix
  // attempts start again.
  assert.ok(!has("script.json") && !has("check.json"));

  stale();
  r = brief(fx, ["audience=managers"]);
  assert.match(r.out, /^brief: audience changed: redo script, voice, render$/m);
  // The compiled script holds no audience, so it stays.
  assert.ok(has("script.json") && !has("check.json"));
  r = brief(fx, ["length=3", "aspect=16:9", "style=claude-code"]);
  assert.match(
    r.out,
    /^brief: length changed: redo source, script, voice, render$/m,
  );
  r = brief(fx, ["focus=merging", "voice=bf_emma"]);
  assert.match(
    r.out,
    /^brief: focus, voice changed: redo source, script, voice, render$/m,
  );
  // The score is made at render, from the voice's word timings.
  stale();
  r = brief(fx, ["score=off"]);
  assert.match(r.out, /^brief score: off$/m);
  assert.match(r.out, /^brief: score changed: redo render$/m);
  r = brief(fx, ["score=ace-step"]);
  assert.match(r.out, /^brief score: ace-step$/m);
  assert.ok(has("script.json") && has("check.json"));
});

test("length has no upper bound: a long video is the operator's to ask for", () => {
  const fx = fixture();
  for (const minutes of [6, 25]) {
    const r = brief(fx, [`length=${minutes}`]);
    assert.equal(r.code, 0, r.out + r.err);
    assert.equal(read(fx, "brief.json").length, minutes);
  }
});

test("a value this version cannot make is refused and nothing is written", () => {
  const fx = fixture();
  for (const [arg, why] of [
    ["length=0.5", /^brief length 0\.5: a number of minutes, 1 or more$/m],
    ["length=two", /^brief length two: a number of minutes, 1 or more$/m],
    ["language=fr", /^brief language fr: no narrator speaks fr \(en, ar\)$/m],
    [
      "voice=nobody",
      /^brief voice nobody: no en narrator \(bf_emma, am_fenrir, af_heart, elevenlabs-george\)$/m,
    ],
    ["style=nope", /^brief style nope: no style profile nope in /m],
    ["aspect=9:16", /^brief aspect 9:16: this version renders 16:9 only$/m],
    ["focus=", /^brief focus: empty$/m],
    ["score=loud", /^brief score loud: on, off or ace-step$/m],
  ]) {
    const r = brief(fx, [arg]);
    assert.equal(r.code, 1, arg);
    assert.match(r.err, why, arg);
    assert.ok(!fs.existsSync(path.join(fx.dir, "brief.json")), arg);
  }
  for (const arg of ["colour=red", "length"]) {
    const r = brief(fx, [arg]);
    assert.equal(r.code, 2, arg);
    assert.match(r.err, /^usage: node brief\.mjs/m, arg);
  }
});

test("a style the run already copied stays valid after its store drops it", () => {
  const fx = fixture();
  const profile = JSON.parse(
    fs.readFileSync(path.join(scripts, "..", "styles", "claude-code.json")),
  );
  fs.writeFileSync(
    path.join(fx.dir, "style.json"),
    JSON.stringify({ ...profile, name: "gone" }),
  );
  const r = brief(fx, ["style=gone"]);
  assert.equal(r.code, 0, r.err);
  assert.equal(brief(fx, ["audience=managers"]).code, 0);
  assert.equal(read(fx, "brief.json").style, "gone");
});

test("compile takes language, narrator and style from the brief and refuses a header that disagrees", () => {
  const fx = fixture();
  assert.equal(brief(fx, ["voice=bf_emma"]).code, 0);
  fs.writeFileSync(
    path.join(fx.dir, "script.md"),
    SCRIPT.replace(
      /^language: en\nnarrator: am_fenrir\nstyle: claude-code\n/m,
      "",
    ),
  );
  let r = node(fx, "script/compile.mjs");
  assert.equal(r.code, 0, r.err);
  const s = read(fx, "script.json");
  assert.deepEqual(
    [s.language, s.narrator, s.style],
    ["en", "bf_emma", "claude-code"],
  );

  fs.writeFileSync(path.join(fx.dir, "script.md"), SCRIPT);
  r = node(fx, "script/compile.mjs");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: header narrator am_fenrir differs from the brief's voice bf_emma$/m,
  );
});
