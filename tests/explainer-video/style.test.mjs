// Style extraction through its process doors: sources turned into reference
// images and measured into colour candidates, then roles assigned by id and a
// draft profile written. The fake backend stands in for Chrome, pdf.js and
// ffmpeg: every reference image it writes or decodes holds a binary PPM.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SLIDE, bandsPpm } from "./fake-backend.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import { loadStyle } from "../../skills/explainer-video/scripts/lib/style.mjs";
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
  "style",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// The cream slide's look with no colour above the saturation floor.
const GREY = [
  ["#f5f4ed", 80],
  ["#141413", 20],
];

function fixture({ tools = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-style-"));
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
  const run = path.join(tmp, "proj", "explainers", "acme");
  fs.mkdirSync(run, { recursive: true });
  const docs = path.join(tmp, "docs");
  fs.mkdirSync(docs);
  return { tmp, run, docs, env };
}

const node = (script, args, env) =>
  spawnSync(process.execPath, [path.join(scripts, script), ...args], {
    env,
    encoding: "utf8",
  });

const candidates = (run) =>
  JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "candidates.json"), "utf8"),
  );

test("screenshots measure into the same candidates every time", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "one.png"), bandsPpm(SLIDE));
  fs.writeFileSync(path.join(docs, "two.png"), bandsPpm(SLIDE));
  const args = [run, path.join(docs, "one.png"), path.join(docs, "two.png")];
  const first = node("measure.mjs", args, env);
  assert.equal(first.status, 0, first.stderr);
  const kept = fs.readFileSync(
    path.join(run, "style-draft", "candidates.json"),
    "utf8",
  );
  const again = node("measure.mjs", args, env);
  assert.equal(again.status, 0, again.stderr);
  assert.equal(
    fs.readFileSync(path.join(run, "style-draft", "candidates.json"), "utf8"),
    kept,
  );

  const c = candidates(run);
  assert.deepEqual(
    c.images.map((i) => i.name),
    ["one-1.png", "two-1.png"],
  );
  assert.deepEqual(
    c.surfaces.map((s) => s.hex),
    ["#f5f4ed", "#ffffff", "#141413", "#cc6c54"],
  );
  assert.deepEqual(c.surfaces[0].images, ["one-1.png", "two-1.png"]);
  assert.equal(c.surfaces[0].share, 0.7);
  assert.deepEqual(
    c.accents.map((a) => a.hex),
    ["#cc6c54"],
  );
  assert.match(
    first.stdout,
    /^style candidate a1: #cc6c54 · 6% · one-1\.png, two-1\.png$/m,
  );
  assert.match(first.stdout, /^style: measured 2 reference image\(s\) -> /m);
});

test("a website's declared colours count only where its pages show them", () => {
  const { run, env } = fixture();
  env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": {
      pages: [SLIDE, SLIDE],
      colors: ["#cc6c55", "#00ff00"],
      fonts: ["Source Serif 4"],
    },
  });
  const r = node("measure.mjs", [run, "https://acme.test/"], env);
  assert.equal(r.status, 0, r.stderr);
  const c = candidates(run);
  assert.deepEqual(
    c.images.map((i) => i.name),
    ["acme-test-1.png", "acme-test-2.png"],
  );
  assert.deepEqual(c.accents[0], {
    id: "a1",
    hex: "#cc6c55",
    share: 0.06,
    images: ["acme-test-1.png", "acme-test-2.png"],
    declared: true,
  });
  assert.ok(![...c.surfaces, ...c.accents].some((x) => x.hex === "#00ff00"));
  assert.deepEqual(c.fonts, ["Source Serif 4"]);
  assert.match(
    r.stdout,
    /^style declared #00ff00: not in the reference images, dropped$/m,
  );
  const call = fs
    .readFileSync(env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l))
    .find((l) => l.call === "capturePages");
  assert.equal(call.max, 5);

  fs.writeFileSync(
    path.join(run, "style-draft", "roles.json"),
    JSON.stringify({
      bg: { candidate: "s1", why: "ground" },
      text: { candidate: "s3", why: "text" },
      accent: { candidate: "a1", why: "the declared brand colour" },
    }),
  );
  const d = node("draft.mjs", [run, "acme"], env);
  assert.equal(d.status, 0, d.stderr);
  const p = JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "acme.json"), "utf8"),
  );
  assert.equal(p.source, "Extracted from website https://acme.test/");
  assert.equal(p.marks.accent.declared, true);
});

