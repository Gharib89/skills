// The script gates: the compiled script checked against the brief, the source
// pack and the support checker's verdicts before anything is voiced.
//
//   node check.mjs <run-folder>
//
// Reads <run>/script.json, script.md, brief.json, excerpts.json, the
// snapshots when present, and support.json, which the support checker writes:
//   { "sentences": [{ "scene", "n", "text", "verdict", "why" }] }
// `text` is the sentence's compiled narration, so a verdict on another
// wording judges nothing; `verdict` is supported or connective (a pass),
// unsupported or unmarked (a [no-claim] sentence that makes a claim).
// stdout: `script <gate>: pass|fail: <findings>|warn: <findings>` per gate
//         (arc, budget, cites, support, coverage, reading, dashes,
//         sentences), then `script: <p> pass, <f> fail, <w> warn`, ending on
//         a red support verdict in `; next: fix attempt <a> of 2` or `; stop:
//         unsupported claims after two fix attempts`
// writes: <run>/check.json, the machine record and the support attempts
// exit:   0 no gate failed · 1 a gate failed, or `script: <why>` on stderr
//         when an input is missing · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { skill } from "../lib/tools.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { segment, squash } from "../source/locators.mjs";

const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node check.mjs <run-folder>");
  process.exit(2);
}
const file = (f) => path.join(run, f);
function need(f, why) {
  if (!fs.existsSync(file(f))) {
    console.error(`script: no ${f}: ${why}`);
    process.exit(1);
  }
  return fs.readFileSync(file(f), "utf8");
}
const script = JSON.parse(need("script.json", "compile first"));
const brief = JSON.parse(need("brief.json", "run brief.mjs first"));
const pack = JSON.parse(need("excerpts.json", "run the source stage first"));
const md = need("script.md", "write the scene file first");

const narrators = JSON.parse(
  fs.readFileSync(path.join(skill, "narrators.json"), "utf8"),
).narrators;
const narrator = narrators.find((n) =>
  script.narrator
    ? n.id === script.narrator
    : n.language === script.language && n.default,
);
const words = (s) => s.split(/\s+/).filter(Boolean).length;
const scenes = script.scenes.map((s) => ({
  ...s,
  counts: s.narration.map(words),
}));
const gates = {};

// arc: one hook, one context, one or more points, one recap, one end.
{
  const f = scenes
    .filter((s) => !s.role)
    .map((s) => `${s.id} has no role line`);
  const roles = scenes.map((s) => s.role ?? "?");
  if (!f.length && !/^hook,context,(point,)+recap,end$/.test(roles.join(",")))
    f.push(
      `roles ${roles.join(", ")}; want hook, context, point..., recap, end`,
    );
  gates.arc = f;
}

// budget: 12 to 30 s a scene, its spoken words within 10 percent of its
// seconds at the narrator's rate, and the scenes within 10 percent of the
// brief's length.
{
  const f = [];
  for (const s of scenes.filter((s) => s.seconds)) {
    if (s.seconds < 12 || s.seconds > 30)
      f.push(`${s.id} ${s.seconds} s is outside 12 to 30 s`);
    const budget = s.seconds * narrator.rate;
    const n = s.counts.reduce((a, b) => a + b, 0);
    if (Math.abs(n - budget) > budget * 0.1)
      f.push(
        `${s.id} ${n} words vs ${Math.round(budget)} (${s.seconds} s at ${narrator.rate}/s) ±10%`,
      );
  }
  const total = scenes.reduce((a, s) => a + (s.seconds ?? 0), 0);
  const want = brief.length * 60;
  if (Math.abs(total - want) > want * 0.1)
    f.push(`the scenes run ${total} s vs the brief's ${want} s ±10%`);
  gates.budget = f;
}

// cites: every cite in the pack, and each cited excerpt still word for word
// in its snapshot when the snapshots are there.
{
  const f = [];
  const byId = new Map(pack.excerpts.map((x) => [x.id, x]));
  const sourcesFile = file(path.join("snapshots", "sources.json"));
  const sources = fs.existsSync(sourcesFile)
    ? JSON.parse(fs.readFileSync(sourcesFile, "utf8")).sources
    : null;
  const seen = new Set();
  for (const s of scenes)
    s.cites.forEach((cites, i) => {
      for (const id of cites) {
        const ex = byId.get(id);
        if (!ex) {
          f.push(`${s.id} ${i + 1}: ${id} is not in excerpts.json`);
          continue;
        }
        const src = sources?.find((x) => x.id === ex.source);
        if (!src || seen.has(id)) continue;
        seen.add(id);
        const seg = segment(run, src, ex.locator);
        if (!seg.texts?.some((t) => squash(t).includes(squash(ex.text))))
          f.push(`${id} is no longer word for word in ${ex.locator}`);
      }
    });
  gates.cites = f;
}

// support: every sentence judged, on its present wording, as supported or
// connective.
const record = fs.existsSync(file("check.json"))
  ? JSON.parse(fs.readFileSync(file("check.json"), "utf8"))
  : null;
