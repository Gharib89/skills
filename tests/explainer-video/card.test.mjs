// The style card through its doors: `card.mjs` builds a card from a draft with
// the canned backend, the page (storyboard/card.html) runs headless over the
// card it built and reads and writes only what card-data.md documents, and its
// answers come back through `card.mjs apply` to save, use once or rebuild. The
// bundled ITWorx profile renders the fixture video through every gate.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { judged } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  failures,
  loadStyle,
  saveScope,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "explainer-video");
const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
const json = (...p) => JSON.parse(read(...p));
const html = read(skill, "storyboard", "card.html");
const doc = read(skill, "storyboard", "card-data.md");
const clone = (o) => JSON.parse(JSON.stringify(o));

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine as render.test.mjs lays it out, with a draft in the run's
// style-draft/ made from the bundled ITWorx profile.
function fixture(draft = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-card-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CONFIG_HOME: path.join(tmp, "config"),
    XDG_DATA_HOME: path.join(tmp, "data"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    XDG_VIDEOS_DIR: path.join(tmp, "videos"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  const dirs = userDirs({ platform: "linux", env, home: env.HOME });
  for (const r of catalogue().filter((r) =>
    ["npm", "chrome", "font"].includes(r.kind),
  )) {
    const d = dest(r, dirs);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
    for (const f of r.files ?? [])
      fs.writeFileSync(path.join(d, `${f}.woff2`), "woff2");
  }
  const gsap = path.join(dest({ kind: "npm" }, dirs), "node_modules", "gsap");
  fs.mkdirSync(path.join(gsap, "dist"), { recursive: true });
  fs.writeFileSync(path.join(gsap, "dist", "gsap.min.js"), "/* gsap */");
  const dir = path.join(tmp, "proj", "explainers", "demo");
  fs.mkdirSync(path.join(dir, "style-draft"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, "style-draft", "acme.json"),
    JSON.stringify({
      ...json(skill, "styles", "itworx.json"),
      name: "acme",
      label: "Acme",
      source: "https://acme.example",
      marks: { accent: { mark: "measured", why: "the logo's red" } },
      ...draft,
    }),
  );
  fs.writeFileSync(path.join(dir, "script.md"), SCRIPT);
  return {
    tmp,
    dir,
    env,
    log: env.EXPLAINER_VIDEO_FAKE_LOG,
    project: path.join(tmp, "proj", "explainers", ".styles"),
    user: path.join(tmp, "config", "explainer-video", "styles"),
  };
}

function card(fx, args, { extra = {}, at = skill } = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(at, "scripts", "style", "card.mjs"), fx.dir, "acme", ...args],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}
function built(fx, args = ["build"]) {
  const r = card(fx, args);
  assert.equal(r.code, 0, r.out + r.err);
  return r;
}
const latestCard = (fx) => {
  const ns = fs
    .readdirSync(path.join(fx.dir, "style-draft", "card"))
    .map((f) => f.match(/^(\d+)\.json$/)?.[1])
    .filter(Boolean)
    .map(Number);
  return json(fx.dir, "style-draft", "card", `${Math.max(...ns)}.json`);
};
function answer(fx, text, args = []) {
  const f = path.join(fx.tmp, "answers.txt");
  fs.writeFileSync(f, text);
  return card(fx, ["apply", f, ...args]);
}
const calls = (fx, name) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];

