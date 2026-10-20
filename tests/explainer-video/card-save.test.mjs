// The style card through its process door, part 3: Save, Use once, fetched
// fonts, edits applied and the bundled profile.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { judged } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  failures,
  loadStyle,
  saveScope,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import { dest } from "../../skills/explainer-video/scripts/lib/tools.mjs";
import {
  answer,
  built,
  card,
  fixture,
  json,
  latestCard,
  read,
  skill,
} from "./card-lib.mjs";

test("Save writes the project store from a project copy, refuses a taken name without Replace, and names the default", () => {
  const fx = fixture();
  built(fx);
  const head =
    "explainer-video: style card 1 answers (database document answers/card-1)\n";
  let r = answer(fx, head + "Choice: Save\nName: acme\nDefault: yes\n");
  assert.equal(r.code, 0, r.err);
  assert.equal(
    r.out.trim(),
    `card: saved acme -> ${path.join(fx.project, "acme.json")}, default of the project store`,
  );
  assert.equal(json(fx.project, "acme.json").colors.accent, "#c03020");
  assert.equal(read(fx.project, "default"), "acme\n");
  r = answer(fx, head + "Choice: Save\nName: acme\n");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /acme is saved in the project store already: tick Replace/,
  );
  r = answer(fx, head + "Choice: Save\nName: acme\nReplace: yes\n");
  assert.equal(r.code, 0, r.err);
  // A run that names no style now takes the store's default.
  fs.rmSync(path.join(fx.dir, "style.json"), { force: true });
  assert.equal(
    loadStyle(fx.dir, undefined, {
      config: path.join(fx.tmp, "config", "explainer-video"),
    }).name,
    "acme",
  );
});

test("a copy of the skill under ~/.claude/skills saves to the user store, --project forces the project, and a project profile of the name refuses a user save", () => {
  const fx = fixture();
  const copy = path.join(fx.env.HOME, ".claude", "skills", "explainer-video");
  fs.cpSync(skill, copy, { recursive: true });
  let r = card(fx, ["build"], { at: copy });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(latestCard(fx).scope, "user");
  const f = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(
    f,
    "explainer-video: style card 1 answers (database document answers/card-1)\nChoice: Save\nName: acme\n",
  );
  r = card(fx, ["apply", f], { at: copy });
  assert.equal(r.code, 0, r.err);
  assert.ok(fs.existsSync(path.join(fx.user, "acme.json")));
  assert.ok(!fs.existsSync(fx.project));
  r = card(fx, ["apply", f, "--project"], { at: copy });
  assert.equal(r.code, 0, r.err);
  assert.ok(fs.existsSync(path.join(fx.project, "acme.json")));
  fs.appendFileSync(f, "Replace: yes\n");
  r = card(fx, ["apply", f], { at: copy });
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /the project store holds a acme that would hide this one/,
  );
  r = card(fx, ["build", "--project"], { at: copy });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(latestCard(fx).scope, "project");
  assert.deepEqual(latestCard(fx).taken, ["acme"]);
});

test("card refuses what it cannot apply or record, naming why", () => {
  const fx = fixture();
  built(fx);
  const head =
    "explainer-video: style card 1 answers (database document answers/card-1)\n";
  for (const [body, why] of [
    [
      "Choice: Save\nName: acme\nShade: red\n",
      /cannot read this answers line: Shade: red/,
    ],
    ["Name: acme\n", /the answers hold no choice/],
    ["Choice: Save\nName: Acme Co\n", /name Acme Co is not kebab-case/],
    [
      "Choice: Save\nName: acme\nColour glow: #ffffff\n",
      /no colour token glow/,
    ],
    [
      "Choice: Save\nName: acme\nColour bg: white\n",
      /bg white is not a #rrggbb colour/,
    ],
    [
      "Choice: Save\nName: acme\nFont arTitle: inter\n",
      /no type role arTitle on the card/,
    ],
    [
      "Choice: Save\nName: acme\nFont title: comic-sans\n",
      /font comic-sans for title is not one setup installs/,
    ],
  ]) {
    const r = answer(fx, head + body);
    assert.equal(r.code, 1, body);
    assert.match(r.err, why, body);
  }
  for (const [args, code, why] of [
    [["page", "http://claude.ai/x"], 1, /is not an https:\/\/ URL/],
    [
      ["asset", "../x.woff2=https://a/b"],
      1,
      /is not a file under the run folder/,
    ],
    [
      ["asset", "style-draft=https://a/b"],
      1,
      /style-draft is not a file under the run folder/,
    ],
    [
      ["asset", "style-draft/acme.json=ftp://a/b"],
      1,
      /neither an https:\/\/ URL nor \/_blob/,
    ],
    [["build", "--local", "--local"], 2, /usage/],
  ]) {
    const r = card(fx, args);
    assert.equal(r.code, code, args.join(" "));
    assert.match(r.err, why, args.join(" "));
  }
});