test("a deck and a video become at most twelve images each", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  fs.writeFileSync(path.join(docs, "talk.mp4"), "mp4");
  env.EXPLAINER_VIDEO_FAKE_FRAMES = "15";
  const r = node(
    "measure.mjs",
    [run, path.join(docs, "deck.pdf"), path.join(docs, "talk.mp4")],
    env,
  );
  assert.equal(r.status, 0, r.stderr);
  const names = candidates(run).images.map((i) => i.name);
  assert.equal(names.filter((n) => n.startsWith("deck-")).length, 12);
  assert.equal(names.filter((n) => n.startsWith("talk-")).length, 12);
  assert.match(r.stdout, /^style ref deck-1\.png: pdf · /m);
  assert.match(r.stdout, /^style ref talk-1\.png: video · /m);
});

test("a PPTX alone has no pixels; beside its PDF its theme confirms colours", () => {
  const { run, docs, env } = fixture();
  const deck = path.join(docs, "deck.pptx");
  // The fake unzip reads a JSON file of parts.
  fs.writeFileSync(
    deck,
    JSON.stringify({
      parts: {
        "ppt/theme/theme1.xml":
          '<a:theme><a:themeElements><a:clrScheme name="Acme"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:accent1><a:srgbClr val="CC6C55"/></a:accent1></a:clrScheme><a:fontScheme><a:majorFont><a:latin typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Inter"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>',
      },
    }),
  );
  const alone = node("measure.mjs", [run, deck], env);
  assert.equal(alone.status, 1);
  assert.match(alone.stderr, /export the deck to PDF/);
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "candidates.json")));

  fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  const both = node(
    "measure.mjs",
    [run, deck, path.join(docs, "deck.pdf")],
    env,
  );
  assert.equal(both.status, 0, both.stderr);
  const c = candidates(run);
  assert.equal(c.accents[0].hex, "#cc6c55");
  assert.deepEqual(c.fonts, ["Georgia", "Inter"]);
  assert.match(
    both.stdout,
    /^style declared #000000: not in the reference images, dropped$/m,
  );
});

test("a source measure cannot take is refused by name, and nothing is written", () => {
  const { run, docs, env } = fixture({ tools: false });
  fs.writeFileSync(path.join(docs, "notes.txt"), "notes");
  const r = node(
    "measure.mjs",
    [
      run,
      path.join(docs, "gone.png"),
      path.join(docs, "notes.txt"),
      "https://acme.test/",
    ],
    env,
  );
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^source .*gone\.png: no such file$/m);
  assert.match(
    r.stderr,
    /^source .*notes\.txt: cannot take \.txt: give a web page URL or a file ending \.png, /m,
  );
  assert.match(
    r.stderr,
    /^style: chrome is not installed: run \/explainer-video setup$/m,
  );
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "candidates.json")));
});

test("an image measure cannot decode is refused by its source, not a stack trace", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "broken.png"), "not an image");
  const r = node("measure.mjs", [run, path.join(docs, "broken.png")], env);
  assert.equal(r.status, 1);
  assert.match(
    r.stderr,
    /^source .*broken\.png: could not read broken-1\.png: not a binary PPM$/m,
  );
  assert.doesNotMatch(r.stderr, /\n\s+at /);
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "candidates.json")));
});

