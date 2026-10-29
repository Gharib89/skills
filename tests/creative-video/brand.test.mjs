// The brand stage, node brand.mjs <run> use | measure | check: a brand from the
// store or the seeds, colours measured by area across every page, the refusals
// of a brand a video cannot wear, and the board's approval saving the brand.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, here } from "./voice-lib.mjs";
import {
  calls,
  exec,
  install,
  project,
  read,
  readJson,
} from "./timing-lib.mjs";
import { lockHash } from "../../skills/creative-video/scripts/lib/tools.mjs";
import { answersText, apply, BRAND, build, ok, ready } from "./board-lib.mjs";

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

// A temp machine whose tool cache holds the npm and Chrome rows' stamps.
function machine() {
  const fx = fixture();
  install(fx);
  const chrome = path.join(
    fx.tmp,
    "cache",
    "creative-video",
    "chrome",
    lockHash,
  );
  fs.mkdirSync(chrome, { recursive: true });
  fs.writeFileSync(path.join(chrome, ".stamp"), "");
  return fx;
}
const brand = (fx, args, extra = {}, run = fx.dir) =>
  exec(script, fx, [run, ...args], {
    CREATIVE_VIDEO_FAKE_PRESENT: "ffmpeg",
    ...extra,
  });
const store = (fx, ...p) =>
  path.join(
    fx.tmp,
    "home",
    ".local",
    "share",
    "creative-video",
    "brands",
    ...p,
  );
const brandJson = (fx) => readJson(path.join(fx.dir, "brand.json"));
const assets = (fx, f) => project(fx, "assets", "brand", f);

const GOOD = {
  name: "acme",
  from: "given",
  once: false,
  colours: [{ hex: "#cc6c54", name: "clay", basis: "declared", from: "given" }],
  faces: [{ family: "inter", role: "text", basis: "declared", weights: [400] }],
  logo: null,
  fetched: [],
};
const put = (fx, doc, files = {}) => {
  fs.writeFileSync(path.join(fx.dir, "brand.json"), JSON.stringify(doc));
  for (const [f, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(fx.dir, f)), { recursive: true });
    fs.writeFileSync(path.join(fx.dir, f), body);
  }
};
const refused = (fx, why) => {
  const r = brand(fx, ["check"]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err.trim(), why);
  assert.ok(!fs.existsSync(project(fx, "assets", "brand", "logo.svg")));
};

test("use reads the store before the seed, and a store brand's logo comes along", () => {
  const fx = machine();
  const stored = {
    ...GOOD,
    name: "itworx",
    from: "fetched",
    colours: [{ hex: "#112233", name: "ink", basis: "declared", from: "x" }],
    logo: { file: "logo.svg", source: "https://example.com/press" },
    fetched: [{ url: "https://example.com/press", gave: "logo" }],
  };
  fs.mkdirSync(store(fx, "itworx"), { recursive: true });
  fs.writeFileSync(store(fx, "itworx", "brand.json"), JSON.stringify(stored));
  fs.writeFileSync(store(fx, "itworx", "logo.svg"), "<svg></svg>");

  const r = brand(fx, ["use", "itworx"]);
  assert.equal(r.code, 0, r.out + r.err);
  const b = brandJson(fx);
  assert.equal(b.from, "store");
  assert.equal(b.once, false);
  assert.equal(b.colours[0].hex, "#112233");
  assert.deepEqual(b.logo, {
    file: "brand/logo.svg",
    source: "https://example.com/press",
  });
  assert.equal(read(path.join(fx.dir, "brand", "logo.svg")), "<svg></svg>");
  assert.equal(read(assets(fx, "logo.svg")), "<svg></svg>");
  assert.match(r.out, /^brand: itworx \(store\)$/m);

  fs.rmSync(store(fx, "itworx"), { recursive: true });
  const seeded = brand(fx, ["use", "itworx", "--once"]);
  assert.equal(seeded.code, 0, seeded.err);
  assert.equal(brandJson(fx).from, "seed");
  assert.equal(brandJson(fx).once, true);
  assert.equal(brandJson(fx).colours[0].hex, "#ffffff");
  assert.match(seeded.out, /^brand: itworx \(seed, once\)$/m);
});

