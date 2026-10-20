// The `timeline` and `compare` components at compile: a timeline's `when` is
// display text, never parsed, and a compare holds exactly two sides. Both are
// rich (they draw their own frame), so a `camera` key is refused on them.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { checkVisual } from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { fixture, run } from "./compile-lib.mjs";

const said = [
  "It began as a side project.",
  "Then it shipped to every team.",
  "Now it runs the whole build.",
];
const timeline = (items) => ({ component: "timeline", props: { items } });
const compare = (sides) => ({ component: "compare", props: { sides } });
const side = (title, items) => ({ title, items });
const row = (at, text, on) => ({ at, text, ...(on && { on }) });
const bad = (visual, why) =>
  assert.throws(() => checkVisual(visual, said), why);

test("compare takes exactly two sides, and refuses any other count at compile", () => {
  const a = side("Before", [row(1, "Manual")]);
  const b = side("After", [row(2, "Automatic")]);
  assert.doesNotThrow(() => checkVisual(compare([a, b]), said));
  bad({ component: "compare", props: {} }, /compare needs 2 sides/);
  bad(compare([a]), /compare needs 2 sides/);
  bad(compare([a, b, a]), /compare needs 2 sides/);
});

test("the compile stage refuses a compare of three sides and writes no script", () => {
  const sides = ["A", "B", "C"].map((t, i) => side(t, [row(i + 1, t)]));
  const fx = fixture(`# Compare
language: en
narrator: am_fenrir

## Scene only · The only scene

### Narration
1. It reads the issue. [ex-1]
2. It writes a failing test. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
${JSON.stringify(compare(sides))}
\`\`\`
`);
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^compile: only: compare needs 2 sides/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "script.json")));
});

test("compare sides take a title and items of at, on and text, and refuse the rest", () => {
  const b = side("After", [row(2, "Automatic")]);
  assert.doesNotThrow(() =>
    checkVisual(
      compare([side("Before", [row(1, "Manual", "side project")]), b]),
      said,
    ),
  );
  bad(compare([side("", [row(1, "a")]), b]), /compare needs a title per side/);
  bad(compare([side("A", []), b]), /compare side needs items/);
  bad(compare([side("A", ["x"]), b]), /a compare side item is not a JSON/);
  bad(compare([side("A", [{ at: 1 }]), b]), /compare needs a text per item/);
  bad(compare([side("A", [row(1, " ")]), b]), /compare needs a text per item/);
  bad(compare([side("A", [row(4, "a")]), b]), /at 4 is not a sentence/);
  bad(
    compare([side("A", [row(1, "a", "no such words")]), b]),
    /on "no such words" is not said in sentence 1/,
  );
  bad(
    compare([{ ...side("A", [row(1, "a")]), note: "x" }, b]),
    /a compare side has no prop note/,
  );
  bad(
    compare([side("A", [{ ...row(1, "a"), label: "x" }]), b]),
    /a compare item has no prop label/,
  );
  bad(
    {
      component: "compare",
      props: { sides: [side("A", [row(1, "a")]), b], emphasis: {} },
    },
    /compare has no prop emphasis/,
  );
});

test("no compare item cues before its side's first item, which brings in the side's title", () => {
  const b = side("After", [row(3, "Automatic")]);
  // the same sentence, a later phrase of it, and a later sentence all pass
  assert.doesNotThrow(() =>
    checkVisual(
      compare([
        side("Before", [
          row(1, "a"),
          row(1, "b"),
          row(1, "c", "side project"),
          row(2, "d"),
        ]),
        b,
      ]),
      said,
    ),
  );
  bad(
    compare([side("Before", [row(2, "a"), row(1, "b")]), b]),
    /compare side "Before" item 2 cues before item 1/,
  );
  bad(
    compare([side("Before", [row(1, "a", "side project"), row(1, "b")]), b]),
    /compare side "Before" item 2 cues before item 1/,
  );
});

test("timeline takes items of at, on, when, label and note, and refuses the rest", () => {
  assert.doesNotThrow(() =>
    checkVisual(
      timeline([
        { at: 1, on: "side project", when: "Spring 2019", label: "Started" },
        { at: 2, when: "Q3 2021", label: "Shipped", note: "every team" },
      ]),
      said,
    ),
  );
  bad({ component: "timeline", props: {} }, /timeline needs items/);
  bad(timeline([{ at: 1, label: "a" }]), /timeline needs a when per item/);
  bad(
    timeline([{ at: 1, when: " ", label: "a" }]),
    /timeline needs a when per item/,
  );
  bad(timeline([{ at: 1, when: "2019" }]), /timeline needs a label per item/);
  bad(
    timeline([{ at: 4, when: "2019", label: "a" }]),
    /at 4 is not a sentence/,
  );
  bad(
    timeline([{ at: 1, when: "2019", label: "a", date: "2019-01-01" }]),
    /a timeline item has no prop date/,
  );
});

test("both are rich, so a camera key on either is refused", () => {
  bad(
    { ...timeline([{ at: 1, when: "2019", label: "a" }]), camera: { at: 1 } },
    /timeline draws its own camera, so it takes no camera key/,
  );
  bad(
    {
      ...compare([side("A", [row(1, "a")]), side("B", [row(2, "b")])]),
      camera: { at: 1 },
    },
    /compare draws its own camera, so it takes no camera key/,
  );
});
