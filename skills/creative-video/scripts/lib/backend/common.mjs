// Helpers the backend modules share: the platform flag, the quiet stdio, the
// ffmpeg and ffprobe wrappers, PATH lookup and the tool cache's require.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { skill, toolPaths } from "../tools.mjs";

export const win = process.platform === "win32";
// Children write to stderr, so stdout carries only setup's own table.
export const quiet = ["ignore", 2, 2];

export function ffmpeg(args) {
  const r = spawnSync("ffmpeg", ["-hide_banner", "-nostats", ...args], {
    encoding: "utf8",
    maxBuffer: 1 << 26,
  });
  if (r.status !== 0)
    throw new Error(
      `ffmpeg exited ${r.status ?? r.error?.message}: ${(r.stderr || "").trim().split("\n").pop()}`,
    );
  return r.stderr;
}

export function sampleRate(input) {
  const probed = spawnSync(
    "ffprobe",
    [
      "-v",
      "error",
      "-select_streams",
      "a:0",
      "-show_entries",
      "stream=sample_rate",
      "-of",
      "csv=p=0",
      input,
    ],
    { encoding: "utf8" },
  );
  const rate = parseInt(probed.stdout, 10);
  if (probed.status !== 0 || !rate)
    throw new Error(`ffprobe ${input}: no audio sample rate`);
  return rate;
}

export function which(cmd) {
  const exts = win
    ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";")
    : [""];
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    for (const ext of exts) {
      const f = path.join(dir, cmd + ext);
      if (fs.statSync(f, { throwIfNoEntry: false })?.isFile()) return f;
    }
  }
  return null;
}

// The voice stage's models load from the tool cache, never the skill's folder:
// `tools.node` is the npm install, `tools.models` each model row's folder by id.
export const fromCache = (nodeDir) =>
  createRequire(path.join(nodeDir, "package.json"));
