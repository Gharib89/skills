// setup.mjs through its process door: a copy of the skill, a tool cache and
// font store in a temp dir, the canned backend, and assertions on the table,
// the exit code and what landed on disk.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
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

// A copy of the skill in a fresh temp dir, its catalogue replaced when `rows` is given.
function fixture(rows) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-video-"));
  temps.push(tmp);
  const skill = path.join(tmp, "skill");
  fs.cpSync(source, skill, { recursive: true });
  if (rows)
    fs.writeFileSync(
      path.join(skill, "setup", "rows.json"),
      JSON.stringify({ rows }),
    );
  return { tmp, skill, log: path.join(tmp, "calls.jsonl") };
}

function run(fx, args, present = "ffmpeg") {
  const env = {
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

test("ffmpeg missing prints its apt, brew and winget lines and installs nothing system-wide", () => {
  const fx = fixture();
  const r = run(fx, ["install"], "");
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, "ffmpeg")[2], "missing");
  assert.match(r.out, /apt: sudo apt install ffmpeg/);
  assert.match(r.out, /brew: brew install ffmpeg/);
  assert.match(r.out, /winget: winget install/);
  assert.ok(calls(fx).every((c) => c.call !== "system"));
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

test("an install unused for 30 days is listed with its size and pruned under the yes; a fresh one is kept", () => {
  const fx = fixture([]);
  const day = 24 * 60 * 60;
  const now = Date.now() / 1000;
  const make = (rel, ageDays) => {
    const dir = path.join(cacheDir(fx), rel);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "blob"), "x".repeat(2048));
    fs.writeFileSync(path.join(dir, ".stamp"), "");
    fs.utimesSync(
      path.join(dir, ".stamp"),
      now - ageDays * day,
      now - ageDays * day,
    );
    return dir;
  };
  const old = make(path.join("node", "aaaaaaaaaaaaaaaa"), 31);
  const oldChrome = make(path.join("chrome", "aaaaaaaaaaaaaaaa"), 45);
  const fresh = make(path.join("node", "bbbbbbbbbbbbbbbb"), 3);
  const c = run(fx, ["check"]);
  assert.equal(c.code, 1, c.out + c.err);
  const cells = row(c.out, "stale node/aaaaaaaaaaaaaaaa");
  assert.ok(cells, c.out);
  assert.match(cells[2], /^stale, unused 31 days/);
  assert.match(cells[3], /KB/);
  assert.ok(row(c.out, "stale chrome/aaaaaaaaaaaaaaaa"));
  assert.equal(row(c.out, "stale node/bbbbbbbbbbbbbbbb"), undefined);
  assert.ok(fs.existsSync(old), "check removed a stale install");
  const i = run(fx, ["install"]);
  assert.equal(i.code, 0, i.out + i.err);
  assert.ok(!fs.existsSync(old));
  assert.ok(!fs.existsSync(oldChrome));
  assert.ok(fs.existsSync(fresh));
});

test("a usage error exits 2", () => {
  const fx = fixture([]);
  assert.equal(run(fx, ["frobnicate"]).code, 2);
});
