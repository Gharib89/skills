// A number in a `timeline` or `compare` scene's on-screen text (a `when`, a
// label, a note, a side's title or an item's text) is a claim: the script
// gate holds it to an excerpt the scene cites, as it holds a chart's values.
// A `when` is still display text, shown as written; only its numbers are
// checked.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES, check, edit, fixture, line } from "./check-lib.mjs";

const FACTS = "The local gate runs 1,200 checks in 40 ms, 0.5 percent flaky.";
function gated(visual, text = FACTS) {
  const fx = fixture({ scenes: edit(SCENES, 2, { visual }) });
  // No snapshot to re-check the excerpt against: the pack's text stands.
  fs.rmSync(path.join(fx.dir, "snapshots"), { recursive: true });
  const file = path.join(fx.dir, "excerpts.json");
  const pack = JSON.parse(fs.readFileSync(file, "utf8"));
  pack.excerpts[1].text = text;
  fs.writeFileSync(file, JSON.stringify(pack));
  return line(check(fx), "cites");
}
const event = (when, label, note) => ({
  at: 1,
  when,
  label,
  ...(note && { note }),
});
const timeline = (...items) => ({ component: "timeline", props: { items } });
const compare = (a, b) => ({
  component: "compare",
  props: {
    sides: [a, b].map(([title, ...texts]) => ({
      title,
      items: texts.map((text) => ({ at: 1, text })),
    })),
  },
});

test("a timeline's numbers found word for word in a cited excerpt pass, and text with none needs no cite", () => {
  assert.equal(
    gated(
      timeline(
        event("Day 40", "1,200 checks", "0.5 percent flaky"),
        event("Later", "Every team"),
      ),
    ),
    "script cites: pass",
  );
});

test("a number in a timeline's when, label or note that no cited excerpt holds is refused", () => {
  assert.match(
    gated(timeline(event("late 2019", "Started"))),
    /^script cites: fail: steps: on-screen number "2019" is in none of ex-1, ex-2, ex-3/,
  );
  // `Q3 '21` is shown as written, and both its numbers are claims
  const q = gated(timeline(event("Q3 '21", "Shipped")));
  assert.match(q, /on-screen number "3"/);
  assert.match(q, /on-screen number "21"/);
  assert.match(
    gated(timeline(event("Day 40", "1200 checks"))),
    /on-screen number "1200"/,
  );
  assert.match(
    gated(timeline(event("Day 40", "Shipped", "5 teams"))),
    /on-screen number "5"/,
  );
});

test("a compare's numbers in a side's title or an item's text stand in a cited excerpt", () => {
  assert.equal(
    gated(compare(["Before", "1,200 checks"], ["After", "40 ms", "No flakes"])),
    "script cites: pass",
  );
  assert.match(
    gated(compare(["Top 3", "1,200 checks"], ["After", "40 ms"])),
    /on-screen number "3"/,
  );
  assert.match(
    gated(compare(["Before", "200 checks"], ["After", "40 ms"])),
    /on-screen number "200"/,
  );
});

test("an Arabic number in a timeline stands in the excerpt's own digits", () => {
  const ar = "يشغل الفحص المحلي ١٬٢٠٠ فحص.";
  assert.equal(
    gated(timeline(event("اليوم ١", "١٬٢٠٠ فحص")), `${ar} اليوم ١`),
    "script cites: pass",
  );
  assert.match(
    gated(timeline(event("اليوم", "1,200 فحص")), ar),
    /on-screen number "1,200".*another digit script/,
  );
});
