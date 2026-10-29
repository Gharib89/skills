// The setup stage through its process door, part 4: Kenney's sound packs into
// the sound store.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { INDEX as index } from "../../skills/creative-video/scripts/sound/kenney.mjs";
import { FAKE_SHA, calls, fixture, realRows, row, run } from "./setup-lib.mjs";

const kenney = realRows().find((r) => r.id === "sounds:kenney");
const npm = realRows().find((r) => r.kind === "npm");
const store = (fx) =>
  path.join(fx.tmp, "data", "creative-video", "sounds", "kenney");

test("the Kenney row lists its size and CC0 licence, writing to the sound store", () => {
  const fx = fixture([kenney]);
  const cells = row(run(fx, ["check"]).out, "sounds:kenney");
  assert.deepEqual(cells.slice(2), [
    "missing",
    "12 MB",
    "CC0-1.0 (Kenney's sound packs)",
    store(fx),
  ]);
});

test("install downloads each pinned pack, checks its sha256 and unpacks it into its own folder", () => {
  const fx = fixture([npm, kenney]);
  const r = run(fx, ["install"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(row(r.out, "sounds:kenney")[2], "present");
  assert.deepEqual(
    calls(fx)
      .filter((c) => c.call === "download")
      .map((c) => c.url),
    kenney.packs.map((p) => p.url),
  );
  for (const p of kenney.packs) {
    const dir = path.join(store(fx), p.name);
    assert.deepEqual(fs.readdirSync(dir).sort(), [
      "License.txt",
      `${Object.keys(index[p.name])[0]}_001.ogg`,
    ]);
  }
  assert.ok(fs.existsSync(path.join(store(fx), ".stamp")));
});

test("a pack holding a stem the word index lacks fails the row and leaves no store", () => {
  const fx = fixture([npm, kenney]);
  const file = path.join(fx.skill, "setup", "kenney-index.json");
  const { beltHandle, ...rest } = index["rpg-audio"];
  fs.writeFileSync(file, JSON.stringify({ ...index, "rpg-audio": rest }));
  const r = run(fx, ["install"]);
  assert.equal(r.code, 1);
  assert.equal(
    row(r.out, "sounds:kenney")[2],
    "failed: rpg-audio holds beltHandle, which the Kenney word index lacks",
  );
  assert.ok(!fs.existsSync(path.join(store(fx), ".stamp")));
});

test("a pack whose sha256 differs fails the row and leaves no store", () => {
  const bad = {
    ...kenney,
    packs: [{ ...kenney.packs[0], sha256: "0".repeat(64) }],
  };
  const fx = fixture([npm, bad]);
  const r = run(fx, ["install"]);
  assert.equal(r.code, 1);
  assert.equal(
    row(r.out, "sounds:kenney")[2],
    `failed: rpg-audio.zip has sha256 ${FAKE_SHA}, pinned ${"0".repeat(64)}`,
  );
  assert.ok(!fs.existsSync(path.join(store(fx), ".stamp")));
});
