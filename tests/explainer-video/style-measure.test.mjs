// The style stage through its process doors, part 1: measuring screenshots,
// websites, decks and videos into candidates and a draft.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SLIDE, bandsPpm } from "./fake-backend.mjs";
import { candidates, fixture, loads, measuredRun, node } from "./style-lib.mjs";

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

test("a website's declared colours count only where its pages show them, and a draft marks them declared", () => {
  const { run, env } = fixture();
  env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": {
      pages: [SLIDE, SLIDE],
      colors: ["#cc6c55", "#00ff00"],
      fonts: [
        {
          role: "text",
          stack: '"Helvetica Neue", Helvetica, Arial, sans-serif',
        },
        { role: "title", stack: "'Source Serif 4', serif" },
        { role: "title", stack: "'Source Serif 4', serif" },
        { role: "text", stack: "system-ui" },
      ],
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
  // Each family keeps the role it plays and its stack's generic family; a
  // stack naming only a generic declares no family.
  assert.deepEqual(c.fonts, [
    { family: "Helvetica Neue", role: "text", generic: "sans-serif" },
    { family: "Source Serif 4", role: "title", generic: "serif" },
  ]);
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
      fonts: { "Helvetica Neue": { font: "inter", why: "a neutral sans" } },
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

test("a declared colour counts only where its own source's images show it", () => {
  const { run, docs, env } = fixture();
  env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": { pages: [SLIDE], colors: ["#00ff00"], fonts: [] },
  });
  fs.writeFileSync(
    path.join(docs, "green.png"),
    bandsPpm([
      ["#f5f4ed", 80],
      ["#00ff00", 20],
    ]),
  );
  const r = node(
    "measure.mjs",
    [run, "https://acme.test/", path.join(docs, "green.png")],
    env,
  );
  assert.equal(r.status, 0, r.stderr);
  const green = candidates(run).accents.find((a) => a.hex === "#00ff00");
  assert.deepEqual(green.images, ["green-1.png"]);
  assert.equal(green.declared, undefined);
  assert.match(
    r.stdout,
    /^style declared #00ff00: not in the reference images, dropped$/m,
  );
});

test("a deck and a video become at most twelve images each, named by kind in a draft", () => {
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

  fs.writeFileSync(
    path.join(run, "style-draft", "roles.json"),
    JSON.stringify({
      bg: { candidate: "s1", why: "ground" },
      text: { candidate: "s3", why: "text" },
    }),
  );
  const d = node("draft.mjs", [run, "talk"], env);
  assert.equal(d.status, 0, d.stderr);
  const p = JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "talk.json"), "utf8"),
  );
  assert.equal(
    p.source,
    `Extracted from deck ${path.join(docs, "deck.pdf")}, video ${path.join(docs, "talk.mp4")}`,
  );
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
  assert.deepEqual(c.fonts, [
    { family: "Georgia", role: "title" },
    { family: "Inter", role: "text" },
  ]);
  assert.match(
    both.stdout,
    /^style declared #000000: not in the reference images, dropped$/m,
  );
});

test("a source measure cannot take is refused by name, and nothing is written", () => {
  const { run, docs, env } = fixture({ tools: false });
  fs.writeFileSync(path.join(docs, "notes.txt"), "notes");
  fs.writeFileSync(path.join(docs, "shot.png"), bandsPpm(SLIDE));
  for (const [source, line] of [
    [path.join(docs, "gone.png"), /^source .*gone\.png: no such file$/m],
    [
      path.join(docs, "notes.txt"),
      /^source .*notes\.txt: cannot take \.txt: give a web page URL or a file ending \.png, /m,
    ],
    [
      "https://acme.test/",
      /^style: chrome is not installed: run \/explainer-video setup$/m,
    ],
    [
      path.join(docs, "shot.png"),
      /^style: ffmpeg is not installed: run \/explainer-video setup$/m,
    ],
  ]) {
    const r = node("measure.mjs", [run, source], env);
    assert.equal(r.status, 1, source);
    assert.match(r.stderr, line);
    assert.ok(
      !fs.existsSync(path.join(run, "style-draft", "candidates.json")),
      source,
    );
  }
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
  assert.match(
    p.source,
    /^Extracted from screenshot .*one\.png, screenshot .*two\.png$/,
  );
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
