// The sound fetch: each kit sound from Openverse, its store, or the Kenney
// packs, else dropped, with its licence written back into sound.json.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, here } from "./voice-lib.mjs";
import { calls, exec, project, readJson } from "./timing-lib.mjs";

const sounds = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "sound",
  "sounds.mjs",
);
const store = (fx, ...p) =>
  path.join(
    fx.tmp,
    "home",
    ".local",
    "share",
    "creative-video",
    "sounds",
    ...p,
  );
const KIT = {
  bed: { world: "a kitchen", query: "kitchen ambience", level: -28 },
  palette: [{ event: "ticket", query: "paper tear" }],
};
// A result titled with its query's words.
const hit = (id, title, filetype = "mp3") => ({
  id,
  title,
  url: `https://cdn.example/${id}.${filetype}`,
  filetype,
  duration: 60000,
  license: "cc0",
  license_version: "1.0",
  creator: "someone",
  foreign_landing_url: `https://freesound.org/s/${id}`,
  attribution: `"sound ${id}" by someone is marked with CC0 1.0.`,
});
const OPENVERSE = {
  "kitchen ambience": [[hit("bed-1", "Kitchen Ambience")]],
  "paper tear": [
    [
      { ...hit("vid", "Paper tear", "mp4") },
      hit("tear-1", "Paper Tear 2", "ogg"),
    ],
  ],
};

function kit(fx, k = KIT) {
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "sound.json"), JSON.stringify(k));
}
const kitOf = (fx) => readJson(project(fx, "kit", "sound.json"));
const fetch = (fx, openverse = OPENVERSE) =>
  exec(sounds, fx, [fx.dir], {
    CREATIVE_VIDEO_FAKE_OPENVERSE: JSON.stringify(openverse),
  });
const asked = (fx, call) => calls(fx).filter((c) => c.call === call);

