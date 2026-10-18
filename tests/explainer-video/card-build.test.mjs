// The style card through its process door, part 1: the build, its gates, the
// documented shape and the refusals before any gate.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import {
  built,
  calls,
  card,
  clone,
  fixture,
  html,
  json,
  latestCard,
  read,
  shape,
  shapeProblems,
  skill,
} from "./card-lib.mjs";

test("build refuses a font folder that holds the stamp but lacks one of its files, by name", () => {
  const fx = fixture();
  const dirs = userDirs({ platform: "linux", env: fx.env, home: fx.env.HOME });
  const family = json(skill, "styles", "itworx.json").type.title.font;
  const row = catalogue().find((r) => r.kind === "font" && r.family === family);
  fs.rmSync(path.join(dest(row, dirs), `${row.files[0]}.woff2`));
  const r = card(fx, ["build"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    new RegExp(
      `${row.id} lacks ${row.files[0]}\\.woff2: run /explainer-video setup`,
    ),
  );
});

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

test("the Arabic frame loads the draft's Arabic title and text faces, each stacked once over its Latin face", () => {
  const itworx = json(skill, "styles", "itworx.json").type;
  // A display-class title takes the Kufi companion, which setup installs too.
  for (const arTitle of ["noto-naskh-arabic", "noto-kufi-arabic"]) {
    const fx = fixture({
      type: { ...itworx, arTitle: { font: arTitle, weight: 600 } },
    });
    built(fx);
    const c = latestCard(fx);
    const arabic = c.frames.find((f) => f.id === "arabic").html;
    for (const family of [arTitle, "ibm-plex-sans-arabic"]) {
      const font = c.fonts.find((f) => f.file.startsWith(`${family}-arabic-`));
      assert.ok(font, `${family} not among ${c.fonts.map((f) => f.file)}`);
      assert.ok(
        fs.existsSync(path.join(fx.dir, "style-draft", "card", font.url)),
      );
      assert.match(
        arabic,
        new RegExp(`@font-face \\{ font-family: "${family}"; src: url\\(`),
      );
    }
    assert.match(arabic, new RegExp(`"${arTitle}", "source-serif-4"`));
    assert.match(arabic, /"ibm-plex-sans-arabic", "inter"/);
    assert.doesNotMatch(arabic, /("[a-z0-9-]+"), \1/);
  }
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
