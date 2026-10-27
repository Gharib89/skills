// The source stage through its process doors, part 1: repo snapshots and the
// locators for PDF, Markdown and text excerpts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  draft,
  fixture,
  locates,
  pack,
  scripts,
  snapshot,
  sourcesOf,
  write,
} from "./source-lib.mjs";

function git(cwd, ...args) {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
}

test("a repo source snapshots tracked and unignored files and never an ignored file, a .env file or one holding a secret", () => {
  const fx = fixture();
  const repo = path.join(fx.tmp, "app");
  fs.mkdirSync(path.join(repo, "src"), { recursive: true });
  // Built at run time, so no secret scanner reads one in this repo's history.
  const key = "AKIA" + "Q3EXAMPLE7KEY4XZ".slice(0, 16);
  const files = {
    "README.md": "# App\n\nThe app renders videos.\n",
    "src/app.js":
      "export const name = 'app';\nexport const run = () => name;\n",
    ".gitignore": "secrets.txt\nbuild/\n",
    "secrets.txt": `ignored ${key}\n`,
    "build/out.js": "ignored build output\n",
    ".env.local": "API_URL=http://localhost\n",
    "src/config.js": `export const aws = "${key}";\n`,
    "deploy.pem": "certificate body\n",
    "notes.md": "Untracked but not ignored.\n",
  };
  fs.mkdirSync(path.join(repo, "build"));
  for (const [f, body] of Object.entries(files))
    fs.writeFileSync(path.join(repo, f), body);
  git(repo, "init", "-q");
  git(
    repo,
    "add",
    "-f",
    "README.md",
    "src/app.js",
    ".gitignore",
    ".env.local",
    "src/config.js",
    "deploy.pem",
  );
  const s = snapshot(fx, [repo]);
  assert.equal(s.code, 0, s.out + s.err);
  assert.deepEqual(s.out.trim().split("\n"), [
    `source app: repo · 4 file(s) · ${repo}`,
    "withheld app/.env.local: .env file",
    "withheld app/deploy.pem: secret file name",
    "withheld app/src/config.js: secret pattern",
    "budget: 16 excerpts (2 min at 8 per minute, at least 12); shares app 16",
  ]);
  const snap = path.join(fx.dir, "snapshots", "app");
  const held = spawnSync("find", [".", "-type", "f"], {
    cwd: snap,
    encoding: "utf8",
  })
    .stdout.trim()
    .split("\n")
    .sort();
  assert.deepEqual(held, [
    "./.gitignore",
    "./README.md",
    "./notes.md",
    "./src/app.js",
  ]);
  const all = held.map((f) => fs.readFileSync(path.join(snap, f), "utf8"));
  assert.ok(!all.some((t) => t.includes(key) || t.includes("build output")));

  // A repo excerpt locates by path and line.
  draft(fx, "app", [["src/app.js:2", "export const run = () => name;"]]);
  assert.equal(pack(fx, ["app"]).code, 0);
  draft(fx, "app", [["src/app.js:1", "export const run = () => name;"]]);
  assert.match(
    pack(fx, ["app"]).err,
    /pack app: excerpt 1: not word for word in src\/app\.js:1/,
  );
  draft(fx, "app", [["src/config.js:1", "export const aws"]]);
  assert.match(
    pack(fx, ["app"]).err,
    /excerpt 1: src\/config\.js:1: no file src\/config\.js in the snapshot/,
  );
});

test("a repo holding the creative-videos folder leaves every run's files out, and a source named twice is read once", () => {
  const fx = fixture();
  const proj = path.join(fx.tmp, "proj");
  fs.writeFileSync(path.join(proj, "README.md"), "# Proj\n");
  fs.writeFileSync(path.join(fx.dir, "outline.md"), "# An earlier pack\n");
  fs.mkdirSync(path.join(fx.dir, "snapshots"));
  fs.writeFileSync(path.join(fx.dir, "snapshots", "old.md"), "stale\n");
  const other = path.join(proj, "creative-videos", "other");
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(other, "outline.md"), "# Another video\n");
  git(proj, "init", "-q");
  git(proj, "add", "README.md", "creative-videos/other/outline.md");
  const s = snapshot(fx, [proj, `${proj}/`]);
  assert.equal(s.code, 0, s.out + s.err);
  assert.deepEqual(
    sourcesOf(fx).sources.map((x) => x.id),
    ["proj"],
  );
  const held = spawnSync("find", [".", "-type", "f"], {
    cwd: path.join(fx.dir, "snapshots", "proj"),
    encoding: "utf8",
  }).stdout.trim();
  assert.equal(held, "./README.md");
});

