// Shared fixtures of the render tests: a temp machine with the tool cache and
// font store laid out, the stage and render runners and the file readers.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { judged } from "./critic.mjs";
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

// A temp machine: tool cache and font store as setup leaves them, a videos
// folder, and a project holding explainers/demo/script.md.
export function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-render-"));
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
  // three's ES module, and an esbuild whose bundle is a marker of its entry.
  const modules = path.join(dest({ kind: "npm" }, dirs), "node_modules");
  fs.mkdirSync(path.join(modules, "three", "build"), { recursive: true });
  fs.writeFileSync(
    path.join(modules, "three", "build", "three.module.js"),
    "/* three */",
  );
  fs.mkdirSync(path.join(modules, "esbuild"), { recursive: true });
  fs.writeFileSync(
    path.join(modules, "esbuild", "index.js"),
    `exports.buildSync = (o) => ({ outputFiles: [{ text: "/* bundle of " + o.entryPoints[0].split("node_modules")[1] + " as " + o.globalName + " */" }] });`,
  );
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

// compile and voice, then render, a clean critic round taken when the critic
// alone holds the render.
export function render(fx, extra) {
  for (const s of ["script/compile.mjs", "voice/voice.mjs"]) {
    const r = stage(fx, s);
    assert.equal(r.code, 0, `${s}: ${r.out}${r.err}`);
  }
  return judged(fx.dir, () => stage(fx, "render/render.mjs", extra));
}

export const calls = (fx, name = "hyperframes") =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];
export const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
export const comp = (fx, f = "index.html") => read(fx.dir, "composition", f);
export const unescape = (s) =>
  s
    .replace(/<[^>]+>/g, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&amp;", "&");
export const seconds = (t) => {
  const [h, m, s] = t.replace(",", ".").split(":");
  return +h * 3600 + +m * 60 + +s;
};
export const delivered = (fx) =>
  path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");

// Style profile lookup: the script names no style, so the stores decide.
export const unstyled = SCRIPT.replace("style: claude-code\n", "");
export const profile = (label, colors = {}) => {
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  return JSON.stringify({ ...p, label, colors: { ...p.colors, ...colors } });
};
export const put = (dir, name, body) => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), body);
};
export const own = (fx) => JSON.parse(read(fx.dir, "style.json"));

// A scene file's tweens: [selector, from, to, seconds into the scene].
export const tweens = (fx, id) =>
  JSON.parse(
    comp(fx, `scenes/${id}.html`).match(/const tweens = (\[.*\]);/)[1],
  );
export const at = (fx, id, n) => {
  const s = JSON.parse(read(fx.dir, "timeline.json")).scenes.find(
    (s) => s.id === id,
  );
  return s.sentences[n - 1] - s.start;
};
export const near = (a, b) => Math.abs(a - b) < 0.002;
export const profiled = (fx, name, extra) =>
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    `${name}.json`,
    JSON.stringify({
      ...JSON.parse(read(skill, "styles", "claude-code.json")),
      ...extra,
    }),
  );
