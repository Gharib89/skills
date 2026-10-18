// The style stage through its process doors, part 2: contrast nudges, roles and
// the fonts a draft fetches.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SLIDE } from "./fake-backend.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import { dest } from "../../skills/explainer-video/scripts/lib/tools.mjs";
import {
  candidates,
  fixture,
  loads,
  measuredRun,
  node,
  scripts,
} from "./style-lib.mjs";

// The cream slide's look with no colour above the saturation floor.
const GREY = [
  ["#f5f4ed", 80],
  ["#141413", 20],
];

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

test("a token no lightness can lift over its floor is refused, and nothing is written", () => {
  const SPLIT = [
    ["#f5f4ed", 60],
    ["#303030", 25],
    ["#141413", 15],
  ];
  const { run, env } = measuredRun(SPLIT, {
    bg: { candidate: "s1", why: "ground" },
    panel: { candidate: "s2", why: "the dark cards" },
    text: { candidate: "s3", why: "the body text" },
  });
  const r = node("draft.mjs", [run, "split"], env);
  assert.equal(r.status, 1);
  assert.match(
    r.stderr,
    /^style text: no lightness passes 4\.5:1 on bg and panel and chip$/m,
  );
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "split.json")));
  assert.ok(fs.existsSync(path.join(run, "style-draft", "refs")));
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
    panel: { candidate: "s2" },
  });
  const r = node("draft.mjs", [run, "acme"], env);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^style role accent: no candidate #ff0000$/m);
  assert.match(r.stderr, /^style role brand: not a token \(bg, /m);
  assert.match(
    r.stderr,
    /^style role panel: needs a one-line why, where the images show it$/m,
  );
  assert.match(
    r.stderr,
    /^style role text: required, every reference image shows a ground and its text$/m,
  );
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "acme.json")));
  assert.ok(fs.existsSync(path.join(run, "style-draft", "refs")));
});

// A site declaring the given font stacks, measured, with bg and text assigned;
// `roles(more)` rewrites roles.json with `more` beside them.
function fontRun(fonts) {
  const f = fixture();
  f.env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": { pages: [SLIDE], colors: [], fonts },
  });
  const r = node("measure.mjs", [f.run, "https://acme.test/"], f.env);
  assert.equal(r.status, 0, r.stderr);
  f.roles = (more) =>
    fs.writeFileSync(
      path.join(f.run, "style-draft", "roles.json"),
      JSON.stringify({
        bg: { candidate: "s1", why: "ground" },
        text: { candidate: "s3", why: "text" },
        ...more,
      }),
    );
  f.roles();
  f.out = path.join(f.run, "style-draft", "acme.json");
  f.draft = () => node("draft.mjs", [f.run, "acme"], f.env);
  f.profile = () => JSON.parse(fs.readFileSync(f.out, "utf8"));
  return f;
}

const BUNDLED = JSON.parse(
  fs.readFileSync(
    path.join(scripts, "..", "..", "styles", "claude-code.json"),
    "utf8",
  ),
);

test("a declared family Fontsource holds under an admitted licence plays its role, fetched into the font store", () => {
  const f = fontRun([
    { role: "title", stack: "'Noto Serif', Georgia, serif" },
    { role: "text", stack: "Inter, sans-serif" },
  ]);
  const r = f.draft();
  assert.equal(r.status, 0, r.stderr);
  const p = f.profile();
  assert.deepEqual(p.type.title, {
    font: "noto-serif",
    weight: 600,
    mark: "measured",
    why: "the source's title font, OFL-1.1",
  });
  assert.deepEqual(p.type.text, {
    font: "inter",
    weight: 400,
    mark: "measured",
    why: "the source's text font, OFL-1.1",
  });
  assert.deepEqual(p.type.code, BUNDLED.type.code);
  assert.deepEqual(p.type.arTitle, {
    font: "noto-naskh-arabic",
    weight: 600,
    mark: "derived",
    why: "the serif companion of noto-serif",
  });
  assert.equal(p.type.arText.font, "ibm-plex-sans-arabic");
  // Inter is a catalogue family; Noto Serif is not, so the draft carries its
  // row.
  assert.deepEqual(p.fonts, [
    {
      id: "font:noto-serif",
      kind: "font",
      family: "noto-serif",
      class: "serif",
      version: "5.3.0",
      files: ["latin-600-normal"],
      licence: "OFL-1.1",
    },
  ]);
  const dir = dest(
    p.fonts[0],
    userDirs({ platform: "linux", env: f.env, home: f.env.HOME }),
  );
  assert.ok(fs.existsSync(path.join(dir, ".stamp")));
  assert.ok(fs.existsSync(path.join(dir, "latin-600-normal.woff2")));
  const downloads = fs
    .readFileSync(f.env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l))
    .filter((l) => l.call === "download")
    .map((l) => l.url);
  assert.deepEqual(downloads, [
    "https://cdn.jsdelivr.net/fontsource/fonts/noto-serif@5.3.0/latin-600-normal.woff2",
  ]);
  assert.equal(loads(f.out, "acme").name, "acme");
  assert.match(
    r.stdout,
    /^style type title: noto-serif · measured · the source's title font, OFL-1\.1$/m,
  );
});