let support = { attempts: 0, judged: null };
let red = false;
{
  const f = [];
  if (!fs.existsSync(file("support.json")))
    f.push("no support.json: run the support check");
  else {
    const raw = fs.readFileSync(file("support.json"), "utf8");
    const verdicts = JSON.parse(raw).sentences ?? [];
    let judged = true;
    for (const s of scenes)
      s.narration.forEach((text, i) => {
        const v = verdicts.find(
          (x) => x.scene === s.id && x.n === i + 1 && x.text === text,
        );
        if (!v) {
          judged = false;
          f.push(`${s.id} ${i + 1} not judged: run the support check`);
        } else if (!["supported", "connective"].includes(v.verdict))
          f.push(`${s.id} ${i + 1} ${v.verdict}: ${v.why}`);
      });
    const hash = crypto.createHash("sha256").update(raw).digest("hex");
    const prev = record?.support ?? support;
    // A red verdict is a fix attempt once per set of verdicts, so judging the
    // same verdicts again counts nothing.
    red = judged && f.length > 0;
    support = red
      ? {
          attempts: prev.judged === hash ? prev.attempts : prev.attempts + 1,
          judged: hash,
        }
      : judged
        ? { attempts: 0, judged: hash }
        : prev;
  }
  gates.support = f;
}

// coverage: each must-include item said or shown, no avoid item anywhere.
{
  const f = [];
  const strings = (x) =>
    typeof x === "string"
      ? [x]
      : x && typeof x === "object"
        ? Object.values(x).flatMap(strings)
        : [];
  const text = (s) =>
    [
      ...s.narration,
      ...s.captions.flat().map((c) => c.text),
      s.title,
      ...strings(s.visual.props),
    ]
      .join("\n")
      .toLowerCase();
  for (const m of brief.must)
    if (!scenes.some((s) => text(s).includes(m.toLowerCase())))
      f.push(`must "${m}" is not said or shown`);
  for (const a of brief.avoid) {
    const hit = scenes.filter((s) => text(s).includes(a.toLowerCase()));
    if (hit.length)
      f.push(`avoid "${a}" is in ${hit.map((s) => s.id).join(", ")}`);
  }
  gates.coverage = f;
}

// reading: each visual item on screen long enough to read, from the sentence
// it rises at to the scene's end, timed by its share of the scene's words. A
// text of at most three words is a label, 0.8 s; a longer one 0.3 s a word
// and 1.2 s at least; an item's texts add up.
{
  const f = [];
  const floor = (t) => {
    const n = words(String(t ?? ""));
    return !n ? 0 : n <= 3 ? 0.8 : Math.max(1.2, 0.3 * n);
  };
  for (const s of scenes.filter((s) => s.seconds)) {
    const p = s.visual.props;
    const items =
      s.visual.component === "title"
        ? [["title", 1, [p.kicker, p.title, p.subtitle]]]
        : s.visual.component === "cards"
          ? p.items.map((x, i) => [
              `item ${i + 1}`,
              x.at,
              [x.label, x.value, x.note],
            ])
          : p.lines.map((x, i) => [`line ${i + 1}`, x.at, [x.text]]);
    const total = s.counts.reduce((a, b) => a + b, 0);
    for (const [name, at, texts] of items) {
      const after = s.counts.slice(at - 1).reduce((a, b) => a + b, 0);
      const shown = (s.seconds * after) / total;
      const need = texts.reduce((a, t) => a + floor(t), 0);
      if (shown < need)
        f.push(
          `${s.id} ${name}: ${shown.toFixed(1)} s on screen vs ${need.toFixed(1)} s to read`,
        );
    }
  }
  gates.reading = f;
}

// dashes: no em or en dash anywhere in the scene file.
gates.dashes = md
  .split(/\r?\n/)
  .flatMap((l, i) => [
    ...(/\u2014/.test(l) ? [`line ${i + 1} has an em dash`] : []),
    ...(/\u2013/.test(l) ? [`line ${i + 1} has an en dash`] : []),
  ]);

// sentences: over 25 spoken words warns.
const warns = scenes.flatMap((s) =>
  s.counts.flatMap((n, i) =>
    n > 25 ? [`${s.id} ${i + 1} has ${n} words (over 25)`] : [],
  ),
);

const checks = {};
for (const [name, f] of Object.entries(gates)) {
  checks[name] = { status: f.length ? "fail" : "pass", findings: f };
  console.log(`script ${name}: ${f.length ? `fail: ${f.join("; ")}` : "pass"}`);
}
checks.sentences = { status: warns.length ? "warn" : "pass", findings: warns };
console.log(
  `script sentences: ${warns.length ? `warn: ${warns.join("; ")}` : "pass"}`,
);
const failed = Object.values(checks).filter((c) => c.status === "fail").length;
fs.writeFileSync(
  file("check.json"),
  JSON.stringify({ checks, support }, null, 2) + "\n",
);
writeIgnore(run);
console.log(
  `script: ${Object.keys(checks).length - failed - (warns.length ? 1 : 0)} pass, ${failed} fail, ${warns.length ? 1 : 0} warn${
    !red
      ? ""
      : support.attempts >= 3
        ? "; stop: unsupported claims after two fix attempts"
        : `; next: fix attempt ${support.attempts} of 2`
  }`,
);
process.exit(failed ? 1 : 0);
