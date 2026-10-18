// Shared fixtures of the gates tests: a temp machine, the stage and render
// runners and the red and green assertions.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { judged } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const skill = path.join(here, "..", "..", "skills", "explainer-video");

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine as render-lib.mjs lays it out.
export function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-gates-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CONFIG_HOME: path.join(tmp, "config"),
    XDG_DATA_HOME: path.join(tmp, "data"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    XDG_VIDEOS_DIR: path.join(tmp, "videos"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  const dirs = userDirs({ platform: "linux", env, home: env.HOME });
  for (const r of catalogue().filter((r) =>
    ["npm", "chrome", "font"].includes(r.kind),
  )) {
    const d = dest(r, dirs);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
    for (const f of r.files ?? [])
      fs.writeFileSync(path.join(d, `${f}.woff2`), "woff2");
  }
  const gsap = path.join(dest({ kind: "npm" }, dirs), "node_modules", "gsap");
  fs.mkdirSync(path.join(gsap, "dist"), { recursive: true });
  fs.writeFileSync(path.join(gsap, "dist", "gsap.min.js"), "/* gsap */");
  const dir = path.join(tmp, "proj", "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), text);
  return { tmp, dir, env, dirs, log: env.EXPLAINER_VIDEO_FAKE_LOG };
}

export function stage(fx, script, extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", script), fx.dir],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

// The script written, compiled and voiced, then rendered, a clean critic round
// taken when the critic alone holds the render.
export function render(fx, text, extra) {
  if (text) fs.writeFileSync(path.join(fx.dir, "script.md"), text);
  for (const s of ["script/compile.mjs", "voice/voice.mjs"]) {
    const r = stage(fx, s);
    assert.equal(r.code, 0, `${s}: ${r.out}${r.err}`);
  }
  return judged(fx.dir, () => stage(fx, "render/render.mjs", extra));
}

export const calls = (fx, name) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];
export const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
export const record = (fx) => JSON.parse(read(fx.dir, "gates.json"));
export const delivered = (fx) =>
  path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");
export const titled = (word) =>
  SCRIPT.replace("Issue to pull request", `Issue to ${word} request`);

// A red render: the gate's line, exit 1, nothing delivered, out/ gone.
export function assertRed(fx, r, gate, why) {
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.out, new RegExp(`^gate ${gate}: fail: .*${why}`, "m"));
  assert.match(
    r.out,
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
  assert.equal(record(fx).gates[gate].status, "fail");
  assert.equal(record(fx).gates[gate].attempts, 1);
  assert.equal(record(fx).attempts, 1);
}
// Green on the fix: every gate passes, attempts back to 0, the video delivered.
export function assertGreen(fx, r) {
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gates: 7 pass, 0 fail$/m);
  for (const g of Object.values(record(fx).gates)) assert.equal(g.attempts, 0);
  assert.equal(record(fx).attempts, 0);
  assert.ok(fs.existsSync(path.join(delivered(fx), "demo.mp4")));
}

// The render stage alone, no critic round taken.
export function renderUnjudged(fx, text, extra) {
  fs.writeFileSync(path.join(fx.dir, "script.md"), text);
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  return stage(fx, "render/render.mjs", extra);
}