test("a seed has no logo, and use installs its faces, fills their licence, version and Arabic companion and copies them into the project", () => {
  for (const name of ["claude-code", "itworx"]) {
    const fx = machine();
    const r = brand(fx, ["use", name]);
    assert.equal(r.code, 0, r.out + r.err);
    const b = brandJson(fx);
    assert.equal(b.logo, null);
    assert.match(r.out, /^brand logo: none$/m);
    assert.doesNotMatch(r.out, /no logo found/);
    const [title, text] = b.faces;
    assert.deepEqual(
      [title.family, title.weights, title.licence, title.version],
      ["source-serif-4", [600], "OFL-1.1", "5.3.0"],
    );
    assert.deepEqual(
      [title.companion, text.companion],
      ["noto-naskh-arabic", "ibm-plex-sans-arabic"],
    );
    assert.match(
      r.out,
      /^brand face title source-serif-4 600: declared · OFL-1\.1 · arabic noto-naskh-arabic · assets\/brand\/source-serif-4-600\.woff2$/m,
    );
    assert.ok(fs.existsSync(assets(fx, "source-serif-4-600.woff2")));
    assert.ok(fs.existsSync(assets(fx, "inter-400.woff2")));
    assert.match(r.out, /^brand colour #[0-9a-f]{6} ground: declared · seed$/m);
  }
});

test("use refuses a name neither the store nor the seeds hold, and a name that is not kebab-case; a wrong shape is usage", () => {
  const fx = machine();
  const r = brand(fx, ["use", "nope"]);
  assert.equal(r.code, 1);
  assert.match(
    r.err.trim(),
    /^brand: no brand nope in the store or the seeds: measure its own pages \(brand\.mjs <run> measure <url>\.\.\.\) and write brand\.json$/,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "brand.json")));
  assert.match(
    brand(fx, ["use", "../x"]).err,
    /^brand: name "\.\.\/x" is not kebab-case/,
  );
  assert.equal(brand(fx, ["use"]).code, 2);
  assert.equal(brand(fx, ["measure"]).code, 2);
  assert.equal(brand(fx, ["measure", "a.png", "--once"]).code, 2);
  assert.equal(brand(fx, ["check", "x"]).code, 2);
  assert.equal(brand(fx, ["colour"]).code, 2);
});

// A page's bands: a cream page and a white one, so a colour only one page
// shows still ranks.
const PAGE_A = [
  ["#ffffff", 60],
  ["#161b8c", 30],
  ["#c03020", 10],
];
const PAGE_B = [
  ["#f5f4ed", 50],
  ["#ffffff", 30],
  ["#4850e0", 20],
];

test("measure ranks colours by area across every page, each page weighing the same, and confirms or drops the declared ones", () => {
  const fx = machine();
  const site = {
    pages: [PAGE_A, PAGE_B],
    colors: ["#161b8d", "#00ff00"],
    fonts: [
      { role: "title", stack: "'Source Serif 4', serif" },
      { role: "text", stack: "Inter, sans-serif" },
      { role: "text", stack: "system-ui" },
    ],
  };
  const r = brand(fx, ["measure", "https://acme.test/"], {
    CREATIVE_VIDEO_FAKE_SITE: JSON.stringify({ "https://acme.test/": site }),
  });
  assert.equal(r.code, 0, r.out + r.err);
  const c = readJson(path.join(fx.dir, "brand", "candidates.json"));
  assert.deepEqual(
    c.surfaces.map((s) => [s.hex, s.share]),
    [
      ["#ffffff", 0.45],
      ["#f5f4ed", 0.25],
      ["#161b8d", 0.15],
      ["#4850e0", 0.1],
      ["#c03020", 0.05],
    ],
  );
  assert.deepEqual(c.surfaces[0].images, [
    "acme-test-1.png",
    "acme-test-2.png",
  ]);
  assert.deepEqual(
    c.accents.map((a) => a.hex),
    ["#161b8d", "#4850e0", "#c03020"],
  );
  assert.equal(c.accents[0].declared, true);
  assert.ok(![...c.surfaces, ...c.accents].some((x) => x.hex === "#00ff00"));
  assert.deepEqual(c.fonts, [
    { family: "Source Serif 4", role: "title", generic: "serif" },
    { family: "Inter", role: "text", generic: "sans-serif" },
  ]);
  assert.match(
    r.out,
    /^brand ref acme-test-1\.png: page · https:\/\/acme\.test\/$/m,
  );
  assert.match(
    r.out,
    /^brand candidate s1: #ffffff · 45% · acme-test-1\.png, acme-test-2\.png$/m,
  );
  assert.match(
    r.out,
    /^brand declared #00ff00: not in the reference images, dropped$/m,
  );
  assert.match(r.out, /^brand font title: Source Serif 4$/m);
  assert.match(
    r.out,
    /^brand: measured 2 reference image\(s\) -> .*brand\/candidates\.json$/m,
  );
  assert.ok(
    fs.existsSync(path.join(fx.dir, "brand", "refs", "acme-test-2.png")),
  );
  assert.match(
    read(path.join(fx.dir, "..", ".gitignore")),
    /^\*\/brand\/refs\/$/m,
  );
});

