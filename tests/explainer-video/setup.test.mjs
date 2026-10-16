// setup.mjs through its process door: a copy of the skill, a tool cache and
// font store in a temp dir, the canned backend, and assertions on the table,
// the exit code and what landed on disk.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = path.join(here, "..", "..", "skills", "explainer-video");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The sha256 of what the fake `download` writes.
const FAKE_SHA = crypto.createHash("sha256").update("woff2").digest("hex");

// A copy of the skill in a fresh temp dir, its catalogue replaced when `rows` is
// given; otherwise the real catalogue, each model file pinned to the fake's body.
function fixture(rows) {
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

function run(fx, args, present = "ffmpeg", extra = {}) {
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
    { env, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

const calls = (fx) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
    : [];
// The cells of the table row named `id`, or undefined.
const row = (out, id) =>
  out
    .split("\n")
    .find((l) => l.startsWith(`| ${id} |`))
    ?.split("|")
    .slice(1, -1)
    .map((c) => c.trim());
const cacheDir = (fx) => path.join(fx.tmp, "cache", "explainer-video");
const fontDir = (fx) => path.join(fx.tmp, "data", "explainer-video", "fonts");

test("a check on an empty machine lists every row missing, with size, licence and destination, and installs nothing", () => {
  const fx = fixture();
  const r = run(fx, ["check"], "");
  assert.equal(r.code, 1, r.err);
  assert.match(
    r.out,
    /^\| row \| needed by \| status \| size \| licence \| writes to \|$/m,
  );
  const rows = JSON.parse(
    fs.readFileSync(path.join(fx.skill, "setup", "rows.json"), "utf8"),
  ).rows.filter((x) => !x.when);
  assert.ok(rows.length >= 4);
  for (const x of rows) {
    const cells = row(r.out, x.id);
    assert.ok(cells, `row ${x.id} missing from:\n${r.out}`);
    assert.equal(cells[2], "missing", x.id);
    assert.ok(cells[4], `${x.id} has no licence`);
    assert.ok(cells[5], `${x.id} has no destination`);
    if (x.kind !== "system")
      assert.match(cells[3], /\d/, `${x.id} has no size`);
  }
  assert.deepEqual(calls(fx), []);
  assert.ok(!fs.existsSync(cacheDir(fx)));
});

test("install is the yes: it installs every row, npm ci skips the onnxruntime provider download, and a second check is all present", () => {
  const fx = fixture();
  const i = run(fx, ["install"]);
  assert.equal(i.code, 0, i.out + i.err);
  const ci = calls(fx).filter((c) => c.call === "npmCi");
  assert.equal(ci.length, 1);
  assert.equal(ci[0].onnxruntime, "skip");
  const c = run(fx, ["check"]);
  assert.equal(c.code, 0, c.out + c.err);
  for (const l of c.out
    .split("\n")
    .filter(
      (l) =>
        l.startsWith("| ") &&
        !l.startsWith("| row |") &&
        !l.startsWith("| ---"),
    )) {
    assert.equal(l.split("|")[3].trim(), "present", l);
  }
  assert.equal(
    calls(fx).filter((x) => x.call === "npmCi").length,
    1,
    "the second check installed something",
  );
});

test("install clears what an earlier Chrome install left half done", () => {
  const fx = fixture();
  const chromeDir = row(run(fx, ["check"]).out, "chrome")[5];
  const leftover = path.join(chromeDir, "partial-download");
  fs.mkdirSync(path.dirname(leftover), { recursive: true });
  fs.writeFileSync(leftover, "x");
  const r = run(fx, ["install"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.ok(!fs.existsSync(leftover), "the half-done download survived");
  assert.ok(fs.existsSync(path.join(path.dirname(leftover), ".stamp")));
});

test("ffmpeg missing prints its apt, brew and winget lines and installs nothing system-wide", () => {
  const fx = fixture();
  const r = run(fx, ["install"], "");
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, "ffmpeg")[2], "missing");
  assert.match(r.out, /apt: sudo apt install ffmpeg/);
  assert.match(r.out, /brew: brew install ffmpeg/);
  assert.match(r.out, /winget: winget install/);
  assert.match(r.out, /^not present: ffmpeg$/m, "a system package has no size");
  const tools = ["npmCi", "ensureChrome", "fontMeta", "download"];
  for (const c of calls(fx)) assert.ok(tools.includes(c.call), c.call);
  assert.equal(row(run(fx, ["check"], "").out, "ffmpeg")[2], "missing");
});

const pyRows = [
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

test("uv is listed only when an opt-in Python row is asked for", () => {
  const fx = fixture(pyRows);
  const plain = run(fx, ["check"], "ffmpeg");
  assert.equal(row(plain.out, "uv"), undefined, plain.out);
  assert.equal(row(plain.out, "py-model"), undefined, plain.out);
  const all = run(fx, ["check", "--all"], "ffmpeg");
  assert.equal(row(all.out, "py-model")[2], "missing");
  assert.equal(row(all.out, "uv")[2], "missing");
  assert.match(all.out, /brew: brew install uv/);
});

// An opt-in model run under uv: its code at a pinned commit, its checkpoints at
// a pinned revision, and the CPU path's cost per 30 s of score.
const aceRow = (sha256 = FAKE_SHA) => ({
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
  cpu: { seconds: 88, ram: 15000000000 },
  neededBy: "score (ace-step)",
  licence: "MIT",
});
const machine = (cap, ram = 32e9) => ({
  ...(cap ? { EXPLAINER_VIDEO_FAKE_GPU: String(cap) } : {}),
  EXPLAINER_VIDEO_FAKE_RAM: String(ram),
});

test("ace-step is listed only when asked, and on a card under compute capability 8.0 it shows the CPU path's cost per 30 s of score", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const plain = run(fx, ["check"], "ffmpeg,uv", machine(7.5));
  assert.equal(row(plain.out, "ace-step"), undefined, plain.out);
  assert.doesNotMatch(plain.out, /per 30 s of score/);
  const all = run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(all.code, 1, all.out + all.err);
  assert.equal(row(all.out, "ace-step")[2], "missing");
  assert.equal(row(all.out, "ace-step")[3], "10.8 GB");
  assert.match(
    all.out,
    /^ace-step runs on the CPU here \(compute capability 7\.5, under 8\.0: no bfloat16, and float16 gives NaN\): about 1 min 28 s and 15\.0 GB RAM per 30 s of score\.$/m,
  );
  assert.deepEqual(calls(fx), []);
});

test("ace-step runs on the GPU from compute capability 8.0, and on the CPU with no NVIDIA card", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const ampere = run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.6, 4e9));
  assert.equal(
    row(ampere.out, "ace-step")[2],
    "missing",
    "a GPU run is not held to the CPU's RAM",
  );
  assert.match(
    ampere.out,
    /^ace-step runs on the GPU here \(compute capability 8\.6\)\.$/m,
  );
  assert.doesNotMatch(ampere.out, /per 30 s of score/);
  assert.match(
    run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.0)).out,
    /^ace-step runs on the GPU here \(compute capability 8\.0\)\.$/m,
  );
  const none = run(fx, ["check", "--all"], "ffmpeg,uv", machine(null));
  assert.match(
    none.out,
    /^ace-step runs on the CPU here \(no NVIDIA card\): about 1 min 28 s/m,
  );
});

