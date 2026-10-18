// The source stage through its process doors, part 2: HTML, DOCX, PPTX and web
// sources, the excerpt budget and the merge.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  draft,
  fixture,
  locates,
  pack,
  snapshot,
  sourcesOf,
  write,
} from "./source-lib.mjs";

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

// #782: a page whose load timed out reached the snapshot as its heading alone,
// exit 0, and took a share of the excerpt budget. Markup with no text in it
// (an empty heading, an image) reads the same.
test("a page that renders no text is refused, and no sources.json is written", () => {
  const fx = fixture();
  const blank = "https://dora.dev/guides/dora-metrics/";
  const bare = "https://dora.dev/guides/how-to-transform/";
  const chart = "https://dora.dev/guides/chart/";
  const pages = JSON.stringify({
    [blank]: { title: "", html: "" },
    [bare]: { title: "", html: "<h2></h2>" },
    [chart]: { title: "", html: '<img src="chart_(empty).png">' },
  });
  const s = snapshot(fx, [blank, bare, chart], {
    EXPLAINER_VIDEO_FAKE_PAGES: pages,
  });
  assert.equal(s.code, 1, s.out + s.err);
  for (const page of ["dora-metrics", "how-to-transform", "chart"])
    assert.match(
      s.err,
      new RegExp(
        `^source https://dora\\.dev/guides/${page}/: the page rendered no text, as it timed out or renders client side: snapshot it again, or give it as a saved \\.html or \\.md file$`,
        "m",
      ),
    );
  assert.equal(
    fs.existsSync(path.join(fx.dir, "snapshots", "sources.json")),
    false,
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
  // A --topic with no topic after it is a usage error, not a source run.
  for (const args of [
    [...urls.slice(0, 3), "--topic"],
    ["--topic", ...urls.slice(0, 3)],
  ])
    assert.equal(snapshot(fx, args, env).code, 2, args.join(" "));
  // A run from sources records no topic.
  assert.equal(snapshot(fx, [urls[0]], env).code, 0);
  assert.equal(sourcesOf(fx).topic, undefined);
});
