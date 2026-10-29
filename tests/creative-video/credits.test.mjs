// The credits stage: CREDITS.md's Voices and Sound sections written from the
// cast and the sound kit, every other section kept.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, fixture, here, run, write, writeCast } from "./voice-lib.mjs";
import { exec, project, read } from "./timing-lib.mjs";

const credits = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "render",
  "credits.mjs",
);
const KIT = {
  bed: {
    query: "kitchen ambience",
    level: -28,
    source: "openverse:bed-1",
    file: "assets/sounds/bed-1.mp3",
    licence: "CC0-1.0",
    creator: "someone",
    url: "https://freesound.org/s/bed-1",
    attribution: '"sound bed-1" by someone is marked with CC0 1.0.',
  },
  palette: [
    {
      event: "ticket",
      query: "bell ding",
      source: "kenney:rpg-audio/bell1.ogg",
      file: "assets/sounds/rpg-audio-bell1.ogg",
      licence: "CC0-1.0",
      creator: "Kenney",
      url: "https://kenney.nl/assets/rpg-audio",
    },
  ],
  dropped: [{ event: "pop", query: "pop", why: "found nowhere" }],
};
const file = (fx) => path.join(fx.dir, "CREDITS.md");
// Credits read the voices voice.json recorded, so each run is voiced first.
const voice = (fx) => {
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
};

test("with no CREDITS.md, no cast and no kit, it writes the narrator's voice and no sound", () => {
  const fx = fixture();
  voice(fx);
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(
    read(file(fx)),
    "# Credits\n\n## Voices\n\n- narrator: af_heart (kokoro, Apache-2.0)\n\n## Sound\n\n- none but the narration\n",
  );
});

test("each cast role's voice and each kit sound is credited, dropped sounds as dropped, and the other sections kept", () => {
  const fx = fixture();
  write(fx, [...SCENES.slice(0, 2), { ...SCENES[2], roles: ["chef"] }]);
  writeCast(fx, {
    narrator: { voices: { en: "bf_emma" } },
    chef: { voices: { en: "am_fenrir" } },
  });
  voice(fx);
  fs.writeFileSync(project(fx, "kit", "sound.json"), JSON.stringify(KIT));
  fs.writeFileSync(
    file(fx),
    "# Credits\n\n## Sources\n\n- a source\n\n## Sound\n\n- stale\n\n## Faces\n\n- a face\n",
  );
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(
    read(file(fx)),
    [
      "# Credits\n\n## Sources\n\n- a source\n\n## Sound\n\n",
      '- bed: openverse:bed-1, CC0-1.0, by someone, https://freesound.org/s/bed-1, "sound bed-1" by someone is marked with CC0 1.0.\n',
      "- ticket: kenney:rpg-audio/bell1.ogg, CC0-1.0, by Kenney, https://kenney.nl/assets/rpg-audio\n",
      "- pop: dropped (found nowhere)\n\n",
      "## Faces\n\n- a face\n\n",
      "## Voices\n\n- narrator: bf_emma (kokoro, Apache-2.0)\n- chef: am_fenrir (kokoro, Apache-2.0)\n",
    ].join(""),
  );
  // Run again, nothing changes.
  const before = read(file(fx));
  assert.equal(exec(credits, fx).code, 0);
  assert.equal(read(file(fx)), before);
});

test("a narrator no sentence speaks is not credited", () => {
  const fx = fixture();
  write(
    fx,
    SCENES.map((s) => ({ ...s, roles: s.narration.map(() => "chef") })),
  );
  writeCast(fx, { chef: { voices: { en: "am_fenrir" } } });
  voice(fx);
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    read(file(fx)),
    /^## Voices\n\n- chef: am_fenrir \(kokoro, Apache-2\.0\)\n\n/m,
  );
});

test("credits name the voices voice.json voiced, not a cast.json edited since", () => {
  const fx = fixture();
  write(fx, [...SCENES.slice(0, 2), { ...SCENES[2], roles: ["chef"] }]);
  writeCast(fx, { chef: { voices: { en: "am_fenrir" } } });
  voice(fx);
  writeCast(fx, { chef: { voices: { en: "bf_emma" } } });
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(read(file(fx)), /^- chef: am_fenrir \(kokoro, Apache-2\.0\)$/m);
});