test("a machine short of the CPU path's RAM is refused before any download", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5, 8e9));
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    row(r.out, "ace-step")[2],
    "refused: the CPU path needs 15.0 GB RAM, this machine has 8.0 GB",
  );
  assert.doesNotMatch(r.out, /to install/, "a refused row is not installed");
  assert.deepEqual(calls(fx), []);
  assert.ok(!fs.existsSync(path.join(cacheDir(fx), "python")));
});

test("ace-step installs its code at the pinned commit, syncs it under uv from its own lock, and fetches its checkpoints at their pinned revision", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(r.code, 0, r.out + r.err);
  const where = path.join(cacheDir(fx), "python", "ace-step@fedcba9-0123456");
  assert.equal(row(r.out, "ace-step")[5], where);
  assert.deepEqual(
    calls(fx).map((c) => c.url ?? c.call),
    [
      "https://codeload.github.com/org/ace/zip/fedcba9876543210fedcba9876543210fedcba98",
      "extract",
      "uvSync",
      "https://huggingface.co/org/ace-weights/resolve/0123456789abcdef0123456789abcdef01234567/dit/model.safetensors",
      "https://huggingface.co/org/ace-weights/resolve/0123456789abcdef0123456789abcdef01234567/vae/config.json",
    ],
  );
  const sync = calls(fx).find((c) => c.call === "uvSync");
  assert.equal(sync.dir, path.join(where, "src"));
  assert.ok(fs.existsSync(path.join(where, "src", "pyproject.toml")));
  assert.ok(
    fs.existsSync(path.join(where, "checkpoints", "dit", "model.safetensors")),
  );
  assert.ok(!fs.existsSync(path.join(where, "source.zip")));
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5)).out,
      "ace-step",
    )[2],
    "present",
  );
});