// The documented shape: every table row whose first cell is a card. or
// answers. path; a `map` is checked as a leaf.
const shape = new Map();
for (const m of doc.matchAll(
  /^\| `((?:card|answers)\.[^`]+)` \| ([^|]+) \| (\w+) \|/gm,
))
  shape.set(m[1], { type: m[2].trim(), req: m[3] });
function objects(v, p, acc = []) {
  if (Array.isArray(v)) v.forEach((x) => objects(x, p + "[]", acc));
  else if (v && typeof v === "object" && shape.get(p)?.type !== "map") {
    acc.push([p, v]);
    for (const k of Object.keys(v)) objects(v[k], p + "." + k, acc);
  }
  return acc;
}
function shapeProblems(d, root) {
  const out = [];
  const all = objects(d, root);
  for (const [p, o] of all)
    for (const k of Object.keys(o))
      if (!shape.has(p + "." + k)) out.push(`undocumented field ${p}.${k}`);
  for (const [f, { req }] of shape) {
    if (!f.startsWith(root + ".") || req !== "yes") continue;
    const parent = f.slice(0, f.lastIndexOf("."));
    const key = f.slice(f.lastIndexOf(".") + 1);
    for (const [p, o] of all)
      if (p === parent && !(key in o)) out.push(`lacks required field ${f}`);
  }
  return out;
}

// The page's code, run with no document so it boots nothing and exposes its core.
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);
const ctx = vm.createContext({ console });
vm.runInContext(
  scripts[0] +
    "\n;globalThis.__page = { newState, setCards, setAnswers, view, ACT, answersDoc, answersText, frameDoc, failing, mediaUrl };",
  ctx,
);
const P = ctx.__page;
const seen = new Set();
function watch(v, p) {
  if (!v || typeof v !== "object") return v;
  return new Proxy(v, {
    get(t, k, r) {
      if (typeof k === "symbol") return Reflect.get(t, k, r);
      if (Array.isArray(t))
        return /^\d+$/.test(k) ? watch(t[k], p + "[]") : Reflect.get(t, k, r);
      seen.add(p + "." + k);
      return watch(t[k], p + "." + k);
    },
  });
}
function session(docs, answered = []) {
  const S = P.newState("Style card: Acme");
  P.setCards(
    S,
    docs.map((d) => watch(clone(d), "card")),
  );
  P.setAnswers(S, answered);
  P.view(S);
  return S;
}
const submitOff = (v) => /<button[^>]*id="submit"[^>]*\sdisabled/.test(v);

test("build gates five sample frames with check and the probe, each mid-way through its own second, and writes card 1", () => {
  const fx = fixture();
  const r = built(fx);
  assert.match(
    r.out,
    /^card 1: 5 frame\(s\), 0 finding\(s\) -> style-draft\/card\/1\.json$/m,
  );
  assert.match(r.out, /^card: local page style-draft\/card\/stylecard\.html$/m);
  // Each frame holds a second, measured mid-way: HyperFrames' seek leaves
  // some clips a frame long unmounted.
  const times = [0.5, 1.5, 2.5, 3.5, 4.5];
  assert.deepEqual(calls(fx, "check")[0].times, times);
  assert.deepEqual(calls(fx, "probe")[0].times, times);
  const c = latestCard(fx);
  assert.deepEqual(
    c.frames.map((f) => f.id),
    ["title", "diagram", "caption", "code", "arabic"],
  );
  assert.equal(c.scope, "project");
  assert.deepEqual(c.taken, []);
  assert.equal(c.colors.find((x) => x.token === "accent").mark, "measured");
  assert.equal(c.colors.find((x) => x.token === "bg").mark, "bundled");
  // The caption frame holds a still cue, its first words said.
  const caption = c.frames.find((f) => f.id === "caption").html;
  assert.match(caption, /<div class="captions"><div class="cue clip">/);
  assert.match(caption, /<span class="w" style="color: var\(--text\)">Each</);
  // A frame runs no script and loads its fonts from fonts/.
  for (const f of c.frames) {
    assert.match(f.html, /<script>\s*<\/script>/);
    assert.match(f.html, /url\("fonts\/[^"]+\.woff2"\)/);
  }
  assert.match(
    c.frames.find((f) => f.id === "arabic").html,
    /dir="rtl"[\s\S]*فيديو شرح/,
  );
  // The local page embeds the same card, its fonts beside it.
  const local = read(fx.dir, "style-draft", "card", "stylecard.html");
  assert.match(
    local,
    /^<!doctype html>\n<meta charset="utf-8">\n<title>Style card: Acme<\/title>/,
  );
  const embedded = JSON.parse(
    local.match(
      /<script type="application\/json" id="card">(.*?)<\/script>/s,
    )[1],
  );
  assert.deepEqual(embedded, c);
  for (const f of c.fonts)
    assert.ok(
      fs.existsSync(path.join(fx.dir, "style-draft", "card", f.url)),
      f.url,
    );
});

test("the built card holds to the documented shape, and the checker refuses a malformed one", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  assert.ok(shape.size > 30, "no field table in card-data.md");
  assert.deepEqual(shapeProblems(c, "card"), []);
  const bad = clone(c);
  delete bad.colors[0].why;
  bad.frames[0].mood = "calm";
  const problems = shapeProblems(bad, "card");
  assert.ok(
    problems.some((p) => /lacks required field card\.colors\[\]\.why/.test(p)),
  );
  assert.ok(
    problems.some((p) => /undocumented field card\.frames\[\]\.mood/.test(p)),
  );
});

test("the page is one inline code script with the title placeholder once and an empty embedded card", () => {
  assert.equal(scripts.length, 1);
  assert.doesNotThrow(() => new vm.Script(scripts[0]));
  assert.match(html, /<title>\{\{TITLE\}\}<\/title>/);
  assert.equal(html.split("{{TITLE}}").length, 2);
  assert.match(
    html,
    /<script type="application\/json" id="card">null<\/script>/,
  );
  // A local page returns at its capability check, so its listeners come first.
  const code = scripts[0];
  for (const ev of ["click", "change", "input"])
    assert.ok(
      code.indexOf(`document.addEventListener('${ev}'`) <
        code.indexOf("return localMode()"),
      ev,
    );
  // A frame runs no script but stays readable for the live palette.
  assert.match(html, /<iframe sandbox="allow-same-origin" /);
});

test("the page reads only documented card fields, and its answers match the shape and apply back to the same answers", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c]);
  const v = P.view(S);
  assert.equal(v.split("<iframe").length - 1, 5);
  assert.ok(submitOff(v));
  P.ACT.set(S, { field: "choice", value: "save" });
  P.ACT.set(S, { field: "name", value: "acme-brand" });
  P.ACT.set(S, { field: "default", value: true });
  P.ACT.set(S, { field: "note", value: "keep\nthe red" });
  assert.ok(!submitOff(P.view(S)));
  const a = clone(P.answersDoc(S, "2026-10-16T10:00:00Z"));
  assert.deepEqual(shapeProblems(a, "answers"), []);
  assert.deepEqual(a, {
    version: 1,
    submittedAt: "2026-10-16T10:00:00Z",
    choice: "save",
    name: "acme-brand",
    colors: {},
    type: {},
    note: "keep\nthe red",
    replace: false,
    default: true,
  });
  for (const f of seen)
    assert.ok(
      shape.has(f.replace(/\[\]$/, "")),
      `the page reads undocumented ${f}`,
    );
  const text = P.answersText(S);
  for (const line of text.split("\n")) {
    const form = line
      .replace(/\d+/g, "<n>")
      .replace(/^Name: .*/, "Name: <name>")
      .replace(/^Note: .*/, "Note: <text>");
    assert.ok(
      doc.includes("`" + form + "`") || doc.includes(line.slice(0, 8)),
      line,
    );
  }
  const r = answer(fx, text);
  assert.equal(r.code, 0, r.out + r.err);
  const back = json(fx.dir, "style-draft", "card", "answers-1.json");
  assert.deepEqual(
    { ...back, submittedAt: a.submittedAt },
    { ...a, note: "keep the red" },
  );
});

test("a colour edit recolours the frames, fails contrast live and blocks Submit until fixed", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c]);
  P.ACT.set(S, { field: "choice", value: "once" });
  P.ACT.color(S, { token: "muted", hex: "#c8c8c0" });
  const v = P.view(S);
  assert.ok(submitOff(v));
  assert.ok(
    P.failing(S).some((x) => /^muted on bg [\d.]+:1, floor 4\.5:1$/.test(x)),
  );
  assert.match(v, /muted on bg/);
  const frame = P.frameDoc(S, c.frames[0]);
  assert.match(frame, /<style id="edits">:root \{[^}]*--muted: #c8c8c0;/);
  assert.ok(!/<script/i.test(frame), "a frame carries no script");
  P.ACT.color(S, { token: "muted", hex: "#3a3f63" });
  assert.deepEqual(clone(P.failing(S)), []);
  assert.ok(!submitOff(P.view(S)));
  assert.deepEqual(clone(P.answersDoc(S).colors), { muted: "#3a3f63" });
  assert.match(P.answersText(S), /^Colour muted: #3a3f63$/m);
});

test("frames load their fonts from the card's URLs, and a URL that is not https, /_blob/ or relative is dropped", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  c.fonts = c.fonts.map((f, i) => ({
    ...f,
    url: i ? `https://cdn.example/${f.file}` : "javascript:alert(1)",
  }));
  const frame = P.frameDoc(session([c]), c.frames[0]);
  assert.ok(!frame.includes("javascript:"));
  assert.match(frame, /url\("https:\/\/cdn\.example\/[^"]+"\)/);
  assert.match(frame, /url\(""\)/);
  for (const bad of ['a")', "/abs", "data:x", "a b", "x\\y"])
    assert.equal(P.mediaUrl(bad), "", bad);
  for (const ok of ["frames/fonts/a.woff2", "https://x/a", "/_blob/abc"])
    assert.equal(P.mediaUrl(ok), ok);
});

