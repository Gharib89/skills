// The compile stage and sections: a `section` role opens each group of two to
// five points with a short title card, and each scene learns its section.
import { test } from "node:test";
import assert from "node:assert/strict";
import { compiled, fixture, run } from "./compile-lib.mjs";
import { LAYOUT, edit, sectionFile } from "./sections-lib.mjs";

test("each scene takes the number of its section: hook and context join the first, recap and end the last", () => {
  const fx = fixture(sectionFile());
  const r = run(fx);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(
    compiled(fx).scenes.map((s) => [s.id, s.role, s.section]),
    [
      ["hook", "hook", 1],
      ["why", "context", 1],
      ["one", "section", 1],
      ["one-a", "point", 1],
      ["one-b", "point", 1],
      ["two", "section", 2],
      ["two-a", "point", 2],
      ["two-b", "point", 2],
      ["three", "section", 3],
      ["three-a", "point", 3],
      ["three-b", "point", 3],
      ["recap", "recap", 3],
      ["bye", "end", 3],
    ],
  );
});

test("a script with no section role carries no section number", () => {
  const fx = fixture(
    sectionFile(
      LAYOUT.filter((s) => s.role !== "section" && !/^(two|three)/.test(s.id)),
    ),
  );
  assert.equal(run(fx).code, 0);
  assert.ok(compiled(fx).scenes.every((s) => !("section" in s)));
});

test("a section of fewer than two or more than five points is refused", () => {
  const six = [
    ...LAYOUT.slice(0, 5),
    ...["c", "d", "e", "f"].map((id) => ({ id, role: "point", seconds: 15 })),
    ...LAYOUT.slice(5),
  ];
  for (const [layout, why] of [
    [
      edit("one-b", null),
      /^compile: one: the section holds 1 point, want 2 to 5$/m,
    ],
    [
      edit("one-a", null, edit("one-b", null)),
      /^compile: one: the section holds 0 points, want 2 to 5$/m,
    ],
    [six, /^compile: one: the section holds 6 points, want 2 to 5$/m],
  ]) {
    const r = run(fixture(sectionFile(layout)));
    assert.equal(r.code, 1, r.out);
    assert.match(r.err, why);
  }
});

test("a section opener outside 6 to 12 s is refused, and 6 and 12 stand", () => {
  for (const seconds of [5.9, 12.1]) {
    const r = run(fixture(sectionFile(edit("two", { seconds }))));
    assert.equal(r.code, 1, String(seconds));
    assert.match(
      r.err,
      new RegExp(
        `^compile: two: the section opener is ${seconds} s, want 6 to 12 s$`,
        "m",
      ),
    );
  }
  for (const seconds of [6, 12])
    assert.equal(run(fixture(sectionFile(edit("two", { seconds })))).code, 0);
});
