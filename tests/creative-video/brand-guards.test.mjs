// The brand's guards outside the brand stage's own commands: a brand.json or
// a stored or seeded brand held to its shape wherever it is read, the board's
// hold on the frames and the logo before any still, and the page key that
// keeps a site's start page from being captured twice.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, here } from "./voice-lib.mjs";
import { calls, exec } from "./timing-lib.mjs";
import { pageKey } from "../../skills/creative-video/scripts/lib/backend/brand.mjs";
import { BRAND, build, ready, wears, writeDirection } from "./board-lib.mjs";

const script = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "brand",
  "brand.mjs",
);
const stored = (fx) =>
  path.join(
    fx.tmp,
    "home",
    ".local",
    "share",
    "creative-video",
    "brands",
    "acme",
    "brand.json",
  );

test("use refuses a stored brand that is not JSON or has a bad shape, naming the file", () => {
  const fx = fixture();
  const file = stored(fx);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, "{ not json");
  const bad = exec(script, fx, [fx.dir, "use", "acme"]);
  assert.equal(bad.code, 1);
  assert.match(bad.err, /^brand: .*acme\/brand\.json: is not valid JSON/m);
  fs.writeFileSync(file, JSON.stringify({ ...BRAND, name: "acme", faces: 3 }));
  const shape = exec(script, fx, [fx.dir, "use", "acme"]);
  assert.equal(shape.code, 1);
  assert.match(
    shape.err,
    /^brand: .*acme\/brand\.json: faces is not a list with at least one entry$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "brand.json")));
});

test("board build refuses a malformed brand.json by the field", () => {
  const fx = ready({ brand: BRAND });
  fs.writeFileSync(
    path.join(fx.dir, "brand.json"),
    JSON.stringify({ ...BRAND, colours: [{ hex: "red" }] }),
  );
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err.trim(),
    "board: brand.json: colours[0].hex is not a lowercase #rrggbb",
  );
});

test("a face is worn only where its name stands as a whole word: cursor:pointer names no inter", () => {
  const fx = ready({ brand: BRAND });
  writeDirection(
    fx,
    "kitchen",
    wears(BRAND).replace("inter", "") + " cursor:pointer",
  );
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err.trim(),
    "board: directions/kitchen.html does not wear the brand: it names no inter",
  );
});

test("board build refuses a missing logo before it takes any still", () => {
  const fx = ready({ brand: BRAND });
  fs.rmSync(path.join(fx.dir, BRAND.logo.file));
  fs.rmSync(fx.log, { force: true });
  const r = build(fx);
  assert.equal(r.code, 1);
  assert.equal(
    r.err.trim(),
    "board: brand.json: logo brand/logo.svg is missing",
  );
  assert.ok(!calls(fx).some((c) => c.call === "snapshot"));
});

test("a page's key drops the fragment and makes a bare origin its root, so the start page is seen once", () => {
  assert.equal(pageKey("https://acme.com"), "https://acme.com/");
  assert.equal(pageKey("https://acme.com/"), "https://acme.com/");
  assert.equal(pageKey("https://acme.com/a?x=1#top"), "https://acme.com/a?x=1");
});
