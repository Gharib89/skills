// An Arabic source writes its numbers in Arabic-Indic (١٢٠٠) or Persian (۱۲۰۰)
// digits. A `chart` or `stat` value is digits as the excerpt writes them, in
// one script: it passes the script gate verbatim, counts up in the same digits
// and separators, and one in another script is refused with a hint.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { countText } from "../../skills/explainer-video/scripts/lib/count.mjs";
import { checkVisual } from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { SCENES, check, edit, fixture, line } from "./check-lib.mjs";

const said = ["One.", "Two.", "Three."];
const stat = (...values) => ({
  component: "stat",
  props: { items: values.map((value) => ({ at: 1, value, label: "x" })) },
});
// The cites gate's line for a scene showing `visual`, the cited excerpt saying
// `text`.
function gated(visual, text) {
  const fx = fixture({ scenes: edit(SCENES, 2, { visual }) });
  fs.rmSync(path.join(fx.dir, "snapshots"), { recursive: true });
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[1].text = text;
  fs.writeFileSync(file, JSON.stringify(pack));
  return line(check(fx), "cites");
}
const arabic = "تشغيل ١٬٢٠٠ فحص في ٤٠ ثانية.";

test("a value may be written in Arabic-Indic or Persian digits, one script to a number", () => {
  for (const ok of ["١٢٠٠", "١٬٢٠٠", "٠٫٥", "۱۲۰۰", "۱,۲۰۰.۵", "۱٬۲۰۰٫۵"])
    assert.doesNotThrow(() => checkVisual(stat(ok), said), ok);
  for (const no of ["١2", "۱٢", "٠١", "١٬٢٠"])
    assert.throws(
      () => checkVisual(stat(no), said),
      /is not a number written in digits/,
      no,
    );
});

test("a number in the excerpt's own digits passes the cites gate", () => {
  assert.equal(gated(stat("١٬٢٠٠", "٤٠"), arabic), "script cites: pass");
});

test("a number in another script's digits is refused, with a hint to write the excerpt's", () => {
  assert.match(
    gated(stat("1,200"), arabic),
    /on-screen number "1,200" is in none of .*; the excerpt writes it in another digit script/,
  );
});

test("a number must stand whole in the excerpt in any script, and no hint then", () => {
  const r = gated(stat("٢٠٠"), arabic);
  assert.match(r, /on-screen number "٢٠٠" is in none of/);
  assert.doesNotMatch(r, /another digit script/);
});

test("countText counts in the digits and separators the number is written in", () => {
  assert.equal(countText("١٬٢٠٠", 1), "١٬٢٠٠");
  assert.equal(countText("١٬٢٠٠", 0.5), "٦٠٠");
  assert.equal(countText("١٬٢٠٠", 0), "٠");
  assert.equal(countText("۱٬۲۰۰٫۵", 1), "۱٬۲۰۰٫۵");
  assert.equal(countText("۱٫۵", 0.5), "۰٫۸");
  assert.equal(countText("۱,۲۰۰", 1), "۱,۲۰۰");
});