test("a brand.json is credited as a Brand section: where it came from, each colour, face and fetched page, and the logo or none", () => {
  const fx = fixture();
  voice(fx);
  const doc = {
    name: "itworx",
    from: "fetched",
    once: true,
    colours: [
      {
        hex: "#161b8c",
        name: "ink",
        basis: "measured",
        from: "https://itworx.test/",
      },
      { hex: "#ffffff", name: "ground", basis: "declared", from: "seed" },
    ],
    faces: [
      { family: "inter", role: "text", basis: "measured", licence: "OFL-1.1" },
      {
        family: "source-serif-4",
        role: "title",
        basis: "replaced",
        was: "Tiempos Headline",
        why: "not on Fontsource",
        licence: "OFL-1.1",
      },
    ],
    logo: null,
    fetched: [{ url: "https://itworx.test/", gave: "colours, faces" }],
  };
  const brand = path.join(fx.dir, "brand.json");
  fs.writeFileSync(brand, JSON.stringify(doc));
  fs.writeFileSync(
    file(fx),
    "# Credits\n\n## Brand\n\n- stale\n\n## Faces\n\n- a face\n",
  );
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  const section = read(file(fx)).match(/^## Brand\n\n([\s\S]*?)\n\n## /m)[1];
  assert.equal(
    section,
    [
      "- itworx, from fetched, used once",
      "- colour #161b8c (ink): measured, https://itworx.test/",
      "- colour #ffffff (ground): declared, seed",
      "- face inter (text): measured, OFL-1.1",
      "- face source-serif-4 (title): replaced, replaces Tiempos Headline, OFL-1.1",
      "- logo: none found",
      "- fetched https://itworx.test/: colours, faces",
    ].join("\n"),
  );
  assert.match(read(file(fx)), /^## Faces\n\n- a face\n/m);
  fs.writeFileSync(
    brand,
    JSON.stringify({
      ...doc,
      once: false,
      from: "store",
      fetched: [],
      logo: { file: "brand/logo.svg", source: "https://itworx.test/press" },
    }),
  );
  assert.equal(exec(credits, fx).code, 0);
  assert.match(
    read(file(fx)),
    /^- itworx, from store\n(- colour .*\n){2}(- face .*\n){2}- logo: https:\/\/itworx\.test\/press\n\n/m,
  );
});

test("a run with no brand.json has no Brand section, an older one removed", () => {
  const fx = fixture();
  voice(fx);
  assert.equal(exec(credits, fx).code, 0);
  assert.doesNotMatch(read(file(fx)), /## Brand/);
  fs.writeFileSync(
    file(fx),
    "# Credits\n\n## Brand\n\n- stale\n\n## Faces\n\n- a face\n",
  );
  assert.equal(exec(credits, fx).code, 0);
  assert.doesNotMatch(read(file(fx)), /## Brand|stale/);
  assert.match(read(file(fx)), /^## Faces\n\n- a face\n/m);
});

test("a malformed brand.json is refused by the field", () => {
  const fx = fixture();
  voice(fx);
  fs.writeFileSync(
    path.join(fx.dir, "brand.json"),
    JSON.stringify({ name: "itworx", from: "web" }),
  );
  const r = exec(credits, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^credits: brand\.json: from is not store, seed/m);
});

test("a run with no voice.json, or one with no voices or no roles, is refused by name", () => {
  const fx = fixture();
  const r = exec(credits, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^credits: .*voice\.json/);
  voice(fx);
  const json = path.join(fx.dir, "voice.json");
  const voiced = JSON.parse(read(json));
  const refused = (doc) => {
    fs.writeFileSync(json, JSON.stringify(doc));
    const bad = exec(credits, fx);
    assert.equal(bad.code, 1);
    return bad.err.trim();
  };
  const { voices: _, ...noVoices } = voiced;
  assert.equal(
    refused(noVoices),
    "credits: voice.json: voices is not an object",
  );
  const [{ roles: __, ...noRoles }, ...rest] = voiced.scenes;
  assert.equal(
    refused({ ...voiced, scenes: [noRoles, ...rest] }),
    "credits: voice.json: scenes[0].roles is not a list",
  );
});