test("a name the store holds needs Replace before Save; findings block Save and Use once until an edit or a revision", () => {
  const fx = fixture();
  fs.mkdirSync(fx.project, { recursive: true });
  fs.writeFileSync(path.join(fx.project, "acme.json"), "{}");
  built(fx);
  const c = latestCard(fx);
  assert.deepEqual(c.taken, ["acme"]);
  const S = session([c]);
  P.ACT.set(S, { field: "choice", value: "save" });
  assert.ok(submitOff(P.view(S)));
  assert.match(P.view(S), /Replace the saved acme/);
  P.ACT.set(S, { field: "replace", value: true });
  assert.ok(!submitOff(P.view(S)));
  assert.equal(P.answersDoc(S).replace, true);

  const red = {
    ...clone(c),
    findings: ["layout title: text 12 px, floor 18 px"],
  };
  const R = session([red]);
  assert.match(P.view(R), /class="banner panel" role="alert"/);
  P.ACT.set(R, { field: "choice", value: "once" });
  assert.ok(submitOff(P.view(R)));
  P.ACT.set(R, { field: "choice", value: "revise" });
  assert.ok(!submitOff(P.view(R)));
  P.ACT.set(R, { field: "choice", value: "once" });
  P.ACT.font(R, { role: "title", font: "inter" });
  assert.ok(!submitOff(P.view(R)));
  assert.deepEqual(clone(P.answersDoc(R).type), { title: "inter" });
});

