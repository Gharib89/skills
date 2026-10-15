// The source stage's second half: each reader's excerpts checked against its
// snapshot, then numbered into the source pack.
//
//   node pack.mjs <run-folder> [<id>]
//
// Reads <run>/snapshots/sources.json and each source's draft,
// <run>/snapshots/<id>.draft.json, which its reader writes:
//   { "summary": "...", "excerpts": [{ "locator", "text", "note" }] }
// An excerpt passes when its locator is one its source's kind takes, names a
// stretch of the snapshot, and that stretch holds its text word for word
// (whitespace runs read as one space). A draft holds at most its source's
// share of the budget. With <id>, checks that draft alone and writes nothing.
// stdout: `pack <id>: <n> of <share> excerpt(s): pass` per draft, then
//         `pack: <n> excerpt(s) from <m> source(s) -> excerpts.json, outline.md`
// stderr: `pack <id>: [excerpt <k>: ]<why>` per problem
// writes: <run>/excerpts.json, <run>/outline.md, explainers/.gitignore
// exit:   0 pass · 1 a problem · 2 usage
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";
import { segment, squash } from "./locators.mjs";

const [run, only, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node pack.mjs <run-folder> [<id>]");
  process.exit(2);
}
const index = path.join(run, "snapshots", "sources.json");
if (!fs.existsSync(index)) {
  console.error("pack: no snapshots/sources.json: run snapshot.mjs first");
  process.exit(1);
}
const { minutes, budget, sources } = JSON.parse(fs.readFileSync(index, "utf8"));
const chosen = only ? sources.filter((s) => s.id === only) : sources;
if (!chosen.length) {
  console.error(
    `pack: no source ${only}; the sources are ${sources.map((s) => s.id).join(", ")}`,
  );
  process.exit(1);
}

let failed = false;
const problem = (id, why) => {
  failed = true;
  console.error(`pack ${id}: ${why}`);
};
const drafts = new Map();
for (const src of chosen) {
  const file = path.join(run, "snapshots", `${src.id}.draft.json`);
  let draft;
  try {
    draft = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    problem(
      src.id,
      e.code === "ENOENT"
        ? `no draft at snapshots/${src.id}.draft.json`
        : `snapshots/${src.id}.draft.json: ${e.message}`,
    );
    continue;
  }
  const excerpts = Array.isArray(draft.excerpts) ? draft.excerpts : null;
  if (!excerpts || typeof draft.summary !== "string" || !draft.summary.trim()) {
    problem(src.id, 'a draft holds a "summary" and an "excerpts" list');
    continue;
  }
  if (excerpts.length > src.share)
    problem(
      src.id,
      `${excerpts.length} excerpts over its share of ${src.share} (budget ${budget})`,
    );
  excerpts.forEach((ex, k) => {
    const at = `excerpt ${k + 1}`;
    for (const f of ["locator", "text", "note"])
      if (typeof ex[f] !== "string" || !ex[f].trim())
        return problem(src.id, `${at}: no ${f}`);
    const seg = segment(run, src, ex.locator.trim());
    if (seg.error) return problem(src.id, `${at}: ${ex.locator}: ${seg.error}`);
    if (!squash(seg.text).includes(squash(ex.text)))
      problem(src.id, `${at}: not word for word in ${ex.locator}`);
  });
  drafts.set(src.id, draft);
}
if (failed) process.exit(1);
for (const src of chosen)
  console.log(
    `pack ${src.id}: ${drafts.get(src.id).excerpts.length} of ${src.share} excerpt(s): pass`,
  );
if (only) process.exit(0);

// Numbered across the pack in source order: ex-1, ex-2, ...
let n = 0;
const excerpts = sources.flatMap((src) =>
  drafts.get(src.id).excerpts.map((ex) => ({
    id: `ex-${++n}`,
    source: src.id,
    locator: ex.locator.trim(),
    text: ex.text.trim(),
    note: ex.note.trim(),
  })),
);
const pack = {
  minutes,
  budget,
  sources: sources.map(({ id, kind, source, title }) => ({
    id,
    kind,
    source,
    title,
    summary: drafts.get(id).summary.trim(),
  })),
  excerpts,
};
fs.writeFileSync(
  path.join(run, "excerpts.json"),
  JSON.stringify(pack, null, 2) + "\n",
);
const outline = [
  "# Source pack",
  "",
  `${excerpts.length} excerpt(s) of a budget of ${budget} (${minutes} min at 8 per minute, at least 12).`,
  ...pack.sources.flatMap((s) => [
    "",
    `## ${s.id} · ${s.kind} · ${s.title}`,
    "",
    `Source: ${s.source}`,
    "",
    s.summary,
    "",
    ...excerpts
      .filter((ex) => ex.source === s.id)
      .map((ex) => `- ${ex.id} · ${ex.locator} · ${ex.note}`),
  ]),
];
fs.writeFileSync(path.join(run, "outline.md"), outline.join("\n") + "\n");
writeIgnore(run);
console.log(
  `pack: ${excerpts.length} excerpt(s) from ${sources.length} source(s) -> excerpts.json, outline.md`,
);