test("a repo file is copied byte for byte, and a run folder outside creative-videos/ hides nothing beside it", () => {
  const fx = fixture();
  const repo = path.join(fx.tmp, "lib");
  fs.mkdirSync(repo);
  const latin1 = Buffer.from("caf\xe9 au lait\n", "latin1");
  fs.writeFileSync(path.join(repo, "menu.txt"), latin1);
  git(repo, "init", "-q");
  git(repo, "add", "menu.txt");
  // The run sits beside the repo, so their shared parent is no creative-videos/.
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, "snapshot.mjs"), path.join(fx.tmp, "run1"), repo],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /^source lib: repo · 1 file\(s\)/);
  assert.deepEqual(
    fs.readFileSync(path.join(fx.tmp, "run1", "snapshots", "lib", "menu.txt")),
    latin1,
  );
});

test("a run folder inside a repo but outside creative-videos/ hides itself and nothing else", () => {
  const fx = fixture();
  const repo = path.join(fx.tmp, "site");
  const run = path.join(repo, "videos", "demo");
  const other = path.join(repo, "videos", "other");
  fs.mkdirSync(run, { recursive: true });
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(run, "outline.md"), "# This video\n");
  fs.writeFileSync(path.join(other, "notes.md"), "# Beside it\n");
  git(repo, "init", "-q");
  git(repo, "add", "videos");
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, "snapshot.mjs"), run, repo],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const held = spawnSync("find", [".", "-type", "f"], {
    cwd: path.join(run, "snapshots", "site"),
    encoding: "utf8",
  }).stdout.trim();
  assert.equal(held, "./videos/other/notes.md");
});

test("a folder outside git is refused, since nothing says which of its files are ignored", () => {
  const fx = fixture();
  const s = snapshot(fx, [fx.docs]);
  assert.equal(s.code, 1);
  assert.match(s.err, /^source .*docs: not inside a git repository/);
  assert.ok(!fs.existsSync(path.join(fx.dir, "snapshots", "sources.json")));
});

test("a PDF excerpt locates by page", () => {
  const fx = fixture();
  const f = write(fx, "design.pdf", {
    pages: [
      "Intro to the design.",
      "The gate blocks a red render.\nThen stop.",
    ],
  });
  const err = locates(
    fx,
    f,
    "design",
    "The gate blocks a red render. Then stop.",
    "page 2",
    "page 1",
  );
  assert.equal(err, "pack design: excerpt 1: not word for word in page 1");
  draft(fx, "design", [["page 3", "Intro"]]);
  assert.match(pack(fx, ["design"]).err, /excerpt 1: page 3: no page 3/);
  draft(fx, "design", [["§ Intro", "Intro"]]);
  assert.match(
    pack(fx, ["design"]).err,
    /excerpt 1: § Intro: not a pdf locator \(want page <n>\)/,
  );
});

test("a Markdown excerpt locates by section or by line", () => {
  const fx = fixture();
  const f = write(
    fx,
    "guide.md",
    "# Guide\n\nAn intro.\n\n## Install\n\nRun npm ci.\n\n```sh\n# not a heading\n```\n\n## Use\n\nRun it.\n",
  );
  const err = locates(fx, f, "guide", "Run npm ci.", "§ Install", "§ Use");
  assert.equal(err, "pack guide: excerpt 1: not word for word in § Use");
  // A `#` line inside a fence is no heading: it stays in § Install.
  draft(fx, "guide", [
    ["§ Install", "# not a heading"],
    ["lines 7-7", "Run npm ci."],
  ]);
  assert.equal(pack(fx, ["guide"]).code, 0);
  assert.match(snapshot(fx, [f]).out, /^source guide: md · 3 section\(s\) · /);
});

