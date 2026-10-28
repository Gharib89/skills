// The credits stage: CREDITS.md's Voices and Sound sections written from the
// cast and the sound kit, every other section kept.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, fixture, here, write, writeCast } from "./voice-lib.mjs";
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

test("with no CREDITS.md, no cast and no kit, it writes the narrator's voice and no sound", () => {
  const fx = fixture();
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
  const r = exec(credits, fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    read(file(fx)),
    /^## Voices\n\n- chef: am_fenrir \(kokoro, Apache-2\.0\)\n\n/m,
  );
});

test("a run with no script.json is refused by name", () => {
  const fx = fixture();
  fs.rmSync(path.join(fx.dir, "script.json"));
  const r = exec(credits, fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /^credits: .*script\.json/);
});
