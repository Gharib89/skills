// The setup stage through its process door, part 4: the fonts a style profile
// carries.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fixture, fontDir, row, run } from "./setup-lib.mjs";

// A profile carrying `fonts` rows, saved into the project store or a run folder
// under `<fx.cwd>/explainers`, where setup looks for them.
const LORA = {
  id: "font:lora",
  kind: "font",
  family: "lora",
  class: "serif",
  version: "5.3.0",
  files: ["latin-400-normal", "latin-600-normal"],
  licence: "OFL-1.1",
};
const INTER = {
  id: "font:inter",
  kind: "font",
  family: "inter",
  version: "5.3.0",
  files: ["latin-400-normal"],
  size: 48116,
  neededBy: "render",
  licence: "OFL-1.1",
};
function withProfile(fx, where, fonts) {
  fx.cwd = path.join(fx.tmp, "project");
  const file = path.join(fx.cwd, "explainers", ...where);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    typeof fonts === "string" ? fonts : JSON.stringify({ fonts }),
  );
}

test("a profile's fetched font shows as missing in the check and installs on the yes", () => {
  const fx = fixture([INTER]);
  withProfile(fx, [".styles", "mine.json"], [LORA]);
  const c = run(fx, ["check"]);
  assert.equal(c.code, 1, c.out + c.err);
  assert.equal(row(c.out, "font:lora")?.[2], "missing", c.out);
  assert.ok(!fs.existsSync(path.join(fontDir(fx), "lora@5.3.0")));
  const i = run(fx, ["install"]);
  assert.equal(i.code, 0, i.out + i.err);
  for (const f of LORA.files)
    assert.ok(
      fs.existsSync(path.join(fontDir(fx), "lora@5.3.0", `${f}.woff2`)),
    );
  assert.ok(fs.existsSync(path.join(fontDir(fx), "lora@5.3.0", ".stamp")));
  assert.equal(run(fx, ["check"]).code, 0);
});

test("the same family and version in a store and a run's style.json is one row", () => {
  const fx = fixture([INTER]);
  withProfile(fx, [".styles", "a.json"], [LORA]);
  withProfile(fx, ["demo", "style.json"], [LORA]);
  const lines = run(fx, ["check"])
    .out.split("\n")
    .filter((l) => l.startsWith("| font:lora |"));
  assert.equal(lines.length, 1);
});

test("a catalogue font a profile also lists is not duplicated", () => {
  const fx = fixture([INTER]);
  withProfile(fx, [".styles", "a.json"], [INTER]);
  const lines = run(fx, ["check"])
    .out.split("\n")
    .filter((l) => l.startsWith("| font:inter |"));
  assert.equal(lines.length, 1);
});

test("a profile that does not parse is a row in the table, not a crash", () => {
  const fx = fixture([INTER]);
  withProfile(fx, [".styles", "broken.json"], "{ not json");
  const r = run(fx, ["check"], "ffmpeg");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.out, /^\| profile:.*broken\.json \|.*\| refused: /m);
});

test("a font folder holding the stamp but lacking one of its files is missing and installs again", () => {
  const fx = fixture([
    INTER,
    {
      ...INTER,
      id: "font:inter2",
      family: "inter2",
      files: ["latin-400-normal", "latin-600-normal"],
    },
  ]);
  assert.equal(run(fx, ["install"]).code, 0);
  fs.rmSync(path.join(fontDir(fx), "inter2@5.3.0", "latin-600-normal.woff2"));
  const c = run(fx, ["check"]);
  assert.equal(row(c.out, "font:inter2")[2], "missing", c.out);
  assert.equal(run(fx, ["install"]).code, 0);
  assert.ok(
    fs.existsSync(
      path.join(fontDir(fx), "inter2@5.3.0", "latin-600-normal.woff2"),
    ),
  );
});

test("a font only a run's style.json carries is listed", () => {
  const fx = fixture([INTER]);
  withProfile(fx, ["demo", "style.json"], [LORA]);
  assert.equal(row(run(fx, ["check"]).out, "font:lora")?.[2], "missing");
});

test("valid JSON of the wrong shape is a refused profile row, not a crash", () => {
  const fx = fixture([INTER]);
  withProfile(fx, [".styles", "null.json"], "null");
  withProfile(fx, [".styles", "notarray.json"], '{"fonts":{"family":"lora"}}');
  withProfile(
    fx,
    [".styles", "nofiles.json"],
    '{"fonts":[{"family":"lora","version":"5.3.0"}]}',
  );
  const r = run(fx, ["check"]);
  assert.equal(r.code, 1, r.out + r.err);
  for (const f of ["null", "notarray", "nofiles"])
    assert.match(
      r.out,
      new RegExp(`^\\| profile:\\S*${f}\\.json \\|.*\\| refused: `, "m"),
    );
});

test("two profiles carrying one family and version with different weights install both", () => {
  const fx = fixture([INTER]);
  withProfile(
    fx,
    [".styles", "a.json"],
    [{ ...LORA, files: ["latin-400-normal"] }],
  );
  withProfile(
    fx,
    ["demo", "style.json"],
    [{ ...LORA, files: ["latin-600-normal"] }],
  );
  assert.equal(run(fx, ["install"]).code, 0);
  for (const f of LORA.files)
    assert.ok(
      fs.existsSync(path.join(fontDir(fx), "lora@5.3.0", `${f}.woff2`)),
    );
});