test("measure refuses a missing tool row, a missing file and a type it cannot take, and writes no candidates", () => {
  const fx = fixture();
  const shot = path.join(fx.tmp, "x.png");
  fs.writeFileSync(shot, "x");
  const bare = brand(fx, ["measure", shot, "x.pdf"], {
    CREATIVE_VIDEO_FAKE_PRESENT: "",
  });
  assert.equal(bare.code, 1);
  assert.match(bare.err, /^brand: source x\.pdf: no such file$/m);
  const rows = brand(fx, ["measure", shot], {
    CREATIVE_VIDEO_FAKE_PRESENT: "",
  });
  assert.equal(
    rows.err.trim(),
    "brand: ffmpeg is not installed: run /creative-video setup",
  );
  const odd = path.join(fx.tmp, "x.txt");
  fs.writeFileSync(odd, "x");
  const r = brand(fx, ["measure", odd]);
  assert.equal(r.code, 1);
  assert.match(r.err, /^brand: source .*x\.txt: cannot take \.txt/);
  assert.ok(!fs.existsSync(path.join(fx.dir, "brand", "candidates.json")));
});

test("check refuses a face Fontsource lacks or licenses badly, and a replaced face with no reason", () => {
  const fx = machine();
  const face = (f) => ({ ...GOOD, faces: [f] });
  put(fx, face({ family: "georgia", role: "title", basis: "declared" }));
  refused(
    fx,
    /^brand: face georgia: Fontsource has no such family: name an admitted replacement \(basis replaced, with was and why\)$/,
  );
  put(fx, face({ family: "ubuntu", role: "text", basis: "declared" }));
  refused(
    fx,
    /^brand: face ubuntu: licence UFL-1\.0, only OFL-1\.1 or Apache-2\.0: name an admitted replacement/,
  );
  put(
    fx,
    face({
      family: "inter",
      role: "text",
      basis: "replaced",
      was: "Helvetica",
    }),
  );
  refused(fx, /^brand: brand\.json: faces\[0\]\.why is missing/);
  put(
    fx,
    face({ family: "inter", role: "text", basis: "replaced", why: "none" }),
  );
  refused(fx, /^brand: brand\.json: faces\[0\]\.was is missing/);
  assert.ok(!fs.existsSync(project(fx, "assets", "brand")));
});

test("check refuses a malformed brand.json by the field", () => {
  const fx = machine();
  const cases = [
    [
      { ...GOOD, name: "Acme Corp" },
      /brand\.json: name "Acme Corp" is not kebab-case/,
    ],
    [{ ...GOOD, from: "web" }, /brand\.json: from is not/],
    [{ ...GOOD, colours: [] }, /brand\.json: colours is not a list/],
    [{ ...GOOD, faces: [] }, /brand\.json: faces is not a list/],
    [
      { ...GOOD, colours: [{ ...GOOD.colours[0], hex: "red" }] },
      /brand\.json: colours\[0\]\.hex/,
    ],
    [
      { ...GOOD, colours: [{ ...GOOD.colours[0], basis: "guessed" }] },
      /brand\.json: colours\[0\]\.basis/,
    ],
    [{ ...GOOD, logo: { file: "x.svg" } }, /brand\.json: logo is not null or/],
    [{ ...GOOD, from: "fetched" }, /brand\.json: fetched is empty/],
  ];
  for (const [doc, why] of cases) {
    put(fx, doc);
    refused(fx, why);
  }
  assert.equal(brand(fx, ["check"], {}, path.join(fx.tmp, "empty")).code, 1);
});