test("Use once writes the draft to the run's style.json and no store; the run keeps it when it names it", () => {
  const fx = fixture();
  built(fx);
  const r = answer(
    fx,
    "explainer-video: style card 1 answers (database document answers/card-1)\nChoice: Use once\nName: acme-trial\n",
  );
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out.trim(), "card: once acme-trial -> style.json");
  assert.ok(!fs.existsSync(fx.project) && !fs.existsSync(fx.user));
  assert.equal(json(fx.dir, "style.json").name, "acme-trial");
  assert.equal(
    loadStyle(fx.dir, "acme-trial", { config: path.join(fx.tmp, "nowhere") })
      .label,
    "Acme",
  );
});

test("a draft carrying a family it fetched builds with it, offers it, and shows the font it replaced", () => {
  const row = {
    id: "font:noto-serif",
    kind: "font",
    family: "noto-serif",
    class: "serif",
    version: "5.3.0",
    files: ["latin-600-normal"],
    licence: "OFL-1.1",
  };
  const fx = fixture({
    type: {
      ...json(skill, "styles", "itworx.json").type,
      title: {
        font: "noto-serif",
        weight: 600,
        mark: "replaced",
        was: "Georgia",
        why: "a transitional serif like Georgia",
      },
    },
    fonts: [row],
  });
  const store = dest(
    row,
    userDirs({ platform: "linux", env: fx.env, home: fx.env.HOME }),
  );
  fs.mkdirSync(store, { recursive: true });
  fs.writeFileSync(path.join(store, ".stamp"), "");
  fs.writeFileSync(path.join(store, "latin-600-normal.woff2"), "woff2");
  built(fx);
  const c = latestCard(fx);
  assert.ok(c.families.includes("noto-serif"));
  assert.deepEqual(
    c.type.find((x) => x.role === "title"),
    {
      role: "title",
      font: "noto-serif",
      mark: "replaced",
      why: "a transitional serif like Georgia",
    },
  );
  assert.ok(
    c.fonts.some((f) => f.file === "noto-serif-latin-600-normal.woff2"),
  );
  const r = answer(
    fx,
    "explainer-video: style card 1 answers (database document answers/card-1)\nChoice: Save\nName: acme\nFont text: noto-serif\n",
  );
  assert.equal(r.code, 0, r.err);
  // The draft fetched noto-serif at 600 only, so text takes that weight.
  assert.deepEqual(json(fx.dir, "style-draft", "acme.json").type.text, {
    weight: 600,
    font: "noto-serif",
    mark: "edited",
    why: "edited on the style card",
  });
  assert.deepEqual(json(fx.dir, "style-draft", "acme.json").type.arText, {
    font: "noto-naskh-arabic",
    weight: 400,
    mark: "derived",
    why: "the serif companion of noto-serif",
  });
});

test("edits go into the draft, marked, and need the next version; answers to an old version are refused", () => {
  const fx = fixture();
  built(fx);
  const head =
    "explainer-video: style card 1 answers (database document answers/card-1)\n";
  let r = answer(
    fx,
    head +
      "Choice: Save\nName: acme\nColour accent: #B02818\nFont title: inter\n",
  );
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out.trim(), "card: rebuild");
  assert.ok(!fs.existsSync(fx.project));
  const draft = json(fx.dir, "style-draft", "acme.json");
  assert.equal(draft.colors.accent, "#b02818");
  assert.deepEqual(draft.marks.accent, {
    mark: "edited",
    was: "#c03020",
    why: "edited on the style card",
  });
  assert.equal(draft.type.title.font, "inter");
  assert.equal(draft.type.title.mark, "edited");
  // A sans title takes the sans Arabic companion.
  assert.deepEqual(draft.type.arTitle, {
    font: "ibm-plex-sans-arabic",
    weight: 600,
    mark: "derived",
    why: "the sans companion of inter",
  });
  built(fx);
  const c = latestCard(fx);
  assert.equal(c.version, 2);
  assert.equal(c.colors.find((x) => x.token === "accent").mark, "edited");
  assert.equal(c.type.find((x) => x.role === "title").font, "inter");
  r = answer(fx, head + "Choice: Save\nName: acme\n");
  assert.equal(r.code, 1);
  assert.match(r.err, /answers for card 1, the latest is card 2/);
  r = answer(
    fx,
    head.replace(/1/g, "2") + "Choice: Revise\nName: acme\nNote: warmer\n",
  );
  assert.equal(r.code, 0, r.err);
  assert.equal(r.out.trim(), "card: revise: warmer");
});