// A run measured from two screenshots of `bands`, with `roles` written as
// Claude writes them.
function measuredRun(bands, roles) {
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
function loads(file, name) {
  const run = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-style-load-"));
  temps.push(run);
  fs.copyFileSync(file, path.join(run, "style.json"));
  return loadStyle(run, name);
}

test("a draft marks each token measured or derived, loads, and keeps no reference image", () => {
  const { run, env } = measuredRun(SLIDE, {
    bg: { candidate: "s1", why: "the ground of every slide" },
    panel: { candidate: "s2", why: "the cards" },
    text: { candidate: "s3", why: "the body text" },
    accent: { candidate: "a1", why: "the one brand colour" },
  });
  assert.ok(fs.existsSync(path.join(run, "style-draft", "refs")));
  const r = node("draft.mjs", [run, "acme"], env);
  assert.equal(r.status, 0, r.stderr);
  const file = path.join(run, "style-draft", "acme.json");
  const p = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(p.name, "acme");
  assert.deepEqual(
    [p.colors.bg, p.colors.panel, p.colors.text, p.colors.accent],
    ["#f5f4ed", "#ffffff", "#141413", "#cc6c54"],
  );
  assert.deepEqual(p.marks.bg, {
    mark: "measured",
    candidate: "s1",
    images: ["one-1.png", "two-1.png"],
    why: "the ground of every slide",
  });
  for (const t of ["chip", "line", "rule", "muted", "faint", "ok", "warn"])
    assert.equal(p.marks[t].mark, "derived", t);
  assert.equal(Object.keys(p.marks).length, 12);
  assert.equal(loads(file, "acme").name, "acme");
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "refs")));
  assert.match(
    fs.readFileSync(path.join(run, "..", ".gitignore"), "utf8"),
    /^\*\/style-draft\/$/m,
  );
  assert.match(
    r.stdout,
    /^style bg: #f5f4ed · measured · the ground of every slide$/m,
  );
  assert.match(r.stdout, /^style: draft acme -> .*acme\.json$/m);
});

test("a token under its contrast floor is nudged in lightness and marked adjusted", () => {
  const PALE = [
    ["#f5f4ed", 80],
    ["#141413", 14],
    ["#e8a090", 6],
  ];
  const { run, env } = measuredRun(PALE, {
    bg: { candidate: "s1", why: "ground" },
    text: { candidate: "s2", why: "text" },
    accent: { candidate: "a1", why: "the pale brand colour" },
  });
  const r = node("draft.mjs", [run, "pale"], env);
  assert.equal(r.status, 0, r.stderr);
  const file = path.join(run, "style-draft", "pale.json");
  const p = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(p.marks.accent.mark, "adjusted");
  assert.equal(p.marks.accent.was, "#e8a090");
  assert.notEqual(p.colors.accent, "#e8a090");
  assert.match(
    p.marks.accent.why,
    /^accent on bg 1\.\d\d:1 under 3:1, moved to 3\.\d\d:1$/,
  );
  assert.equal(loads(file, "pale").name, "pale");
});

test("a monochrome source gets the default accent hue, derived", () => {
  const { run, env } = measuredRun(GREY, {
    bg: { candidate: "s1", why: "ground" },
    text: { candidate: "s2", why: "text" },
  });
  assert.deepEqual(candidates(run).accents, []);
  const r = node("draft.mjs", [run, "grey"], env);
  assert.equal(r.status, 0, r.stderr);
  const p = JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "grey.json"), "utf8"),
  );
  assert.equal(p.marks.accent.mark, "derived");
});

test("a role names a candidate id, never a colour, and bg and text are required", () => {
  const { run, env } = measuredRun(SLIDE, {
    bg: { candidate: "s1", why: "ground" },
    accent: { candidate: "#ff0000", why: "made up" },
    brand: { candidate: "a1", why: "not a token" },
  });
  const r = node("draft.mjs", [run, "acme"], env);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^style role accent: no candidate #ff0000$/m);
  assert.match(r.stderr, /^style role brand: not a token \(bg, /m);
  assert.match(
    r.stderr,
    /^style role text: required, every reference image shows a ground and its text$/m,
  );
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "acme.json")));
  assert.ok(fs.existsSync(path.join(run, "style-draft", "refs")));
});
