// Shared fixtures of the board tests: a temp machine, the stage runners and
// the board and call readers.
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
import { SCRIPT } from "./scene-file.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const skill = path.join(here, "..", "..", "skills", "explainer-video");

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine: tool cache and font store as setup leaves them, and a
// project holding explainers/demo/script.md.
export function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-board-"));
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
  return { tmp, dir, env, log: env.EXPLAINER_VIDEO_FAKE_LOG };
}

export function run(fx, script, args = [], extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", script), fx.dir, ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
export const ok = (r, what) => {
  assert.equal(r.code, 0, `${what}: ${r.out}${r.err}`);
  return r;
};
export const compile = (fx) => ok(run(fx, "script/compile.mjs"), "compile");
export const voice = (fx) => ok(run(fx, "voice/voice.mjs"), "voice");
export const stills = (fx) =>
  ok(run(fx, "render/render.mjs", ["--stills"]), "stills");
export const board = (fx, ...args) =>
  run(fx, "storyboard/board.mjs", args, fx.extra ?? {});
export const prep = (fx) => {
  compile(fx);
  voice(fx);
  return stills(fx);
};

export const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
export const doc = (fx, n) => JSON.parse(read(fx.dir, "board", `${n}.json`));
export const calls = (fx, name) =>
  fs.existsSync(fx.log)
    ? read(fx.log)
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];
