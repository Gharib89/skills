// Shared fixtures of the style stage tests: a temp machine and the screenshot
// and node runners.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { bandsPpm } from "./fake-backend.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import { loadStyle } from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "style",
);

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

export function fixture({ tools = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-style-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
    EXPLAINER_VIDEO_FAKE_PRESENT: tools ? "ffmpeg" : "",
  };
  if (tools)
    for (const r of catalogue().filter((r) =>
      ["npm", "chrome"].includes(r.kind),
    )) {
      const d = dest(r, userDirs({ platform: "linux", env, home: env.HOME }));
      fs.mkdirSync(d, { recursive: true });
      fs.writeFileSync(path.join(d, ".stamp"), "");
    }
  const run = path.join(tmp, "proj", "explainers", "acme");
  fs.mkdirSync(run, { recursive: true });
  const docs = path.join(tmp, "docs");
  fs.mkdirSync(docs);
  return { tmp, run, docs, env };
}

export const node = (script, args, env) =>
  spawnSync(process.execPath, [path.join(scripts, script), ...args], {
    env,
    encoding: "utf8",
  });

export const candidates = (run) =>
  JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "candidates.json"), "utf8"),
  );

// A run measured from two screenshots of `bands`, with `roles` written as
// Claude writes them.
export function measuredRun(bands, roles) {
  const f = fixture();
  fs.writeFileSync(path.join(f.docs, "one.png"), bandsPpm(bands));
  fs.writeFileSync(path.join(f.docs, "two.png"), bandsPpm(bands));
  const r = node(
    "measure.mjs",
    [f.run, path.join(f.docs, "one.png"), path.join(f.docs, "two.png")],
    f.env,
  );
  assert.equal(r.status, 0, r.stderr);
  fs.writeFileSync(
    path.join(f.run, "style-draft", "roles.json"),
    JSON.stringify(roles),
  );
  return f;
}

// The draft as the skill's own loader takes it: contrast by role, floors,
// look and effects, or a throw.
export function loads(file, name) {
  const run = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-style-load-"));
  temps.push(run);
  fs.copyFileSync(file, path.join(run, "style.json"));
  return loadStyle(run, name);
}
