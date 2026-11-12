// A bed from Openverse must loop clean: of the first results of its query, the
// first whose loop seam measures clean is kept (lib/seam.mjs), a dirty download
// is removed, and a bed none of whose results qualifies is dropped with each
// outcome counted.
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
  bed: { world: "a kitchen", query: "kitchen ambience", level: -12 },
  palette: [{ event: "ticket", query: "paper tear" }],
};
const hit = (id, title) => ({
  id,
  title,
  url: `https://cdn.example/${id}.mp3`,
  filetype: "mp3",
  duration: 60000,
  license: "cc0",
  license_version: "1.0",
  creator: "someone",
  foreign_landing_url: `https://freesound.org/s/${id}`,
  attribution: `"sound ${id}" by someone is marked with CC0 1.0.`,
});
function kit(fx, k) {
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "sound.json"), JSON.stringify(k));
}
const kitOf = (fx) => readJson(project(fx, "kit", "sound.json"));
const asked = (fx, call) => calls(fx).filter((c) => c.call === call);

const BEDS = {
  "kitchen ambience": [
    [
      hit("bed-1", "Kitchen Ambience"),
      hit("bed-2", "Kitchen Ambience 2"),
      hit("bed-3", "Kitchen Ambience 3"),
    ],
  ],
};
const fetchSeams = (fx, seams) =>
  exec(sounds, fx, [fx.dir], {
    CREATIVE_VIDEO_FAKE_OPENVERSE: JSON.stringify(BEDS),
    CREATIVE_VIDEO_FAKE_SEAM: JSON.stringify(seams),
  });

test("a bed is the first result whose loop seam measures clean: a click or a fade at the join is skipped for the next", () => {
  const fx = fixture();
  kit(fx, { bed: KIT.bed });
  const r = fetchSeams(fx, { "bed-1.mp3": "click", "bed-2.mp3": "fade" });
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out.trim(), "sound bed: openverse bed-3");
  assert.equal(kitOf(fx).bed.file, "assets/sounds/bed-3.mp3");
  // A dirty download is not kept, so a re-run measures it again.
  assert.ok(!fs.existsSync(store(fx, "openverse", "bed-1.mp3")));
  assert.ok(fs.existsSync(store(fx, "openverse", "bed-3.mp3")));
  assert.deepEqual(
    asked(fx, "pcm").map((c) => c.file),
    ["bed-1.mp3", "bed-2.mp3", "bed-3.mp3"],
  );
});

test("a bed none of whose results loops clean is dropped with each outcome counted, and a palette sound's seam is never measured", () => {
  const fx = fixture();
  kit(fx, KIT);
  const r = fetchSeams(fx, {
    "bed-1.mp3": "click",
    "bed-2.mp3": "click",
    "bed-3.mp3": "fade",
  });
  assert.equal(r.code, 0, r.out + r.err);
  const k = kitOf(fx);
  assert.equal(k.bed, undefined);
  assert.match(
    k.dropped.find((d) => d.event === "bed").why,
    /^openverse found no result whose loop seam is clean \(3 unclean\)/,
  );
  assert.deepEqual(
    asked(fx, "pcm").map((c) => c.file),
    ["bed-1.mp3", "bed-2.mp3", "bed-3.mp3"],
  );
});

test("a bed that one result will not decode still names the loops measured and rejected", () => {
  const fx = fixture();
  kit(fx, { bed: KIT.bed });
  const r = fetchSeams(fx, {
    "bed-1.mp3": "undecodable",
    "bed-2.mp3": "click",
    "bed-3.mp3": "fade",
  });
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    kitOf(fx).dropped.find((d) => d.event === "bed").why,
    /^openverse found no result whose loop seam is clean \(2 unclean, 1 undecodable\)/,
  );
});