test("a draft fetching another weight of a family keeps the weight an earlier draft fetched", () => {
  const f = fontRun([{ role: "title", stack: "'Noto Serif', serif" }]);
  assert.equal(f.draft().status, 0);
  f.env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": {
      pages: [SLIDE],
      colors: [],
      fonts: [{ role: "text", stack: "'Noto Serif', serif" }],
    },
  });
  assert.equal(
    node("measure.mjs", [f.run, "https://acme.test/"], f.env).status,
    0,
  );
  f.roles();
  const r = f.draft();
  assert.equal(r.status, 0, r.stderr);
  const dir = dest(
    f.profile().fonts[0],
    userDirs({ platform: "linux", env: f.env, home: f.env.HOME }),
  );
  assert.deepEqual(fs.readdirSync(dir).sort(), [
    ".stamp",
    "latin-400-normal.woff2",
    "latin-600-normal.woff2",
  ]);
});

test("a family Fontsource cannot hold is replaced by the admitted family roles.json names, of the same class", () => {
  const f = fontRun([
    { role: "title", stack: "Georgia" },
    { role: "text", stack: '"Helvetica Neue", Arial, sans-serif' },
  ]);
  const refused = (fonts, why) => {
    f.roles({ fonts });
    const r = f.draft();
    assert.equal(r.status, 1, r.stdout);
    assert.match(r.stderr, why);
    assert.ok(!fs.existsSync(f.out));
  };
  refused(
    {},
    /^style font Helvetica Neue: not on Fontsource: name an admitted replacement in roles\.json `fonts`/m,
  );
  const sans = { font: "open-sans", why: "the nearest neutral sans" };
  refused(
    { "Helvetica Neue": sans, Georgia: { font: "noto-serif", why: "x" } },
    /^style font Georgia: its stack names no generic family: give its class/m,
  );
  refused(
    {
      "Helvetica Neue": { font: "noto-serif", why: "x" },
      Georgia: { font: "noto-serif", class: "serif", why: "x" },
    },
    /^style font Helvetica Neue: noto-serif is serif, the source's is sans$/m,
  );
  refused(
    {
      "Helvetica Neue": { font: "ubuntu", why: "x" },
      Georgia: { font: "noto-serif", class: "serif", why: "x" },
    },
    /^style font Helvetica Neue: ubuntu has licence UFL-1\.0, only OFL-1\.1 or Apache-2\.0$/m,
  );

  f.roles({
    fonts: {
      "Helvetica Neue": sans,
      Georgia: {
        font: "noto-serif",
        class: "serif",
        why: "a transitional serif like Georgia",
      },
    },
  });
  const r = f.draft();
  assert.equal(r.status, 0, r.stderr);
  const p = f.profile();
  assert.deepEqual(p.type.text, {
    font: "open-sans",
    weight: 400,
    mark: "replaced",
    was: "Helvetica Neue",
    why: "the nearest neutral sans",
  });
  assert.equal(p.type.title.was, "Georgia");
  assert.equal(p.type.arTitle.font, "noto-naskh-arabic");
  assert.equal(p.type.arText.font, "ibm-plex-sans-arabic");
  assert.deepEqual(
    p.fonts.map((r) => r.id),
    ["font:noto-serif", "font:open-sans"],
  );
});

test("a source declaring no family keeps the bundled type roles", () => {
  const f = fontRun([{ role: "text", stack: "system-ui, sans-serif" }]);
  const r = f.draft();
  assert.equal(r.status, 0, r.stderr);
  const p = f.profile();
  assert.deepEqual(p.type, BUNDLED.type);
  assert.ok(!("fonts" in p));
  assert.doesNotMatch(r.stdout, /^style type/m);
});