test("an ace-step checkpoint whose sha256 differs from its pin fails the row and leaves it missing", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow("0".repeat(64))]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    row(r.out, "ace-step")[2],
    /^failed: dit\/model\.safetensors has sha256 [0-9a-f]{64}, pinned 0{64}/,
  );
  assert.match(r.out, /^not present: ace-step \(10\.8 GB to install\)$/m);
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5)).out,
      "ace-step",
    )[2],
    "missing",
  );
});

test("fonts are fetched by family at the pinned version into the font store", () => {
  const fx = fixture([
    {
      id: "font:inter",
      kind: "font",
      family: "inter",
      version: "5.3.0",
      files: ["latin-400-normal", "latin-600-normal"],
      size: 48116,
      neededBy: "render",
      licence: "OFL-1.1",
    },
  ]);
  const r = run(fx, ["install"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    calls(fx)
      .filter((c) => c.call === "fontMeta")
      .map((c) => c.id),
    ["inter"],
  );
  const urls = calls(fx)
    .filter((c) => c.call === "download")
    .map((c) => c.url);
  assert.deepEqual(urls, [
    "https://cdn.jsdelivr.net/fontsource/fonts/inter@5.3.0/latin-400-normal.woff2",
    "https://cdn.jsdelivr.net/fontsource/fonts/inter@5.3.0/latin-600-normal.woff2",
  ]);
  assert.ok(
    fs.existsSync(
      path.join(fontDir(fx), "inter@5.3.0", "latin-600-normal.woff2"),
    ),
  );
});

test("a font whose licence is neither OFL nor Apache is refused and nothing is written", () => {
  const fx = fixture([
    {
      id: "font:ubuntu",
      kind: "font",
      family: "ubuntu",
      version: "5.2.0",
      files: ["latin-400-normal"],
      size: 1,
      neededBy: "render",
      licence: "UFL-1.0",
    },
  ]);
  const r = run(fx, ["install"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(row(r.out, "font:ubuntu")[2], /^refused: licence UFL-1\.0/);
  assert.ok(calls(fx).every((c) => c.call !== "download"));
  assert.ok(!fs.existsSync(path.join(fontDir(fx), "ubuntu@5.2.0")));
});

const modelRow = (sha256) => ({
  id: "model:aligner",
  kind: "model",
  repo: "org/aligner",
  revision: "0123456789abcdef0123456789abcdef01234567",
  files: [
    { path: "vocab.json", size: 358, sha256: FAKE_SHA },
    { path: "onnx/model_int8.onnx", size: 95286006, sha256 },
  ],
  neededBy: "voice",
  licence: "Apache-2.0",
});

test("a model is its own row with its files' size, fetched at its pinned revision into the tool cache", () => {
  const fx = fixture([modelRow(FAKE_SHA)]);
  const c = run(fx, ["check"]);
  assert.equal(row(c.out, "model:aligner")[3], "95 MB");
  const where = row(c.out, "model:aligner")[5];
  assert.equal(
    where,
    path.join(cacheDir(fx), "models", "aligner@0123456789ab"),
  );
  const r = run(fx, ["install"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    calls(fx)
      .filter((x) => x.call === "download")
      .map((x) => x.url),
    [
      "https://huggingface.co/org/aligner/resolve/0123456789abcdef0123456789abcdef01234567/vocab.json",
      "https://huggingface.co/org/aligner/resolve/0123456789abcdef0123456789abcdef01234567/onnx/model_int8.onnx",
    ],
  );
  assert.ok(fs.existsSync(path.join(where, "onnx", "model_int8.onnx")));
  assert.equal(row(run(fx, ["check"]).out, "model:aligner")[2], "present");
});

test("a model file whose sha256 differs from its pin fails the row and leaves nothing installed", () => {
  const fx = fixture([modelRow("0".repeat(64))]);
  const r = run(fx, ["install"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    row(r.out, "model:aligner")[2],
    /^failed: onnx\/model_int8\.onnx has sha256 [0-9a-f]{64}, pinned 0{64}/,
  );
  assert.ok(
    !fs.existsSync(path.join(cacheDir(fx), "models", "aligner@0123456789ab")),
  );
  assert.equal(row(run(fx, ["check"]).out, "model:aligner")[2], "missing");
});

test("an install unused for 30 days is listed with its size and pruned under the yes; a fresh one is kept", () => {
  const fx = fixture([]);
  const day = 24 * 60 * 60;
  const now = Date.now() / 1000;
  // An install that never finished has no stamp, and ages by its folder.
  const make = (rel, ageDays, stamped = true) => {
    const dir = path.join(cacheDir(fx), rel);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "blob"), "x".repeat(2048));
    const aged = stamped ? path.join(dir, ".stamp") : dir;
    if (stamped) fs.writeFileSync(aged, "");
    fs.utimesSync(aged, now - ageDays * day, now - ageDays * day);
    return dir;
  };
  const old = make(path.join("node", "aaaaaaaaaaaaaaaa"), 31);
  const oldChrome = make(path.join("chrome", "aaaaaaaaaaaaaaaa"), 45);
  const unfinished = make(path.join("node", "cccccccccccccccc"), 40, false);
  const fresh = make(path.join("node", "bbbbbbbbbbbbbbbb"), 3);
  const c = run(fx, ["check"]);
  assert.equal(c.code, 1, c.out + c.err);
  const cells = row(c.out, "stale node/aaaaaaaaaaaaaaaa");
  assert.ok(cells, c.out);
  assert.match(cells[2], /^stale, unused 31 days/);
  assert.match(cells[3], /KB/);
  assert.ok(row(c.out, "stale chrome/aaaaaaaaaaaaaaaa"));
  assert.ok(row(c.out, "stale node/cccccccccccccccc"), c.out);
  assert.equal(row(c.out, "stale node/bbbbbbbbbbbbbbbb"), undefined);
  assert.ok(fs.existsSync(old), "check removed a stale install");
  const i = run(fx, ["install"]);
  assert.equal(i.code, 0, i.out + i.err);
  assert.ok(!fs.existsSync(old));
  assert.ok(!fs.existsSync(oldChrome));
  assert.ok(!fs.existsSync(unfinished));
  assert.ok(fs.existsSync(fresh));
});

test("a usage error exits 2", () => {
  const fx = fixture([]);
  assert.equal(run(fx, ["frobnicate"]).code, 2);
});
