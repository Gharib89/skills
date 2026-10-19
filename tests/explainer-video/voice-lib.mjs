// Shared fixtures of the voice tests: a temp machine, the scene file and the
// voice runner.
import { after } from "node:test";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const voice = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "voice",
  "voice.mjs",
);

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

export const SCENES = [
  {
    id: "hook",
    narration: ["Ship drives one issue to a merged pull request."],
  },
  {
    id: "context",
    narration: [
      "It reads the profile first.",
      "Then it claims the issue so no other run takes it.",
    ],
  },
  {
    id: "recap",
    narration: ["Every change lands through a reviewed pull request."],
  },
];

export function fixture(scenes = SCENES, language = "en") {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-voice-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const fx = { tmp, dir, log: path.join(tmp, "calls.jsonl") };
  write(fx, scenes, language);
  return fx;
}

export const write = (fx, scenes, language = "en") =>
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({ language, scenes }),
  );

export function run(fx, extra = {}) {
  const r = spawnSync(process.execPath, [voice, fx.dir], {
    env: {
      ...extra,
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
    // A voice stage takes under a second here: a hang fails the test (status
    // null) instead of holding the suite.
    timeout: 60000,
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

export const synths = (fx) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === "synthesize")
    : [];

export const line = (out, id) =>
  out.split("\n").find((l) => l.startsWith(`voice ${id}:`));
