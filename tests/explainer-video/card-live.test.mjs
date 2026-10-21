// The style card's live builds: each sample frame loops its scene through its
// exit seam, one more sample plays a seam, and each grammar field carries its
// mark.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {
  built,
  card,
  fixture,
  json,
  latestCard,
  read,
  skill,
} from "./card-lib.mjs";

const IDS = ["title", "diagram", "caption", "code", "arabic", "seam"];
const loops = (c) => Object.fromEntries(c.frames.map((f) => [f.id, f.loop]));
// The build as the page loads it: a script setting window.__build.
const build = (fx, url = "live.js") => {
  const win = {};
  vm.runInNewContext(read(fx.dir, "style-draft", "card", url), { window: win });
  return win.__build;
};

test("the card holds a live build of the five samples and a sixth frame that plays a seam", () => {
  const fx = fixture();
  const r = built(fx);
  assert.match(r.out, /^card 1: 6 frame\(s\), 0 finding\(s\) /m);
  const c = latestCard(fx);
  assert.deepEqual(
    c.frames.map((f) => f.id),
    IDS,
  );
  assert.deepEqual(c.live, { url: "live.js" });
  const { html, fonts } = build(fx);
  // The one composition holds every sample, each scene inline.
  for (const id of IDS.slice(0, 5))
    assert.match(html, new RegExp(`data-composition-id="${id}"`), id);
  assert.ok(fonts.length > 0);
  // Each sample loops its own 2.4 s plus its exit seam (0.2 s by default), the
  // last scene having none; the sixth runs across the seam out of the title.
  assert.deepEqual(loops(c), {
    title: [0, 2.6],
    diagram: [2.4, 5],
    caption: [4.8, 7.4],
    code: [7.2, 9.8],
    arabic: [9.6, 12],
    seam: [1.9, 3.1],
  });
});

test("a draft whose seams are plain cuts plays the sixth frame across a cut", () => {
  const fx = fixture({ grammar: { seams: "cut" } });
  built(fx);
  const c = latestCard(fx);
  assert.deepEqual(loops(c).title, [0, 2.4]);
  assert.deepEqual(loops(c).seam, [1.9, 2.9]);
});

test("a published page needs the live build uploaded like a font, and takes its URL", () => {
  const fx = fixture();
  built(fx);
  const dir = path.join(fx.dir, "style-draft", "card");
  fs.writeFileSync(
    path.join(dir, "page.json"),
    JSON.stringify({ url: "https://x.example/p" }),
  );
  // Fonts uploaded, the live build not: the build names what is missing.
  const fonts = latestCard(fx).fonts.map(
    (f) => `style-draft/card/frames/fonts/${f.file}`,
  );
  const blob = (i) => `/_blob/${String(i).padStart(32, "0")}`;
  let r = card(fx, ["asset", ...fonts.map((f, i) => `${f}=${blob(i + 1)}`)]);
  assert.equal(r.code, 0, r.err);
  r = card(fx, ["build"]);
  assert.equal(r.code, 1);
  assert.match(r.err, /card: upload style-draft\/card\/live\.js /);
  r = card(fx, ["asset", `style-draft/card/live.js=${blob(99)}`]);
  assert.equal(r.code, 0, r.err);
  built(fx);
  assert.equal(latestCard(fx).live.url, blob(99));
  // The local copy opens from file:, where a blob URL resolves to nothing: it
  // keeps its build and its fonts beside it.
  const page = read(dir, "stylecard.html");
  const embedded = JSON.parse(
    page.match(
      /<script type="application\/json" id="card">(.*?)<\/script>/s,
    )[1],
  );
  assert.equal(embedded.live.url, "live.js");
  assert.ok(embedded.fonts.every((f) => f.url.startsWith("frames/fonts/")));
});

test("each grammar field is listed with its mark: measured, judged, or default where the draft leaves it out", () => {
  const fx = fixture({
    grammar: {
      seams: { family: "velocity", blur: 12 },
      camera: "locked",
      texture: { surface: "flat", overlays: ["vignette"] },
    },
    grammarMarks: {
      "seams.family": { mark: "measured", why: "blur 0.5 at the cuts" },
      "seams.blur": { mark: "measured", why: "blur 0.5, 12 px" },
      "camera.family": { mark: "judged", why: "no push-in in the strips" },
      // A mark for a field the grammar does not state does not show.
      ease: { mark: "judged", why: "stale" },
    },
  });
  built(fx);
  const rows = Object.fromEntries(
    latestCard(fx).grammar.map((g) => [g.field, g]),
  );
  assert.deepEqual(Object.keys(rows), [
    "layout",
    "seams.family",
    "seams.duration",
    "seams.blur",
    "camera.family",
    "camera.scale",
    "camera.duration",
    "type.family",
    "type.stagger",
    "ease",
    "texture.surface",
    "texture.overlays",
    "texture.grain",
    "texture.fieldBlur",
    "texture.depthBlur",
    "bans",
  ]);
  assert.deepEqual(rows["seams.blur"], {
    field: "seams.blur",
    value: "12",
    mark: "measured",
    why: "blur 0.5, 12 px",
  });
  assert.equal(rows["camera.family"].value, "locked");
  assert.equal(rows["camera.family"].mark, "judged");
  assert.equal(rows["texture.overlays"].value, "vignette");
  // Stated by the profile with no mark: it came with the profile.
  assert.equal(rows["texture.surface"].mark, "bundled");
  // Left out: the default's value, marked default, whatever a mark says.
  assert.deepEqual(rows.ease, {
    field: "ease",
    value: "velocity",
    mark: "default",
    why: "",
  });
  assert.equal(rows["seams.duration"].value, "0.2");
  assert.equal(rows["seams.duration"].mark, "default");
  assert.equal(rows.layout.mark, "default");
  assert.equal(rows.bans.value, "none");
});

test("the bundled profile with no grammar block marks every field default", () => {
  const fx = fixture({ grammar: undefined });
  built(fx);
  const rows = latestCard(fx).grammar;
  assert.ok(rows.every((g) => g.mark === "default"));
  assert.equal(json(skill, "styles", "claude-code.json").grammar, undefined);
});