// #725: a page heading holding an anchor link reached outline.md as
// `§ [Validation](#validation)`.
test("a heading holding a Markdown link reads as its text in the pack, and either form locates", () => {
  const fx = fixture();
  const f = write(
    fx,
    "cache.md",
    "# Caching\n\n## [Validation](#validation)\n\nAn ETag names a version.\n",
  );
  assert.equal(snapshot(fx, [f]).code, 0);
  for (const locator of ["§ [Validation](#validation)", "§ Validation"]) {
    draft(fx, "cache", [[locator, "An ETag names a version."]]);
    const r = pack(fx);
    assert.equal(r.code, 0, r.out + r.err);
    const outline = fs.readFileSync(path.join(fx.dir, "outline.md"), "utf8");
    assert.match(outline, /^- ex-1 · § Validation · note for /m);
    const { excerpts } = JSON.parse(
      fs.readFileSync(path.join(fx.dir, "excerpts.json"), "utf8"),
    );
    assert.equal(excerpts[0].locator, "§ Validation");
  }
  // A link around a badge image reads as the image's text, and the stored
  // locator still finds its section.
  const g = write(
    fx,
    "readme.md",
    "# Project [![CI](x/badge.svg)](x/actions)\n\nIt builds.\n\n## [API](https://e.org/a_(b))\n\nIt serves.\n\n## [Array [T]](#array-t)\n\nIt holds.\n",
  );
  assert.equal(snapshot(fx, [g]).code, 0);
  draft(fx, "readme", [
    ["§ Project [![CI](x/badge.svg)](x/actions)", "It builds."],
    ["§ [API](https://e.org/a_(b))", "It serves."],
    ["§ [Array [T]](#array-t)", "It holds."],
  ]);
  draft(fx, "cache", [["§ Validation", "An ETag names a version."]]);
  assert.equal(pack(fx).code, 0);
  const { excerpts } = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "excerpts.json"), "utf8"),
  );
  const [badge, api, array] = excerpts.filter((x) => x.source === "readme");
  assert.equal(badge.locator, "§ Project CI");
  // A destination holding balanced parentheses is read whole, and so is a
  // label holding balanced brackets.
  assert.equal(api.locator, "§ API");
  assert.equal(array.locator, "§ Array [T]");
  draft(fx, "readme", [
    [badge.locator, "It builds."],
    [api.locator, "It serves."],
    [array.locator, "It holds."],
  ]);
  assert.equal(pack(fx, ["readme"]).code, 0);
});

test("a repo locator is stored as written, brackets and spaces included", () => {
  const fx = fixture();
  const repo = path.join(fx.tmp, "app");
  fs.mkdirSync(path.join(repo, "§ docs"), { recursive: true });
  const file = "§ docs/[id](x)  notes.md";
  fs.writeFileSync(path.join(repo, file), "It ships.\n");
  git(repo, "init", "-q");
  git(repo, "add", ".");
  assert.equal(snapshot(fx, [repo]).code, 0);
  draft(fx, "app", [[`${file}:1`, "It ships."]]);
  const r = pack(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const { excerpts } = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "excerpts.json"), "utf8"),
  );
  assert.equal(excerpts[0].locator, `${file}:1`);
});

test("a heading used twice locates in either section, never across the two", () => {
  const fx = fixture();
  const f = write(
    fx,
    "ex.md",
    "# Ex\n\n## Example\n\nAlpha ends.\n\n## Other\n\nMiddle.\n\n## Example\n\nBeta starts.\n",
  );
  assert.equal(snapshot(fx, [f]).code, 0);
  draft(fx, "ex", [
    ["§ Example", "Alpha ends."],
    ["§ Example", "Beta starts."],
  ]);
  assert.equal(pack(fx, ["ex"]).code, 0);
  draft(fx, "ex", [["§ Example", "Alpha ends. ## Example Beta starts."]]);
  assert.match(pack(fx, ["ex"]).err, /not word for word in § Example/);
});

test("a text excerpt locates by line", () => {
  const fx = fixture();
  const f = write(fx, "notes.txt", "first line\nsecond line\nthird line\n");
  const err = locates(fx, f, "notes", "third line", "line 3", "line 2");
  assert.equal(err, "pack notes: excerpt 1: not word for word in line 2");
  draft(fx, "notes", [["lines 2-9", "second"]]);
  assert.match(pack(fx, ["notes"]).err, /excerpt 1: lines 2-9: no lines 2-9/);
});