test("each sound comes from Openverse's first usable CC0 result into the store and the project, its licence written into sound.json", () => {
  const fx = fixture();
  kit(fx);
  const r = fetch(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(r.out.trim().split("\n"), [
    "sound bed: openverse bed-1",
    "sound ticket: openverse tear-1",
  ]);
  assert.deepEqual(
    asked(fx, "openverse").map((c) => [c.query, c.medium]),
    [
      ["kitchen ambience", true],
      ["paper tear", false],
    ],
  );
  const k = kitOf(fx);
  assert.deepEqual(k.bed, {
    ...KIT.bed,
    source: "openverse:bed-1",
    file: "assets/sounds/bed-1.mp3",
    licence: "CC0-1.0",
    creator: "someone",
    url: "https://freesound.org/s/bed-1",
    attribution: '"sound bed-1" by someone is marked with CC0 1.0.',
  });
  assert.equal(k.palette[0].file, "assets/sounds/tear-1.ogg");
  for (const f of ["openverse/bed-1.mp3", "openverse/tear-1.ogg"])
    assert.ok(fs.existsSync(store(fx, f)), f);
  for (const f of ["bed-1.mp3", "tear-1.ogg"])
    assert.ok(fs.existsSync(project(fx, "assets", "sounds", f)), f);
});

test("a re-run, or another run folder asking the same queries, fetches nothing", () => {
  const fx = fixture();
  kit(fx);
  assert.equal(fetch(fx).code, 0);
  fs.rmSync(fx.log);
  const again = fetch(fx, {});
  assert.equal(again.code, 0, again.out + again.err);
  assert.deepEqual(again.out.trim().split("\n"), [
    "sound bed: cached",
    "sound ticket: cached",
  ]);
  assert.deepEqual(calls(fx), []);
  // A second run folder on the same machine.
  const other = path.join(fx.tmp, "creative-videos", "other");
  fs.mkdirSync(path.join(other, "project", "kit"), { recursive: true });
  fs.writeFileSync(
    path.join(other, "project", "kit", "sound.json"),
    JSON.stringify(KIT),
  );
  const fresh = exec(sounds, fx, [other], {
    CREATIVE_VIDEO_FAKE_OPENVERSE: "{}",
  });
  assert.equal(fresh.code, 0, fresh.out + fresh.err);
  assert.match(fresh.out, /^sound ticket: cached$/m);
  assert.deepEqual(calls(fx), []);
  assert.ok(
    fs.existsSync(
      path.join(other, "project", "assets", "sounds", "tear-1.ogg"),
    ),
  );
  assert.equal(
    readJson(path.join(other, "project", "kit", "sound.json")).bed.licence,
    "CC0-1.0",
  );
});

test("a search that times out is tried once more", () => {
  const fx = fixture();
  kit(fx, { palette: KIT.palette });
  const r = fetch(fx, {
    "paper tear": ["timeout", [hit("tear-1", "paper tears")]],
  });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound ticket: openverse tear-1");
  assert.equal(asked(fx, "openverse").length, 2);
});

// Openverse's first two results for two queries of the pstack run (recorded
// 2026-10-30, trimmed to the fields the pick reads), and the page flip it took
// for "pencil scratch", which Openverse answered 504 when recorded.
const RECORDED = {
  "rubber stamp": [
    {
      id: "622292b5-764e-4fc5-a99c-6781b20e7007",
      title: "LL-Q1860 (eng)-Flame, not lame-rubber stamp",
      url: "https://upload.wikimedia.org/wikipedia/commons/9/94/LL-Q1860_%28eng%29-Flame%2C_not_lame-rubber_stamp.wav",
      filetype: "wav",
      license: "cc0",
      category: "pronunciation",
      tags: [],
    },
    {
      id: "c154424d-43c2-455c-a232-e5b2c2cfa45f",
      title: "es-stamp.wav",
      url: "https://cdn.freesound.org/previews/448/448474_9090982-hq.mp3",
      filetype: "mp3",
      license: "cc0",
      category: null,
      tags: ["datestamp", "paper", "rubber", "signature", "stamp"].map(
        (name) => ({ name }),
      ),
    },
  ],
  "radio squelch": [
    {
      id: "6cc51e37-8a0e-4d9d-8462-5002f249d13f",
      title: "Zombie Eat",
      url: "https://cdn.freesound.org/previews/264/264280_1733081-hq.mp3",
      filetype: "mp3",
      license: "cc0",
      category: null,
      tags: ["brains", "flesh", "gore", "squelch", "zombie"].map((name) => ({
        name,
      })),
    },
    {
      id: "9b484e81-a91b-4255-9b2a-041e17bb8229",
      title: "Radio Buzz / Squelch 1",
      url: "https://cdn.freesound.org/previews/522/522164_11537497-hq.mp3",
      filetype: "mp3",
      license: "cc0",
      category: null,
      tags: ["buzz", "noise", "radio", "squlech"].map((name) => ({ name })),
    },
  ],
  "pencil scratch": [
    {
      id: "page-flip",
      title: "Page Flip",
      url: "https://cdn.example/page-flip.mp3",
      filetype: "mp3",
      license: "cc0",
      category: "sound_effect",
      tags: [{ name: "book" }, { name: "paper" }],
    },
  ],
};

test("a result that is speech, or whose title and tags miss a query word, is passed over for the next; with none left the sound falls back to Kenney, then is dropped", () => {
  const fx = fixture();
  kit(fx, {
    palette: ["rubber stamp", "radio squelch", "pencil scratch"].map(
      (query) => ({ event: query.split(" ")[1], query }),
    ),
  });
  const r = fetch(
    fx,
    Object.fromEntries(Object.entries(RECORDED).map(([q, rs]) => [q, [rs]])),
  );
  assert.equal(r.code, 0, r.out + r.err);
  const why =
    "openverse found no usable CC0 result; the Kenney packs are not installed (run /creative-video setup)";
  assert.deepEqual(r.out.trim().split("\n"), [
    "sound stamp: openverse c154424d-43c2-455c-a232-e5b2c2cfa45f",
    "sound squelch: openverse 9b484e81-a91b-4255-9b2a-041e17bb8229",
    `sound scratch: dropped: ${why}`,
    `warn dropped sound: scratch: ${why}`,
  ]);
});

test("each mark of speech alone passes a result over: a speech category, a Lingua Libre title, a title naming a pronunciation", () => {
  const stamp = hit("stamp-1", "Rubber stamp");
  for (const [query, result] of [
    ["rubber stamp", { ...stamp, category: "pronunciation" }],
    ["rubber stamp", { ...stamp, category: "podcast" }],
    ["rubber stamp", { ...stamp, category: "audiobook" }],
    ["rubber stamp", { ...stamp, title: "LL-Q1860 (eng)-Flame-rubber stamp" }],
    ["rubber stamp", { ...stamp, title: "Rubber stamp pronunciation" }],
  ]) {
    const fx = fixture();
    kit(fx, { palette: [{ event: "stamp", query }] });
    const r = fetch(fx, { [query]: [[result]] });
    assert.equal(r.code, 0, r.out + r.err);
    assert.match(r.out, /^sound stamp: dropped: /m, JSON.stringify(result));
  }
  // The same result, unmarked, is taken.
  const fx = fixture();
  kit(fx, { palette: [{ event: "stamp", query: "rubber stamp" }] });
  const r = fetch(fx, { "rubber stamp": [[stamp]] });
  assert.equal(r.out.trim(), "sound stamp: openverse stamp-1");
});

// The Kenney packs installed in the store, each holding the named files.
function packs(fx, files) {
  for (const [pack, names] of Object.entries(files)) {
    fs.mkdirSync(store(fx, "kenney", pack), { recursive: true });
    for (const f of [...names, "License.txt"])
      fs.writeFileSync(store(fx, "kenney", pack, f), f);
  }
  fs.writeFileSync(store(fx, "kenney", ".stamp"), "");
}

test("two timeouts fall back to the Kenney pack whose index words match the query", () => {
  const fx = fixture();
  kit(fx, { palette: [{ event: "ticket", query: "page turn" }] });
  packs(fx, { "rpg-audio": ["bookClose.ogg", "bookFlip1.ogg"] });
  const r = fetch(fx, { "page turn": ["timeout"] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound ticket: kenney rpg-audio/bookFlip1.ogg");
  assert.equal(asked(fx, "openverse").length, 2);
  const [entry] = kitOf(fx).palette;
  assert.deepEqual(entry, {
    event: "ticket",
    query: "page turn",
    source: "kenney:rpg-audio/bookFlip1.ogg",
    file: "assets/sounds/rpg-audio-bookFlip1.ogg",
    licence: "CC0-1.0",
    creator: "Kenney",
    url: "https://kenney.nl/assets/rpg-audio",
    attribution: '"bookFlip1.ogg" by Kenney (kenney.nl), CC0 1.0',
  });
  assert.ok(
    fs.existsSync(project(fx, "assets", "sounds", "rpg-audio-bookFlip1.ogg")),
  );
});

// Real file names from the seven packs setup pins.
const PACKS = {
  "interface-sounds": [
    "bong_001.ogg",
    "click_001.ogg",
    "glass_001.ogg",
    "glass_002.ogg",
  ],
  "rpg-audio": ["doorClose_1.ogg", "metalClick.ogg", "metalPot1.ogg"],
  "sci-fi-sounds": [
    "doorClose_000.ogg",
    "spaceEngineLarge_000.ogg",
    "spaceEngine_000.ogg",
  ],
  "ui-audio": ["click1.wav", "mouseclick1.wav"],
};

test("with Openverse down, a sound a pack holds is found by what it is, and one no pack holds is dropped with why", () => {
  const fx = fixture();
  const queries = [
    "service bell",
    "spoon clink",
    "door slam",
    "mouse click",
    "frying pan sizzle",
    "receipt printer",
  ];
  kit(fx, {
    bed: { world: "a diner", query: "restaurant kitchen ambience", level: -28 },
    palette: queries.map((query, i) => ({ event: `e${i}`, query })),
  });
  packs(fx, PACKS);
  const down = Object.fromEntries(
    [...queries, "restaurant kitchen ambience"].map((q) => [q, ["timeout"]]),
  );
  const r = fetch(fx, down);
  assert.equal(r.code, 0, r.out + r.err);
  const why = (q, kind = "sound") =>
    `openverse failed twice (timed out after 30 s); no Kenney ${kind} matches "${q}"`;
  assert.deepEqual(r.out.trim().split("\n"), [
    `sound bed: dropped: ${why("restaurant kitchen ambience", "loop")}`,
    "sound e0: kenney interface-sounds/bong_001.ogg",
    "sound e1: kenney interface-sounds/glass_001.ogg",
    "sound e2: kenney rpg-audio/doorClose_1.ogg",
    "sound e3: kenney interface-sounds/click_001.ogg",
    `sound e4: dropped: ${why("frying pan sizzle")}`,
    `sound e5: dropped: ${why("receipt printer")}`,
    `warn dropped sound: bed: ${why("restaurant kitchen ambience", "loop")}`,
    `warn dropped sound: e4: ${why("frying pan sizzle")}`,
    `warn dropped sound: e5: ${why("receipt printer")}`,
  ]);
  for (const s of kitOf(fx).palette) {
    assert.equal(s.licence, "CC0-1.0");
    assert.equal(s.creator, "Kenney");
  }
});

test("a bed comes only from a stem the index marks loopable", () => {
  const fx = fixture();
  kit(fx, { bed: { world: "a hallway", query: "door slam", level: -28 } });
  packs(fx, PACKS);
  const r = fetch(fx, { "door slam": ["timeout"] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^sound bed: dropped: .*; no Kenney loop matches "door slam"$/m,
  );
  assert.equal(kitOf(fx).bed, undefined);
  kit(fx, { bed: { world: "a spaceship", query: "space engine", level: -28 } });
  const engine = fetch(fx, { "space engine": ["timeout"] });
  assert.equal(engine.code, 0, engine.out + engine.err);
  assert.equal(
    engine.out.trim(),
    "sound bed: kenney sci-fi-sounds/spaceEngineLarge_000.ogg",
  );
});

test("a failed download is dropped like a failed search, and falls back to Kenney once installed", () => {
  const fx = fixture();
  kit(fx, { palette: [{ event: "ticket", query: "page turn" }] });
  const dead = {
    ...hit("page-1", "Page turn"),
    url: "https://cdn.example/dead/page-1.mp3",
  };
  const r = fetch(fx, { "page turn": [[dead]] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(
    kitOf(fx).dropped[0].why,
    "openverse download failed (https://cdn.example/dead/page-1.mp3: HTTP 404); the Kenney packs are not installed (run /creative-video setup)",
  );
  packs(fx, { "rpg-audio": ["bookFlip1.ogg"] });
  kit(fx, { palette: [{ event: "ticket", query: "page turn" }] });
  const again = fetch(fx, { "page turn": [[dead]] });
  assert.equal(again.code, 0, again.out + again.err);
  assert.equal(
    again.out.trim(),
    "sound ticket: kenney rpg-audio/bookFlip1.ogg",
  );
});

test("a sound found nowhere is dropped from the kit with why, and warned", () => {
  const fx = fixture();
  kit(fx);
  const r = fetch(fx, {
    "kitchen ambience": [[hit("bed-1", "Kitchen Ambience")]],
  });
  assert.equal(r.code, 0, r.out + r.err);
  const why =
    "openverse found no usable CC0 result; the Kenney packs are not installed (run /creative-video setup)";
  assert.deepEqual(r.out.trim().split("\n"), [
    "sound bed: openverse bed-1",
    `sound ticket: dropped: ${why}`,
    `warn dropped sound: ticket: ${why}`,
  ]);
  const k = kitOf(fx);
  assert.deepEqual(k.palette, []);
  assert.deepEqual(k.dropped, [{ event: "ticket", query: "paper tear", why }]);
});

test("a sound whose query was edited is searched again, not kept on its old file", () => {
  const fx = fixture();
  kit(fx);
  assert.equal(fetch(fx).code, 0);
  const k = kitOf(fx);
  k.palette[0].query = "glass break";
  kit(fx, k);
  const r = fetch(fx, {
    ...OPENVERSE,
    "glass break": [[hit("glass-1", "Glass Break")]],
  });
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(r.out.trim().split("\n"), [
    "sound bed: cached",
    "sound ticket: openverse glass-1",
  ]);
  const [entry] = kitOf(fx).palette;
  assert.equal(entry.query, "glass break");
  assert.equal(entry.source, "openverse:glass-1");
  assert.equal(entry.file, "assets/sounds/glass-1.mp3");
});

test("a dropped sound put back with its query replaces its earlier drop, and leaves the list once found", () => {
  const fx = fixture();
  const door = { event: "door", query: "door creak", why: "found nowhere" };
  const events = () => kitOf(fx).dropped?.map((d) => [d.event, d.query]);
  kit(fx, { palette: KIT.palette, dropped: [door] });
  assert.equal(fetch(fx, {}).code, 0);
  assert.deepEqual(events(), [
    ["door", "door creak"],
    ["ticket", "paper tear"],
  ]);
  // Found nowhere again: this run's drop replaces the earlier one.
  const retry = () =>
    kit(fx, {
      palette: [{ event: "ticket", query: "paper rip" }],
      dropped: kitOf(fx).dropped,
    });
  retry();
  assert.equal(fetch(fx, {}).code, 0);
  assert.deepEqual(events(), [
    ["door", "door creak"],
    ["ticket", "paper rip"],
  ]);
  // Found: it leaves the list and no longer warns.
  retry();
  const r = fetch(fx, { "paper rip": [[hit("rip-1", "Paper rip")]] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound ticket: openverse rip-1");
  assert.deepEqual(kitOf(fx).dropped, [door]);
  // The last drop found, the list goes too.
  kit(fx, {
    palette: [{ event: "door", query: "paper rip" }],
    dropped: [door],
  });
  assert.equal(fetch(fx, {}).code, 0);
  assert.equal(events(), undefined);
});

test("a malformed sound.json is refused by its field before any search", () => {
  const fx = fixture();
  kit(fx, { palette: [{ event: "ticket" }] });
  const r = fetch(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    r.err.trim(),
    "sounds: project/kit/sound.json: palette[0].query is not text",
  );
  assert.deepEqual(calls(fx), []);
});

test("a malformed queries.json in the store is refused by its path and field", () => {
  const fx = fixture();
  kit(fx);
  const file = store(fx, "queries.json");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const refused = (body, why) => {
    fs.writeFileSync(file, body);
    const r = fetch(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.equal(r.err.trim(), `sounds: ${file} is malformed: ${why}`);
  };
  refused(
    JSON.stringify({ "palette:paper tear": { file: "assets/sounds/x.ogg" } }),
    "palette:paper tear.source is not text",
  );
  refused(
    JSON.stringify({ "bed:kitchen ambience": { source: "openverse:bed-1" } }),
    "bed:kitchen ambience.file is not text",
  );
  refused("[]", "it is not an object");
});