test("check refuses a measured colour of a given or fetched brand that brand/candidates.json lacks, and takes one it has", () => {
  const fx = machine();
  const measured = {
    ...GOOD,
    colours: [{ hex: "#123456", name: "ink", basis: "measured", from: "x" }],
  };
  put(fx, measured);
  refused(
    fx,
    /^brand: colour #123456 is marked measured but brand\/candidates\.json has no such candidate$/,
  );
  fs.mkdirSync(path.join(fx.dir, "brand"), { recursive: true });
  const candidates = path.join(fx.dir, "brand", "candidates.json");
  fs.writeFileSync(
    candidates,
    JSON.stringify({ surfaces: [{ hex: "#654321" }], accents: [] }),
  );
  refused(fx, /colour #123456 is marked measured/);
  fs.writeFileSync(
    candidates,
    JSON.stringify({ surfaces: [], accents: [{ hex: "#123456" }] }),
  );
  const r = brand(fx, ["check"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^brand colour #123456 ink: measured · x$/m);
  // A store brand's measured colours were checked when it was written.
  put(fx, { ...measured, from: "store" });
  fs.rmSync(candidates);
  assert.equal(brand(fx, ["check"]).code, 0);
});

// A PNG of one pixel, its colour type and the extra chunks named.
const png = (colourType, ...chunks) => {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    return Buffer.concat([len, Buffer.from(type), data, Buffer.alloc(4)]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = colourType;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    ...chunks.map((t) => chunk(t, Buffer.alloc(1))),
    chunk("IEND", Buffer.alloc(0)),
  ]);
};

test("check refuses a logo that is a favicon or social card, an icon, a PNG with no transparency, an SVG holding a raster image, or a file that is missing", () => {
  const fx = machine();
  const logo = (file, source = "https://acme.test/press") => ({
    ...GOOD,
    logo: { file, source },
  });
  put(fx, logo("brand/missing.svg"));
  refused(fx, /^brand: logo brand\/missing\.svg: is missing$/);
  put(fx, logo("brand/favicon.svg"), { "brand/favicon.svg": "<svg></svg>" });
  refused(
    fx,
    /^brand: logo brand\/favicon\.svg: a favicon or social card is never the logo$/,
  );
  put(fx, logo("brand/mark.svg", "https://acme.test/og-image.png"), {
    "brand/mark.svg": "<svg></svg>",
  });
  refused(fx, /a favicon or social card is never the logo/);
  put(fx, logo("brand/mark.ico"), { "brand/mark.ico": "ico" });
  refused(fx, /a favicon or social card is never the logo/);
  put(fx, logo("brand/mark.jpg"), { "brand/mark.jpg": "jpg" });
  refused(fx, /^brand: logo brand\/mark\.jpg: is not an \.svg or a \.png$/);
  put(fx, logo("brand/mark.png"), { "brand/mark.png": png(2) });
  refused(fx, /^brand: logo brand\/mark\.png: has no transparency/);
  put(fx, logo("brand/mark.svg"), {
    "brand/mark.svg": '<svg><image href="data:image/png;base64,AAAA"/></svg>',
  });
  refused(
    fx,
    /^brand: logo brand\/mark\.svg: embeds a raster image: a trace or a wrapped bitmap, not the mark$/,
  );
  put(fx, logo("brand/mark.svg"), { "brand/mark.svg": "<html></html>" });
  refused(fx, /holds no <svg>/);
});

test("check passes a brand and copies its fonts and logo into project/assets/brand, never shrinking the font store", () => {
  const fx = machine();
  const folder = path.join(
    fx.tmp,
    "home",
    ".local",
    "share",
    "creative-video",
    "fonts",
    "inter@5.3.0",
  );
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, "latin-700-normal.woff2"), "held");
  for (const [file, body, ext] of [
    ["brand/mark.png", png(6), "png"],
    ["brand/mark2.png", png(3, "tRNS"), "png"],
    ["brand/mark.svg", "<svg><path d=''/></svg>", "svg"],
  ]) {
    put(fx, { ...GOOD, logo: { file, source: "given" } }, { [file]: body });
    const r = brand(fx, ["check"]);
    assert.equal(r.code, 0, r.out + r.err);
    assert.match(
      r.out,
      new RegExp(`^brand logo: assets/brand/logo\\.${ext} · given$`, "m"),
    );
    assert.deepEqual(
      read(assets(fx, `logo.${ext}`)),
      fs.readFileSync(path.join(fx.dir, file), "utf8"),
    );
  }
  assert.ok(fs.existsSync(assets(fx, "inter-400.woff2")));
  assert.ok(
    calls(fx).some(
      (c) => c.call === "download" && c.url.includes("latin-700-normal"),
    ),
  );
  const b = brandJson(fx);
  assert.deepEqual(
    [
      b.faces[0].licence,
      b.faces[0].version,
      b.faces[0].weights,
      b.faces[0].companion,
    ],
    ["OFL-1.1", "5.3.0", [400], "ibm-plex-sans-arabic"],
  );
  // The weights asked snap to the ones the family has, no repeat.
  put(fx, { ...GOOD, faces: [{ ...GOOD.faces[0], weights: [300, 500, 700] }] });
  const snapped = brand(fx, ["check"]);
  assert.equal(snapped.code, 0, snapped.err);
  assert.deepEqual(brandJson(fx).faces[0].weights, [400, 600]);
  assert.match(
    snapped.out,
    /^brand face text inter 400,600: declared · OFL-1\.1 · arabic ibm-plex-sans-arabic · assets\/brand\/inter-400\.woff2, assets\/brand\/inter-600\.woff2$/m,
  );
  // A brand from the web with no logo asks for one.
  assert.match(
    snapped.out,
    /^brand logo: none\nbrand: no logo found: ask the person for one \(unattended: say so in DELIVERY\.md\)$/m,
  );
});