test("an answered version locks the page; a viewer who cannot edit sees no Submit", () => {
  const fx = fixture();
  built(fx);
  const c = latestCard(fx);
  const S = session([c], [{ version: 1 }]);
  assert.match(P.view(S), /<b>Submitted\.<\/b>/);
  assert.match(
    P.view(S),
    /<input type="radio" name="choice" value="save"\s+disabled>/,
  );
  const V = session([c]);
  V.canEdit = false;
  assert.ok(!P.view(V).includes('id="submit"'));
});

test("a draft whose text breaks a layout rule lists the finding by frame; a probe that sees no text refuses", () => {
  const fx = fixture({ label: "Acme tiny" });
  const r = built(fx);
  assert.match(r.out, /^card 1: 5 frame\(s\), 1 finding\(s\)/m);
  assert.match(r.out, /^card layout title: .*12/m);
  assert.deepEqual(latestCard(fx).findings.length, 1);
  const g = fixture();
  const b = card(g, ["build"], { extra: { EXPLAINER_VIDEO_FAKE_BLANK: "1" } });
  assert.equal(b.code, 1);
  assert.match(b.err, /^card: layout probe: no text in frame title$/m);
});

test("a draft under its contrast floor, or naming a font setup does not install, is refused before any gate", () => {
  const pale = fixture({
    colors: {
      ...json(skill, "styles", "itworx.json").colors,
      muted: "#c8c8c0",
    },
  });
  const r = card(pale, ["build"]);
  assert.equal(r.code, 1);
  assert.match(r.err, /fails contrast: .*muted on bg/);
  assert.equal(calls(pale, "check").length, 0);
  const odd = fixture({
    type: {
      ...json(skill, "styles", "itworx.json").type,
      title: { font: "comic-sans", weight: 600 },
    },
  });
  const o = card(odd, ["build"]);
  assert.equal(o.code, 1);
  assert.match(o.err, /names font comic-sans, which no setup row installs/);
});

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

test("a copy of the skill under ~/.claude/skills saves to the user store, and --project forces the project", () => {
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
    /card 1 has 1 layout finding\(s\): revise the draft before using it/,
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
  r = card(fx, [
    "asset",
    ...uploads.map((u, i) => `${u}=/_blob/${String(i).padStart(32, "0")}`),
  ]);
  assert.equal(r.code, 0, r.err);
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
  assert.match(r.out, /^gates: 6 pass, 0 fail$/m);
  assert.equal(json(fx.dir, "style.json").name, "itworx");
  assert.match(read(fx.dir, "composition", "index.html"), /--bg: #ffffff;/);
});
