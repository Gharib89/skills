// The source stage through its process doors: sources snapshotted into a run
// folder, a reader's draft checked against its snapshot, and the pack the merge
// writes. The fake backend stands in for Chrome, pdf.js, mammoth, Turndown and
// jszip; what it hands back is what the stage splits, locates and checks.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "source",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine with the npm install and Chrome as setup leaves them (unless
// `tools` is false), and a project holding explainers/demo/.
function fixture({ tools = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-source-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  if (tools)
    for (const r of catalogue().filter((r) =>
      ["npm", "chrome"].includes(r.kind),
    )) {
      const d = dest(r, userDirs({ platform: "linux", env, home: env.HOME }));
      fs.mkdirSync(d, { recursive: true });
      fs.writeFileSync(path.join(d, ".stamp"), "");
    }
  const dir = path.join(tmp, "proj", "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const docs = path.join(tmp, "docs");
  fs.mkdirSync(docs);
  return { tmp, dir, docs, env };
}

function write(fx, name, body) {
  const f = path.join(fx.docs, name);
  fs.writeFileSync(f, typeof body === "string" ? body : JSON.stringify(body));
  return f;
}

function node(fx, script, args, extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, script), fx.dir, ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const snapshot = (fx, args, extra) => node(fx, "snapshot.mjs", args, extra);
const pack = (fx, args = []) => node(fx, "pack.mjs", args);

const sourcesOf = (fx) =>
  JSON.parse(
    fs.readFileSync(path.join(fx.dir, "snapshots", "sources.json"), "utf8"),
  );

function draft(fx, id, excerpts, summary = "What the source says.") {
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
function locates(fx, file, id, text, right, wrong) {
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

test("a repo holding the explainers folder leaves every run's files out, and a source named twice is read once", () => {
  const fx = fixture();
  const proj = path.join(fx.tmp, "proj");
  fs.writeFileSync(path.join(proj, "README.md"), "# Proj\n");
  fs.writeFileSync(path.join(fx.dir, "outline.md"), "# An earlier pack\n");
  fs.mkdirSync(path.join(fx.dir, "snapshots"));
  fs.writeFileSync(path.join(fx.dir, "snapshots", "old.md"), "stale\n");
  const other = path.join(proj, "explainers", "other");
  fs.mkdirSync(other);
  fs.writeFileSync(path.join(other, "outline.md"), "# Another video\n");
  git(proj, "init", "-q");
  git(proj, "add", "README.md", "explainers/other/outline.md");
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

test("a repo file is copied byte for byte, and a run folder outside explainers/ hides nothing beside it", () => {
  const fx = fixture();
  const repo = path.join(fx.tmp, "lib");
  fs.mkdirSync(repo);
  const latin1 = Buffer.from("caf\xe9 au lait\n", "latin1");
  fs.writeFileSync(path.join(repo, "menu.txt"), latin1);
  git(repo, "init", "-q");
  git(repo, "add", "menu.txt");
  // The run sits beside the repo, so their shared parent is no explainers/.
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

test("a run folder inside a repo but outside explainers/ hides itself and nothing else", () => {
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

test("an HTML file renders through Chrome and its excerpt locates by section", () => {
  const fx = fixture();
  const f = write(
    fx,
    "page.html",
    "<html><head><title>Docs</title></head><body><h2>Setup</h2><p>Install the tools.</p><h2>Run</h2><p>Go.</p></body></html>",
  );
  const err = locates(fx, f, "page", "Install the tools.", "§ Setup", "§ Run");
  assert.equal(err, "pack page: excerpt 1: not word for word in § Run");
  const calls = fs
    .readFileSync(fx.env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
    .trim()
    .split("\n")
    .map((l) => JSON.parse(l));
  assert.equal(calls[0].call, "renderPage");
  assert.match(calls[0].url, /^file:\/\/.*page\.html$/);
  // The page's title heads the snapshot, so text above its first heading has
  // a section too.
  assert.match(
    fs.readFileSync(path.join(fx.dir, "snapshots", "page.md"), "utf8"),
    /^# Docs\n\n## Setup/,
  );
});

test("a DOCX excerpt locates by section", () => {
  const fx = fixture();
  const f = write(
    fx,
    "plan.docx",
    "<h1>Setup</h1><p>Install the tools once.</p><h2>Run</h2><p>Render the video.</p>",
  );
  const err = locates(
    fx,
    f,
    "plan",
    "Install the tools once.",
    "§ Setup",
    "§ Run",
  );
  assert.equal(err, "pack plan: excerpt 1: not word for word in § Run");
});

test("a PPTX excerpt locates by slide in the deck's order, and its notes by slide notes", () => {
  const fx = fixture();
  const P = 'xmlns:a="a" xmlns:p="p" xmlns:r="r"';
  const sp = (ph, text) =>
    `<p:sp><p:nvSpPr><p:nvPr><p:ph type="${ph}"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>${text}</a:t></a:r></a:p></p:txBody></p:sp>`;
  const slide = (title, body) =>
    `<p:sld ${P}><p:cSld><p:spTree>${sp("title", title)}<p:sp useBgFill="1"><p:txBody><a:p><a:r><a:t>${body.split(" ")[0]}</a:t></a:r><a:br/><a:r><a:t xml:space="preserve">${body.split(" ").slice(1).join(" ")}</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>`;
  const rel = (id, type, target) =>
    `<Relationship Id="${id}" Type="http://x/${type}" Target="${target}"/>`;
  const f = write(fx, "deck.pptx", {
    parts: {
      // The deck shows slide2.xml first.
      "ppt/presentation.xml": `<p:presentation ${P}><p:sldIdLst><p:sldId id="257" r:id="rId3"/><p:sldId id="256" r:id="rId2"/></p:sldIdLst></p:presentation>`,
      "ppt/_rels/presentation.xml.rels": `<Relationships>${rel("rId2", "slide", "slides/slide1.xml")}${rel("rId3", "slide", "slides/slide2.xml")}</Relationships>`,
      "ppt/slides/slide1.xml": slide(
        "Gates",
        "Red means no video &amp; no delivery",
      ),
      "ppt/slides/slide2.xml": slide("Ship", "Issue to pull request"),
      "ppt/slides/_rels/slide2.xml.rels": `<Relationships>${rel("rId1", "notesSlide", "../notesSlides/notesSlide1.xml")}</Relationships>`,
      "ppt/notesSlides/notesSlide1.xml": `<p:notes ${P}><p:cSld><p:spTree>${sp("sldImg", "")}${sp("body", "Say hello first.")}${sp("sldNum", "7")}</p:spTree></p:cSld></p:notes>`,
    },
  });
  const err = locates(
    fx,
    f,
    "deck",
    "Issue to pull request",
    "slide 1",
    "slide 2",
  );
  assert.equal(err, "pack deck: excerpt 1: not word for word in slide 2");
  draft(fx, "deck", [
    ["slide 1 notes", "Say hello first."],
    ["slide 2", "Red means no video & no delivery"],
  ]);
  assert.equal(pack(fx, ["deck"]).code, 0);
  draft(fx, "deck", [["slide 1 notes", "7"]]);
  assert.match(pack(fx, ["deck"]).err, /not word for word in slide 1 notes/);
});

test("a web page renders in Chrome and its excerpt locates by section", () => {
  const fx = fixture();
  const url = "https://docs.example.com/guide/intro";
  const pages = JSON.stringify({
    [url]: {
      title: "Intro",
      html: "<h2>Install</h2><p>Run the setup once.</p><h2>Render</h2><p>Then render.</p>",
    },
  });
  const s = snapshot(fx, [url], { EXPLAINER_VIDEO_FAKE_PAGES: pages });
  assert.equal(s.code, 0, s.out + s.err);
  assert.match(
    s.out,
    /^source docs-example-com-intro: page · 3 section\(s\) · https/,
  );
  draft(fx, "docs-example-com-intro", [["§ Install", "Run the setup once."]]);
  assert.equal(pack(fx, ["docs-example-com-intro"]).code, 0);
  const missing = snapshot(fx, ["https://nowhere.example.com/"]);
  assert.equal(missing.code, 1);
  assert.match(
    missing.err,
    /^source https:\/\/nowhere\.example\.com\/: could not read it: net::ERR_NAME_NOT_RESOLVED/,
  );
});

test("a page URL is kept without its credentials, query or fragment, and a malformed URL is refused by name", () => {
  const fx = fixture();
  const url = "https://me:pw@docs.example.com/guide/intro?token=s3cret#t=key";
  const pages = JSON.stringify({
    [url]: { title: "", html: "<h2>Install</h2><p>Run the setup once.</p>" },
  });
  const s = snapshot(fx, [url], { EXPLAINER_VIDEO_FAKE_PAGES: pages });
  assert.equal(s.code, 0, s.out + s.err);
  draft(fx, "docs-example-com-intro", [["§ Install", "Run the setup once."]]);
  assert.equal(pack(fx).code, 0);
  const kept = [
    s.out,
    fs.readFileSync(path.join(fx.dir, "snapshots", "sources.json"), "utf8"),
    fs.readFileSync(path.join(fx.dir, "excerpts.json"), "utf8"),
    fs.readFileSync(path.join(fx.dir, "outline.md"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(kept, /s3cret|pw@|token|key/);
  assert.match(kept, /Source: https:\/\/docs\.example\.com\/guide\/intro\n/);
  const bad = snapshot(fx, ["http://["]);
  assert.equal(bad.code, 1);
  assert.equal(bad.err.trim(), "source http://[: not a valid URL");
});

test("a scanned PDF with no text layer stops the stage with a clear message and no sources.json", () => {
  const fx = fixture();
  const good = write(fx, "good.md", "# Good\n\nText.\n");
  assert.equal(snapshot(fx, [good]).code, 0);
  const f = write(fx, "scan.pdf", { pages: ["", "  \n "] });
  const s = snapshot(fx, [good, f]);
  assert.equal(s.code, 1);
  assert.equal(
    s.err.trim(),
    `source ${f}: a scanned PDF with no text layer, so there is nothing to read: give a PDF with selectable text, or the document as Markdown or text`,
  );
  assert.equal(s.out, "");
  assert.ok(!fs.existsSync(path.join(fx.dir, "snapshots", "sources.json")));
  assert.match(pack(fx).err, /pack: no snapshots\/sources\.json/);
});

test("the excerpt budget is 8 per minute of target length, at least 12, split across the sources", () => {
  const fx = fixture();
  const a = write(fx, "a.txt", "one\n");
  const b = write(fx, "b.txt", "two\n");
  const c = write(fx, "c.txt", "three\n");
  const budget = (args) => {
    const s = snapshot(fx, args);
    assert.equal(s.code, 0, s.err);
    return s.out.trim().split("\n").pop();
  };
  assert.equal(
    budget([a, b, c]),
    "budget: 16 excerpts (2 min at 8 per minute, at least 12); shares a 6, b 5, c 5",
  );
  assert.equal(
    budget(["--minutes", "1", a]),
    "budget: 12 excerpts (1 min at 8 per minute, at least 12); shares a 12",
  );
  assert.equal(
    budget(["--minutes", "2.5", a]),
    "budget: 20 excerpts (2.5 min at 8 per minute, at least 12); shares a 20",
  );
  assert.equal(snapshot(fx, ["--minutes", "0", a]).code, 2);

  budget([a, b, c]);
  draft(fx, "b", new Array(6).fill(["line 1", "two"]));
  const over = pack(fx, ["b"]);
  assert.equal(over.code, 1);
  assert.equal(
    over.err.trim(),
    "pack b: 6 excerpts over its share of 5 (budget 16)",
  );
});

test("an excerpt passes only word for word: whitespace may differ, a paraphrase may not", () => {
  const fx = fixture();
  const f = write(fx, "n.txt", "The gate blocks\n  a red   render.\n");
  assert.equal(snapshot(fx, [f]).code, 0);
  draft(fx, "n", [["lines 1-2", "The gate blocks a red render."]]);
  assert.equal(pack(fx, ["n"]).code, 0);
  draft(fx, "n", [["lines 1-2", "The gate stops a red render."]]);
  assert.match(pack(fx, ["n"]).err, /not word for word in lines 1-2/);
  draft(fx, "n", [["line 1", ""]]);
  assert.match(pack(fx, ["n"]).err, /excerpt 1: no text/);
});

test("a malformed draft gets a pack line to fix, not a crash", () => {
  const fx = fixture();
  const f = write(fx, "n.txt", "The gate blocks a red render.\n");
  assert.equal(snapshot(fx, [f]).code, 0);
  const at = path.join(fx.dir, "snapshots", "n.draft.json");
  for (const [body, why] of [
    ['{"summary":"ok","excerpts":[null]}', "pack n: excerpt 1: not an object"],
    ["null", 'pack n: a draft holds a "summary" and an "excerpts" list'],
  ]) {
    fs.writeFileSync(at, body);
    const r = pack(fx, ["n"]);
    assert.equal(r.code, 1);
    assert.equal(r.err.trim(), why);
  }
});

test("the merge numbers every excerpt across the pack and writes the excerpts and the outline, both committed", () => {
  const fx = fixture();
  const a = write(
    fx,
    "alpha.md",
    "# Alpha\n\n## One\n\nFirst fact.\n\n## Two\n\nSecond fact.\n",
  );
  const b = write(fx, "beta.txt", "Beta line.\n");
  assert.equal(snapshot(fx, [a, b]).code, 0);
  draft(
    fx,
    "alpha",
    [
      ["§ One", "First fact."],
      ["§ Two", "Second fact."],
    ],
    "Alpha in one line.",
  );
  const missing = pack(fx);
  assert.equal(missing.code, 1);
  assert.match(
    missing.err,
    /pack beta: no draft at snapshots\/beta\.draft\.json/,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "excerpts.json")));

  draft(fx, "beta", [["line 1", "Beta line."]], "Beta in one line.");
  const r = pack(fx);
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out.trim().split("\n").pop(),
    "pack: 3 excerpt(s) from 2 source(s) -> excerpts.json, outline.md",
  );
  const p = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "excerpts.json"), "utf8"),
  );
  assert.deepEqual(
    p.excerpts.map((e) => [e.id, e.source, e.locator, e.text]),
    [
      ["ex-1", "alpha", "§ One", "First fact."],
      ["ex-2", "alpha", "§ Two", "Second fact."],
      ["ex-3", "beta", "line 1", "Beta line."],
    ],
  );
  assert.deepEqual(
    p.sources.map((s) => [s.id, s.kind, s.title, s.summary]),
    [
      ["alpha", "md", "Alpha", "Alpha in one line."],
      ["beta", "txt", "beta.txt", "Beta in one line."],
    ],
  );
  assert.equal(p.budget, 16);
  const outline = fs.readFileSync(path.join(fx.dir, "outline.md"), "utf8");
  assert.match(outline, /^# Source pack\n\n3 excerpt\(s\) of a budget of 16/);
  assert.match(
    outline,
    /## alpha · md · Alpha\n\nSource: .*alpha\.md\n\nAlpha in one line\.\n\n- ex-1 · § One · note for § One\n- ex-2 · § Two · note for § Two\n/,
  );
  assert.match(outline, /- ex-3 · line 1 · note for line 1\n$/);
  // Snapshots and drafts stay out of git; the excerpts and outline are recipe.
  const ignore = fs.readFileSync(
    path.join(path.dirname(fx.dir), ".gitignore"),
    "utf8",
  );
  assert.match(ignore, /^\*\/snapshots\/$/m);
  assert.doesNotMatch(ignore, /excerpts|outline/);
});

test("a converter source with its tools not installed is refused before any read", () => {
  const fx = fixture({ tools: false });
  const f = write(fx, "design.pdf", { pages: ["Text."] });
  const s = snapshot(fx, [f]);
  assert.equal(s.code, 1);
  assert.equal(
    s.err.trim(),
    "source: npm-packages is not installed: run /explainer-video setup",
  );
  assert.ok(!fs.existsSync(fx.env.EXPLAINER_VIDEO_FAKE_LOG));
  // Markdown and text need no tool.
  assert.equal(snapshot(fx, [write(fx, "a.md", "# A\n")]).code, 0);
});

test("a topic run takes three to eight web pages, refuses anything else before a read, and records the topic", () => {
  const fx = fixture();
  const urls = "abcdefghi"
    .split("")
    .map((h) => `https://${h}.example.com/topic/page`);
  const env = {
    EXPLAINER_VIDEO_FAKE_PAGES: JSON.stringify(
      Object.fromEntries(
        urls.map((u, i) => [
          u,
          { title: `Page ${i + 1}`, html: "<h2>Merge</h2><p>It merges.</p>" },
        ]),
      ),
    ),
  };
  const log = path.join(fx.tmp, "calls.jsonl");
  const refused = (args, why) => {
    const r = snapshot(fx, ["--topic", "How ship merges", ...args], env);
    assert.equal(r.code, 1, r.out + r.err);
    assert.equal(r.err.trim(), why);
    assert.ok(!fs.existsSync(log), "nothing read");
  };
  refused(urls.slice(0, 2), "source: a topic takes 3 to 8 web pages, got 2");
  refused(urls, "source: a topic takes 3 to 8 web pages, got 9");
  const notes = write(fx, "notes.md", "# Notes\n");
  refused(
    [...urls.slice(0, 3), notes],
    `source ${notes}: a topic takes web pages only`,
  );
  const ok = snapshot(
    fx,
    ["--topic", "How ship merges", ...urls.slice(0, 3)],
    env,
  );
  assert.equal(ok.code, 0, ok.out + ok.err);
  assert.match(ok.out, /^topic: How ship merges · 3 page\(s\)$/m);
  const s = sourcesOf(fx);
  assert.equal(s.topic, "How ship merges");
  assert.deepEqual(
    s.sources.map((x) => [x.kind, x.source]),
    urls.slice(0, 3).map((u) => ["page", u]),
  );
  // A run from sources records no topic.
  assert.equal(snapshot(fx, [urls[0]], env).code, 0);
  assert.equal(sourcesOf(fx).topic, undefined);
});
