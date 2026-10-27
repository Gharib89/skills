// Shared fixtures of the source tests: a temp machine, the snapshot and pack
// runners and the draft helpers.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { userDirs } from "../../skills/creative-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/creative-video/scripts/lib/tools.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "source",
);

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine with the npm install and Chrome as setup leaves them (unless
// `tools` is false), and a project holding creative-videos/demo/.
export function fixture({ tools = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "creative-source-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    CREATIVE_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    CREATIVE_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  if (tools)
    for (const r of catalogue().filter((r) =>
      ["npm", "chrome"].includes(r.kind),
    )) {
      const d = dest(r, userDirs({ platform: "linux", env, home: env.HOME }));
      fs.mkdirSync(d, { recursive: true });
      fs.writeFileSync(path.join(d, ".stamp"), "");
    }
  const dir = path.join(tmp, "proj", "creative-videos", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const docs = path.join(tmp, "docs");
  fs.mkdirSync(docs);
  return { tmp, dir, docs, env };
}

export function write(fx, name, body) {
  const f = path.join(fx.docs, name);
  fs.writeFileSync(f, typeof body === "string" ? body : JSON.stringify(body));
  return f;
}

export function node(fx, script, args, extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, script), fx.dir, ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
export const snapshot = (fx, args, extra) =>
  node(fx, "snapshot.mjs", args, extra);
export const pack = (fx, args = []) => node(fx, "pack.mjs", args);

export const sourcesOf = (fx) =>
  JSON.parse(
    fs.readFileSync(path.join(fx.dir, "snapshots", "sources.json"), "utf8"),
  );

export function draft(fx, id, excerpts, summary = "What the source says.") {
  fs.writeFileSync(
    path.join(fx.dir, "snapshots", `${id}.draft.json`),
    JSON.stringify({
      summary,
      excerpts: excerpts.map(([locator, text]) => ({
        locator,
        text,
        note: `note for ${locator}`,
      })),
    }),
  );
}

// One source, one right excerpt and one with the same text at a wrong
// locator: the right one passes alone, the wrong one is refused by name.
export function locates(fx, file, id, text, right, wrong) {
  const s = snapshot(fx, [file]);
  assert.equal(s.code, 0, s.out + s.err);
  draft(fx, id, [[right, text]]);
  const ok = pack(fx, [id]);
  assert.equal(ok.code, 0, ok.out + ok.err);
  assert.equal(ok.out.trim(), `pack ${id}: 1 of 16 excerpt(s): pass`);
  draft(fx, id, [[wrong, text]]);
  const bad = pack(fx, [id]);
  assert.equal(bad.code, 1);
  return bad.err.trim();
}
