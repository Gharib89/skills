// The compile stage on an `excerpt` scene: it reads the run's excerpts.json,
// holds the scene's cite to what its narration cites, and keeps the pack's own
// text and locator in script.json, so the scene file never restates them.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { compiled, fixture, run } from "./compile-lib.mjs";

const TEXT =
  "The cache is cleared on every deploy. Stale entries never survive a release.";
const pack = {
  sources: [{ id: "notes", kind: "md" }],
  excerpts: [
    { id: "ex-1", source: "notes", locator: "§ Caching", text: TEXT },
    { id: "ex-2", source: "notes", locator: "line 9", text: "Other." },
  ],
};
const SCENE = (visual, cites = "[ex-1]") => `# Excerpt
language: en
narrator: am_fenrir
style: claude-code

## Scene proof · The proof

### Narration
1. The cache is wiped on every deploy. ${cites}
2. No stale entry survives. [ex-1]

### Visual
\`\`\`json
${JSON.stringify(visual)}
\`\`\`
`;
const compile = (visual, { cites, withPack = true } = {}) => {
  const fx = fixture(SCENE(visual, cites));
  if (withPack)
    fs.writeFileSync(path.join(fx.dir, "excerpts.json"), JSON.stringify(pack));
  return { fx, r: run(fx) };
};
const excerpt = (props) => ({ component: "excerpt", props });

test("compile keeps the cited excerpt's own text and locator in script.json", () => {
  const { fx, r } = compile(
    excerpt({
      cite: "ex-1",
      emphasis: { target: "Stale entries never survive a release.", at: 2 },
    }),
  );
  assert.equal(r.code, 0, r.err);
  const { props } = compiled(fx).scenes[0].visual;
  assert.deepEqual(props.excerpts, {
    "ex-1": { text: TEXT, locator: "§ Caching", code: false },
  });
  assert.equal(props.cite, "ex-1");
});

test("compile refuses an excerpt the narration does not cite, naming its scene", () => {
  const { r } = compile(excerpt({ cite: "ex-2" }));
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: proof: excerpt cite "ex-2" is not cited by the scene's narration \(ex-1\)$/m,
  );
});

test("compile refuses an excerpt scene with no pack in the run folder", () => {
  const { r } = compile(excerpt({ cite: "ex-1" }), { withPack: false });
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: proof: excerpt needs excerpts\.json beside the scene file/m,
  );
});

test("compile refuses an emphasis that is no sentence of the excerpt", () => {
  const { r } = compile(
    excerpt({
      cite: "ex-1",
      emphasis: { target: "Stale entries survive.", at: 2 },
    }),
  );
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^compile: proof: excerpt emphasis target .* is no sentence of ex-1$/m,
  );
});
