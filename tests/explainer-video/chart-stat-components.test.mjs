// The `chart` and `stat` components: numbers that count up on their cue, each
// written as the source writes it. Both are rich (they draw their own frame),
// so a `camera` key is refused on them; the script gate holds each number to a
// cited excerpt (see check-gates.test.mjs for that side).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  VISUALS,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { SCENES, check, edit, fixture, line } from "./check-lib.mjs";

const said = [
  "Latency fell to 240 milliseconds.",
  "Then 1,200 requests a second held.",
  "Errors stayed under 0.5 percent.",
];
const chart = (items, more = {}) => ({
  component: "chart",
  props: { kind: "bar", unit: "ms", items, ...more },
});
const stat = (items) => ({ component: "stat", props: { items } });
const item = (at, label, value, on) => ({
  at,
  label,
  value,
  ...(on && { on }),
});
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("chart takes a kind, a unit and items of at, label and value, and refuses the rest", () => {
  assert.doesNotThrow(() =>
    checkVisual(
      chart([
        item(1, "After", "240", "240 milliseconds"),
        item(2, "Rate", "1,200"),
      ]),
      said,
    ),
  );
  assert.doesNotThrow(() =>
    checkVisual(
      chart([item(1, "a", "1"), item(2, "b", "2")], { kind: "line" }),
      said,
    ),
  );
  bad({ component: "chart", props: {} }, /chart needs a kind of bar or line/);
  bad(
    chart([item(1, "a", "1")], { kind: "pie" }),
    /chart needs a kind of bar or line/,
  );
  bad(chart([item(1, "a", "1")], { unit: 4 }), /chart unit needs text/);
  bad(chart([]), /chart needs items/);
  bad(
    chart([item(1, "a", "1")], { kind: "line" }),
    /a line chart needs 2 or more items/,
  );
  bad(chart([item(1, "", "1")]), /chart needs a label per item/);
  bad(chart([item(4, "a", "1")]), /at 4 is not a sentence \(1 to 3\)/);
  bad(
    chart([{ ...item(1, "a", "1"), note: "x" }]),
    /a chart item has no prop note/,
  );
  bad(
    chart([item(1, "a", "1")], { emphasis: {} }),
    /chart has no prop emphasis/,
  );
});

test("stat takes items of at, value and label, and refuses the rest", () => {
  assert.doesNotThrow(() =>
    checkVisual(stat([{ at: 1, value: "240", label: "ms" }]), said),
  );
  bad({ component: "stat", props: {} }, /stat needs items/);
  bad(stat([{ at: 1, value: "240" }]), /stat needs a label per item/);
  bad(stat([{ at: 1, label: "ms" }]), /stat needs a value per item/);
  bad(
    stat([{ at: 1, value: "240", label: "ms", unit: "x" }]),
    /a stat item has no prop unit/,
  );
});

test("a value is a number written as digits, with optional commas and decimals", () => {
  for (const ok of ["0", "7", "240", "1,200", "1200", "0.5", "1,200.25"])
    assert.doesNotThrow(
      () => checkVisual(stat([{ at: 1, value: ok, label: "x" }]), said),
      ok,
    );
  for (const no of ["", "1,20", "01", "1.", ".5", "12 ms", "40%", "ten", 240])
    bad(
      stat([{ at: 1, value: no, label: "x" }]),
      /value .* is not a number written in digits/,
    );
});

test("both are rich, so a camera key on either is refused", () => {
  assert.equal(VISUALS.chart.ownCamera, true);
  assert.equal(VISUALS.stat.ownCamera, true);
  bad(
    { ...chart([item(1, "a", "1")]), camera: { at: 1 } },
    /chart draws its own camera, so it takes no camera key/,
  );
  bad(
    { ...stat([{ at: 1, value: "1", label: "x" }]), camera: { at: 1 } },
    /stat draws its own camera, so it takes no camera key/,
  );
});

test("counts past the guidance (more than 3 stats, 6 bars) still compile", () => {
  const many = (n) =>
    Array.from({ length: n }, (_, i) => item(1 + (i % 3), `l${i}`, `${i + 1}`));
  assert.doesNotThrow(() => checkVisual(chart(many(9)), said));
  assert.doesNotThrow(() =>
    checkVisual(
      stat(many(5).map(({ at, label, value }) => ({ at, label, value }))),
      said,
    ),
  );
});

// The script gate: every on-screen number is in an excerpt the scene cites.
const FACTS = "The local gate runs 1,200 checks in 40 ms, 0.5 percent flaky.";
function gated(visual, text = FACTS) {
  const fx = fixture({ scenes: edit(SCENES, 2, { visual }) });
  // No snapshot to re-check the excerpt against: the pack's text stands.
  fs.rmSync(path.join(fx.dir, "snapshots"), { recursive: true });
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[1].text = text;
  pack.excerpts.push({ ...pack.excerpts[1], id: "ex-4", text: "Only 77 ran." });
  fs.writeFileSync(file, JSON.stringify(pack));
  return line(check(fx), "cites");
}
const gatedStat = (...values) =>
  gated(stat(values.map((value) => ({ at: 1, value, label: "x" }))));

test("numbers found word for word in a cited excerpt pass the cites gate", () => {
  assert.equal(
    gated(
      chart([
        item(1, "Checks", "1,200"),
        item(2, "Time", "40"),
        item(3, "Flaky", "0.5"),
      ]),
    ),
    "script cites: pass",
  );
  assert.equal(gatedStat("1,200", "40", "0.5"), "script cites: pass");
});

test("a number in no cited excerpt is refused, naming the value and the scene", () => {
  assert.match(
    gatedStat("999"),
    /^script cites: fail: steps: on-screen number "999" is in none of ex-1, ex-2, ex-3/,
  );
  assert.match(
    gated(chart([item(1, "a", "1,200"), item(2, "b", "12")])),
    /on-screen number "12" is in none of/,
  );
});

test("a number written differently from the excerpt is refused", () => {
  assert.match(gatedStat("1200"), /on-screen number "1200"/);
  assert.match(gatedStat("0.50"), /on-screen number "0.50"/);
});

test("a number must stand whole in the excerpt, never inside a longer one", () => {
  assert.match(gatedStat("200"), /on-screen number "200"/);
  assert.match(gatedStat("4"), /on-screen number "4"/);
  assert.match(gatedStat("5"), /on-screen number "5"/);
});

test("an excerpt the scene does not cite does not count", () => {
  assert.match(
    gatedStat("77"),
    /on-screen number "77" is in none of ex-1, ex-2, ex-3/,
  );
});
