// Every stage refuses a malformed run-folder JSON file with one named line:
// each file a stage reads, replaced in turn by `{}`, `null` and `[null]`, gives
// exit 1 and one `<stage>: ` line on stderr naming the file, never a TypeError,
// a stack or a silent exit 0.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fixture as checked } from "./check-lib.mjs";
import { fixture as rendered, render, skill } from "./render-lib.mjs";
import { fixture as parted, plan, writePlan } from "./parts-lib.mjs";

const BAD = ["{}", "null", "[null]"];

// One run folder every stage below passes on: check-lib's brief, pack and
// support verdicts on render-lib's machine, compiled, voiced and delivered.
const c = checked();
const fx = rendered(fs.readFileSync(path.join(c.dir, "script.md"), "utf8"));
for (const f of ["brief.json", "excerpts.json", "support.json"])
  fs.copyFileSync(path.join(c.dir, f), path.join(fx.dir, f));
fs.cpSync(path.join(c.dir, "snapshots"), path.join(fx.dir, "snapshots"), {
  recursive: true,
});
const r = render(fx);
assert.equal(r.code, 0, r.out + r.err);
const s = run(fx.dir, "gates/samples.mjs", [], fx.env);
assert.equal(s.code, 0, s.out + s.err);

// A parts run folder: a 12-minute brief, its pack and a plan of three parts.
const p = parted();
writePlan(p, plan([4, 4, 4]));
p.env = {
  PATH: process.env.PATH,
  HOME: path.join(p.tmp, "home"),
  XDG_CONFIG_HOME: path.join(p.tmp, "config"),
};

// Each stage: its stderr prefix, its command, its folder and the files it reads.
const STAGES = [
  ["voice", "voice/voice.mjs", [], fx, ["script.json", "brief.json"]],
  [
    "render",
    "render/render.mjs",
    [],
    fx,
    ["script.json", "voice.json", "brief.json", "manifest.json"],
  ],
  [
    "gates",
    "gates/gates.mjs",
    [],
    fx,
    ["script.json", "timeline.json", "score.json", "excerpts.json"],
  ],
  ["samples", "gates/samples.mjs", [], fx, ["script.json", "timeline.json"]],
  [
    "board",
    "storyboard/board.mjs",
    ["build"],
    fx,
    [
      "script.json",
      "voice.json",
      "stills.json",
      "timeline.json",
      "brief.json",
      "excerpts.json",
      "manifest.json",
    ],
  ],
  [
    "script",
    "script/check.mjs",
    [],
    fx,
    ["script.json", "brief.json", "excerpts.json", "support.json"],
  ],
  ["compile", "script/compile.mjs", [], fx, ["brief.json"]],
  [
    "parts",
    "parts/parts.mjs",
    ["check"],
    p,
    ["brief.json", "excerpts.json", "parts.json"],
  ],
  ["parts", "parts/parts.mjs", ["offer"], p, ["brief.json"]],
];

function run(dir, script, args, env) {
  const x = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", script), dir, ...args],
    { env, encoding: "utf8" },
  );
  return { code: x.status, out: x.stdout, err: x.stderr };
}

// The run folder's own JSON files, put back after each case with their
// times, which the board reads: a stage may remove one (voice drops voice.json
// first) or write one before it refuses.
const saved = (dir) =>
  new Map(
    fs
      .readdirSync(dir)
      .filter((f) => f.endsWith(".json"))
      .map((f) => [
        f,
        [fs.readFileSync(path.join(dir, f)), fs.statSync(path.join(dir, f))],
      ]),
  );
const restore = (dir, files) => {
  for (const f of fs.readdirSync(dir))
    if (f.endsWith(".json") && !files.has(f)) fs.rmSync(path.join(dir, f));
  for (const [f, [body, { atime, mtime }]] of files) {
    fs.writeFileSync(path.join(dir, f), body);
    fs.utimesSync(path.join(dir, f), atime, mtime);
  }
};

for (const [name, script, args, at, files] of STAGES) {
  const label = [script, ...args].join(" ");
  const held = saved(at.dir);

  test(`${label} passes on the well-formed run folder`, () => {
    const x = run(at.dir, script, args, at.env);
    restore(at.dir, held);
    assert.equal(x.code, 0, x.out + x.err);
  });

  for (const file of files)
    for (const bad of BAD)
      test(`${label} refuses ${file} as ${bad} by name`, () => {
        fs.writeFileSync(path.join(at.dir, file), bad);
        const x = run(at.dir, script, args, at.env);
        restore(at.dir, held);
        const lines = x.err.trim().split("\n");
        assert.equal(x.code, 1, `exit ${x.code}\n${x.out}${x.err}`);
        assert.doesNotMatch(x.err, /TypeError|^\s+at /m, x.err);
        assert.deepEqual(
          lines.filter((l) => l.startsWith(`${name}: `)),
          lines,
          x.err,
        );
        assert.equal(lines.length, 1, x.err);
        assert.match(lines[0], new RegExp(`\\b${file.replace(".", "\\.")}\\b`));
      });
}
