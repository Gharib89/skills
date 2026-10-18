// Shared fixtures of the style card tests: a temp machine, the card runner
// and the call readers.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SCRIPT } from "./scene-file.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const skill = path.join(here, "..", "..", "skills", "explainer-video");
export const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
export const json = (...p) => JSON.parse(read(...p));
export const html = read(skill, "storyboard", "card.html");
export const doc = read(skill, "storyboard", "card-data.md");
export const clone = (o) => JSON.parse(JSON.stringify(o));

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine as render-lib.mjs lays it out, with a draft in the run's
// style-draft/ made from the bundled ITWorx profile.
export function fixture(draft = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-card-"));
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
  fs.mkdirSync(path.join(dir, "style-draft"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, "style-draft", "acme.json"),
    JSON.stringify({
      ...json(skill, "styles", "itworx.json"),
      name: "acme",
      label: "Acme",
      source: "https://acme.example",
      marks: { accent: { mark: "measured", why: "the logo's red" } },
      ...draft,
    }),
  );
  fs.writeFileSync(path.join(dir, "script.md"), SCRIPT);
  return {
    tmp,
    dir,
    env,
    log: env.EXPLAINER_VIDEO_FAKE_LOG,
    project: path.join(tmp, "proj", "explainers", ".styles"),
    user: path.join(tmp, "config", "explainer-video", "styles"),
  };
}

export function card(fx, args, { extra = {}, at = skill } = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(at, "scripts", "style", "card.mjs"), fx.dir, "acme", ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
export function built(fx, args = ["build"]) {
  const r = card(fx, args);
  assert.equal(r.code, 0, r.out + r.err);
  return r;
}
export const latestCard = (fx) => {
  const ns = fs
    .readdirSync(path.join(fx.dir, "style-draft", "card"))
    .map((f) => f.match(/^(\d+)\.json$/)?.[1])
    .filter(Boolean)
    .map(Number);
  return json(fx.dir, "style-draft", "card", `${Math.max(...ns)}.json`);
};
export function answer(fx, text, args = []) {
  const f = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(f, text);
  return card(fx, ["apply", f, ...args]);
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

// The documented shape: every table row whose first cell is a card. or
// answers. path; a `map` is checked as a leaf.
export const shape = new Map();
for (const m of doc.matchAll(
  /^\| `((?:card|answers)\.[^`]+)` \| ([^|]+) \| (\w+) \|/gm,
))
  shape.set(m[1], { type: m[2].trim(), req: m[3] });
export function objects(v, p, acc = []) {
  if (Array.isArray(v)) v.forEach((x) => objects(x, p + "[]", acc));
  else if (v && typeof v === "object" && shape.get(p)?.type !== "map") {
    acc.push([p, v]);
    for (const k of Object.keys(v)) objects(v[k], p + "." + k, acc);
  }
  return acc;
}
export function shapeProblems(d, root) {
  const out = [];
  const all = objects(d, root);
  for (const [p, o] of all)
    for (const k of Object.keys(o))
      if (!shape.has(p + "." + k)) out.push(`undocumented field ${p}.${k}`);
  for (const [f, { req }] of shape) {
    if (!f.startsWith(root + ".") || req !== "yes") continue;
    const parent = f.slice(0, f.lastIndexOf("."));
    const key = f.slice(f.lastIndexOf(".") + 1);
    for (const [p, o] of all)
      if (p === parent && !(key in o)) out.push(`lacks required field ${f}`);
  }
  return out;
}
