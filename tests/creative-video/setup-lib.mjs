// Shared fixtures of the setup tests: a temp machine with a stubbed tool
// catalogue, the runner and the call and row readers.
import { after } from "node:test";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const source = path.join(here, "..", "..", "skills", "creative-video");

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The sha256 of what the fake `download` writes.
export const FAKE_SHA = crypto
  .createHash("sha256")
  .update("woff2")
  .digest("hex");

// A catalogue row with each model file and sound pack pinned to the fake's body.
const fakePinned = (r) =>
  r.kind === "model"
    ? { ...r, files: r.files.map((f) => ({ ...f, sha256: FAKE_SHA })) }
    : r.kind === "sounds"
      ? { ...r, packs: r.packs.map((p) => ({ ...p, sha256: FAKE_SHA })) }
      : r;

// A copy of the skill in a fresh temp dir, its catalogue replaced when `rows` is
// given; otherwise the real catalogue, pinned to the fake's body.
export function fixture(rows) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "creative-video-"));
  temps.push(tmp);
  const skill = path.join(tmp, "skill");
  fs.cpSync(source, skill, { recursive: true });
  const catalogue = path.join(skill, "setup", "rows.json");
  rows ??= JSON.parse(fs.readFileSync(catalogue, "utf8")).rows.map(fakePinned);
  fs.writeFileSync(catalogue, JSON.stringify({ rows }));
  return { tmp, skill, log: path.join(tmp, "calls.jsonl") };
}

export function run(fx, args, present = "ffmpeg", extra = {}) {
  const env = {
    ...extra,
    PATH: process.env.PATH,
    HOME: path.join(fx.tmp, "home"),
    XDG_CONFIG_HOME: path.join(fx.tmp, "config"),
    XDG_DATA_HOME: path.join(fx.tmp, "data"),
    XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
    CREATIVE_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    CREATIVE_VIDEO_FAKE_LOG: fx.log,
    CREATIVE_VIDEO_FAKE_PRESENT: present,
  };
  const r = spawnSync(
    process.execPath,
    [path.join(fx.skill, "scripts", "setup.mjs"), ...args],
    { env, encoding: "utf8", cwd: fx.cwd },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

export const calls = (fx) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
    : [];
// The cells of the table row named `id`, or undefined.
export const row = (out, id) =>
  out
    .split("\n")
    .find((l) => l.startsWith(`| ${id} |`))
    ?.split("|")
    .slice(1, -1)
    .map((c) => c.trim());
export const cacheDir = (fx) => path.join(fx.tmp, "cache", "creative-video");
export const fontDir = (fx) =>
  path.join(fx.tmp, "data", "creative-video", "fonts");

export const machine = (cap) =>
  cap ? { CREATIVE_VIDEO_FAKE_GPU: String(cap) } : {};

// The real catalogue pinned to the fake's body.
export const realRows = () =>
  JSON.parse(
    fs.readFileSync(path.join(source, "setup", "rows.json"), "utf8"),
  ).rows.map(fakePinned);

// The machine's platform, as backend.platform() reports it.
export const on = (platform, extra = {}) => ({
  ...machine(8.6),
  CREATIVE_VIDEO_FAKE_PLATFORM: platform,
  ...extra,
});
