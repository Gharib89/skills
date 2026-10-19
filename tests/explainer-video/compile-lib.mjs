// Shared by the compile tests: a run folder holding a scene file, the compile
// stage run on it through its process door, and the script it wrote.
import { after } from "node:test";
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

export function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-compile-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), text);
  return { tmp, dir, log: path.join(tmp, "calls.jsonl") };
}

export function run(fx, stage = "script/compile.mjs") {
  const r = spawnSync(process.execPath, [path.join(scripts, stage), fx.dir], {
    env: {
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

export const compiled = (fx) =>
  JSON.parse(fs.readFileSync(path.join(fx.dir, "script.json"), "utf8"));
