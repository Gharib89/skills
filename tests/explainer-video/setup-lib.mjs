// Shared fixtures of the setup tests: a temp machine with a stubbed tool
// catalogue, the runner and the call and row readers.
import { after, test } from "node:test";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const source = path.join(here, "..", "..", "skills", "explainer-video");

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The sha256 of what the fake `download` writes.
export const FAKE_SHA = crypto
  .createHash("sha256")
  .update("woff2")
  .digest("hex");

// A copy of the skill in a fresh temp dir, its catalogue replaced when `rows` is
// given; otherwise the real catalogue, each model file pinned to the fake's body.
export function fixture(rows) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-video-"));
  temps.push(tmp);
  const skill = path.join(tmp, "skill");
  fs.cpSync(source, skill, { recursive: true });
  const catalogue = path.join(skill, "setup", "rows.json");
  rows ??= JSON.parse(fs.readFileSync(catalogue, "utf8")).rows.map((r) =>
    r.kind === "model"
      ? { ...r, files: r.files.map((f) => ({ ...f, sha256: FAKE_SHA })) }
      : r,
  );
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
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    EXPLAINER_VIDEO_FAKE_PRESENT: present,
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
export const cacheDir = (fx) => path.join(fx.tmp, "cache", "explainer-video");
export const fontDir = (fx) =>
  path.join(fx.tmp, "data", "explainer-video", "fonts");

export const pyRows = [
  {
    id: "ffmpeg",
    kind: "system",
    command: "ffmpeg",
    neededBy: "render",
    licence: "LGPL-2.1-or-later",
    install: {
      apt: "sudo apt install ffmpeg",
      brew: "brew install ffmpeg",
      winget: "winget install --id Gyan.FFmpeg",
    },
  },
  {
    id: "uv",
    kind: "system",
    command: "uv",
    when: "python",
    neededBy: "opt-in Python rows",
    licence: "MIT OR Apache-2.0",
    install: {
      apt: "curl -LsSf https://astral.sh/uv/install.sh | sh",
      brew: "brew install uv",
      winget: "winget install --id astral-sh.uv",
    },
  },
  {
    id: "py-model",
    kind: "font",
    when: "opt-in",
    python: true,
    family: "inter",
    version: "5.3.0",
    files: ["latin-400-normal"],
    size: 1,
    neededBy: "score",
    licence: "OFL-1.1",
  },
];

// An opt-in model run under uv: its code at a pinned commit, its checkpoints at
// a pinned revision, and the CPU path's cost per 30 s of score.
export const aceRow = (sha256 = FAKE_SHA) => ({
  id: "ace-step",
  kind: "uv",
  when: "opt-in",
  python: true,
  source: {
    repo: "org/ace",
    revision: "fedcba9876543210fedcba9876543210fedcba98",
  },
  repo: "org/ace-weights",
  revision: "0123456789abcdef0123456789abcdef01234567",
  files: [
    { path: "dit/model.safetensors", size: 4787825604, sha256 },
    { path: "vae/config.json", size: 425, sha256: FAKE_SHA },
  ],
  size: 6000000000,
  cpu: {
    seconds: 88,
    ram: 15000000000,
    of: "score",
    why: "no bfloat16, and float16 gives NaN",
  },
  neededBy: "score (ace-step)",
  licence: "MIT",
});
export const machine = (cap, ram = 32e9) => ({
  ...(cap ? { EXPLAINER_VIDEO_FAKE_GPU: String(cap) } : {}),
  EXPLAINER_VIDEO_FAKE_RAM: String(ram),
});

// A row that carries a CPU-only pin: its own pyproject and lock, and the size
// of the env they sync, which replace the upstream's on the CPU path.
export const CPU_PIN = {
  pyproject: "[project]\n# cpu\n",
  lock: "# cpu lock\n",
};
export const cpuFixture = () => {
  const row0 = aceRow();
  const fx = fixture([
    ...pyRows.slice(0, 2),
    { ...row0, cpu: { ...row0.cpu, env: { path: "setup/ace", size: 1e9 } } },
  ]);
  const pin = path.join(fx.skill, "setup", "ace");
  fs.mkdirSync(pin, { recursive: true });
  fs.writeFileSync(path.join(pin, "pyproject.toml"), CPU_PIN.pyproject);
  fs.writeFileSync(path.join(pin, "uv.lock"), CPU_PIN.lock);
  return fx;
};
export const aceDirs = (fx) =>
  fs
    .readdirSync(path.join(cacheDir(fx), "python"))
    .filter((d) => /^ace/.test(d));

// The real catalogue with the own-voice checkpoint pinned to the fake's body.
export const realRows = () =>
  JSON.parse(
    fs.readFileSync(path.join(source, "setup", "rows.json"), "utf8"),
  ).rows.map((r) =>
    r.kind === "model" || r.id === "own-voice"
      ? { ...r, files: r.files.map((f) => ({ ...f, sha256: FAKE_SHA })) }
      : r,
  );
export const enrolled = (fx, name = "maya") => {
  const dir = path.join(fx.tmp, "data", "explainer-video", "voices", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "clip.wav"), "wav");
  fs.writeFileSync(
    path.join(dir, "consent.json"),
    JSON.stringify({
      name,
      gender: "female",
      clip: crypto.createHash("sha256").update("wav").digest("hex"),
    }),
  );
};

// The machine's platform, as backend.platform() reports it.
export const on = (platform, extra = {}) => ({
  ...machine(8.6),
  EXPLAINER_VIDEO_FAKE_PLATFORM: platform,
  ...extra,
});