test("a plain approval saves the brand to the store, and a later use reads it back without asking; --once saves nothing", () => {
  const fx = ready({ brand: BRAND });
  ok(build(fx));
  const r = apply(fx, answersText(1, "Approved: the look"));
  ok(r);
  assert.equal(
    r.out,
    "board: brand itworx saved to the store\nboard: approved; next: run the gates\n",
  );
  const kept = readJson(store(fx, "itworx", "brand.json"));
  assert.equal(kept.logo.file, "logo.svg");
  assert.equal(read(store(fx, "itworx", "logo.svg")), "<svg></svg>");
  assert.ok(!fs.existsSync(`${store(fx, "itworx")}.part`));

  const next = path.join(fx.tmp, "creative-videos", "next");
  fs.rmSync(fx.log, { force: true });
  const again = brand(fx, ["use", "itworx"], {}, next);
  assert.equal(again.code, 0, again.out + again.err);
  assert.match(again.out, /^brand: itworx \(store\)$/m);
  assert.equal(readJson(path.join(next, "brand.json")).from, "store");
  assert.ok(
    fs.existsSync(path.join(next, "project", "assets", "brand", "logo.svg")),
  );
  assert.ok(
    !calls(fx).some((c) => ["capturePages", "renderPage"].includes(c.call)),
    "no page was read",
  );

  const once = ready({ brand: { ...BRAND, once: true } });
  ok(build(once));
  const o = apply(once, answersText(1, "Approved: the look"));
  ok(o);
  assert.equal(
    o.out,
    "board: brand itworx used once, not saved\nboard: approved; next: run the gates\n",
  );
  assert.ok(!fs.existsSync(store(once, "itworx")));
});

test("a board with no brand.json approves with no brand line", () => {
  const fx = ready();
  ok(build(fx));
  const r = apply(fx, answersText(1, "Approved: the look"));
  assert.equal(r.out, "board: approved; next: run the gates\n");
});