test("an edit under the contrast floor and a findings card's Save are refused by apply too", () => {
  const fx = fixture({ label: "Acme tiny" });
  built(fx);
  const head =
    "explainer-video: style card 1 answers (database document answers/card-1)\n";
  let r = answer(fx, head + "Choice: Use once\nName: acme\n");
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /card 1 has 1 finding\(s\): revise the draft before using it/,
  );
  r = answer(fx, head + "Choice: Save\nName: acme\nColour muted: #c8c8c0\n");
  assert.equal(r.code, 1);
  assert.match(r.err, /fails contrast: .*muted on bg/);
});

test("a published card needs every font uploaded first, then loads them from their URLs", () => {
  const fx = fixture();
  let r = card(fx, ["page", "https://claude.ai/artifact/abc"]);
  assert.equal(r.code, 0, r.err);
  r = card(fx, ["build"]);
  assert.equal(r.code, 1);
  const uploads = [...r.err.matchAll(/^card: upload (\S+) /gm)].map(
    (m) => m[1],
  );
  assert.ok(uploads.length > 0);
  // One call per upload: each keeps the entries the calls before it recorded.
  uploads.forEach((u, i) => {
    r = card(fx, ["asset", `${u}=/_blob/${String(i).padStart(32, "0")}`]);
    assert.equal(r.code, 0, r.err);
  });
  r = built(fx);
  assert.match(r.out, /^card: post style-draft\/card\/1\.json to cards\/1$/m);
  assert.ok(latestCard(fx).fonts.every((f) => f.url.startsWith("/_blob/")));
  // The local copy still loads the files beside it.
  assert.match(
    read(fx.dir, "style-draft", "card", "stylecard.html"),
    /"url":"frames\/fonts\//,
  );
  r = card(fx, ["page"]);
  assert.equal(r.code, 0, r.err);
  assert.match(
    read(fx.dir, "style-draft", "card", "page.html"),
    /<title>Style card: Acme<\/title>/,
  );
});

test("saveScope: user under ~/.claude/skills or ~/.agents/skills, else project", () => {
  const home = "/home/u";
  assert.equal(
    saveScope("/home/u/.claude/skills/explainer-video", home),
    "user",
  );
  assert.equal(
    saveScope("/home/u/.agents/skills/explainer-video", home),
    "user",
  );
  assert.equal(
    saveScope("/home/u/repo/.claude/skills/explainer-video", home),
    "project",
  );
  assert.equal(
    saveScope("/home/u/.claude/skills-old/explainer-video", home),
    "project",
  );
  assert.equal(saveScope("/srv/skills/explainer-video", home), "project");
});

test("the bundled ITWorx profile loads, passes contrast by role and renders the fixture video through every gate", () => {
  const itworx = json(skill, "styles", "itworx.json");
  assert.deepEqual(failures(itworx), []);
  assert.doesNotThrow(() => validate(itworx));
  assert.equal(itworx.colors.bg, "#ffffff");
  const fx = fixture();
  fs.writeFileSync(
    path.join(fx.dir, "script.md"),
    SCRIPT.replace("style: claude-code", "style: itworx"),
  );
  const stage = (s) =>
    spawnSync(process.execPath, [path.join(skill, "scripts", s), fx.dir], {
      env: fx.env,
      encoding: "utf8",
    });
  for (const s of ["script/compile.mjs", "voice/voice.mjs"]) {
    const r = stage(s);
    assert.equal(r.status, 0, `${s}: ${r.stdout}${r.stderr}`);
  }
  const r = judged(fx.dir, () => {
    const x = stage("render/render.mjs");
    return { code: x.status, out: x.stdout, err: x.stderr };
  });
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gates: 8 pass, 0 fail$/m);
  assert.equal(json(fx.dir, "style.json").name, "itworx");
  assert.match(read(fx.dir, "composition", "index.html"), /--bg: #ffffff;/);
});
