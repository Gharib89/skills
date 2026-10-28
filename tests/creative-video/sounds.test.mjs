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
const hit = (id, filetype = "mp3") => ({
  id,
  title: `sound ${id}`,
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
  "kitchen ambience": [[hit("bed-1")]],
  "paper tear": [[{ ...hit("vid", "mp4") }, hit("tear-1", "ogg")]],
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
  const r = fetch(fx, { "paper tear": ["timeout", [hit("tear-1")]] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound ticket: openverse tear-1");
  assert.equal(asked(fx, "openverse").length, 2);
});

test("two timeouts fall back to the Kenney pack whose file names match the query", () => {
  const fx = fixture();
  kit(fx, { palette: [{ event: "ticket", query: "paper tear" }] });
  const pack = store(fx, "kenney", "rpg-audio");
  fs.mkdirSync(pack, { recursive: true });
  for (const f of ["bookFlip1.ogg", "paperTear2.ogg", "License.txt"])
    fs.writeFileSync(path.join(pack, f), f);
  fs.writeFileSync(store(fx, "kenney", ".stamp"), "");
  const r = fetch(fx, { "paper tear": ["timeout"] });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound ticket: kenney rpg-audio/paperTear2.ogg");
  assert.equal(asked(fx, "openverse").length, 2);
  const [entry] = kitOf(fx).palette;
  assert.equal(entry.source, "kenney:rpg-audio/paperTear2.ogg");
  assert.equal(entry.file, "assets/sounds/rpg-audio-paperTear2.ogg");
  assert.equal(entry.licence, "CC0-1.0");
  assert.equal(entry.creator, "Kenney");
  assert.ok(
    fs.existsSync(project(fx, "assets", "sounds", "rpg-audio-paperTear2.ogg")),
  );
});

test("a sound found nowhere is dropped from the kit with why, and warned", () => {
  const fx = fixture();
  kit(fx);
  const r = fetch(fx, { "kitchen ambience": [[hit("bed-1")]] });
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
