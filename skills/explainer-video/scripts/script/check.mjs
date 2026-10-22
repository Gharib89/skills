// The script gates: the compiled script checked against the brief, the source
// pack and the support checker's verdicts before anything is voiced.
//
//   node check.mjs <run-folder>
//
// Reads <run>/script.json, script.md, brief.json, excerpts.json, the
// snapshots when present, and support.json, which the support checker writes:
//   { "sentences": [{ "scene", "n", "text", "cites", "verdict", "why" }] }
// `text` and `cites` are the sentence's compiled narration and excerpt ids,
// so a verdict on another wording or other cites, or one older than
// excerpts.json, judges nothing; `verdict` is supported or connective (a pass),
// unsupported or unmarked (a [no-claim] sentence that makes a claim).
// stdout: `script <gate>: pass|fail: <findings>|warn: <findings>` per gate
//         (arc, budget, cites, support, coverage, dashes, sentences), then
//         `script: <p> pass, <f> fail, <w> warn`, ending on a red support
//         verdict in `; next: fix attempt <a> of 2` or `; stop: unsupported
//         claims after two fix attempts`
// writes: <run>/check.json, the machine record, the support attempts and each
//         sentence's kept verdict
// exit:   0 no gate failed · 1 a gate failed, or `script: no <input>: <why>`
//         on stderr when an input is missing or names no narrator · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { HOLD, chars, fitsLength, sentences } from "../lib/length.mjs";
import { narrator as findNarrator } from "../lib/narrators.mjs";
import { writeIgnore } from "../lib/runfolder.mjs";
import { plain } from "../lib/count.mjs";
import { numberIn } from "../lib/figures.mjs";
import { VISUALS } from "../lib/visuals.mjs";
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

const narrator = findNarrator(script.narrator, script.language);
if (!narrator) {
  console.error(
    `script: no narrator ${script.narrator ?? script.language}: set the brief's voice and compile again`,
  );
  process.exit(1);
}
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

// budget: 12 to 30 s a scene, its spoken characters within 10 percent of its
// seconds, less the narrator's pause a sentence, at the narrator's rate, and
// the scenes with the render's closing hold within 10 percent of the brief's
// length.
{
  const f = [];
  for (const s of scenes.filter((s) => s.seconds !== undefined)) {
    if (s.seconds < 12 || s.seconds > 30)
      f.push(`${s.id} ${s.seconds} s is outside 12 to 30 s`);
    const stops = sentences(s.narration.join(" ")).length;
    const budget = (s.seconds - stops * narrator.pause) * narrator.rate;
    const n = chars(s.narration.join(" "));
    if (Math.abs(n - budget) > budget * 0.1)
      f.push(
        `${s.id} ${n} spoken characters ({written|spoken} counts its spoken form) vs ${Math.round(budget)} (${s.seconds} s less ${stops} sentences at ${narrator.pause} s, at ${narrator.rate} chars/s) ±10%`,
      );
  }
  const total = scenes.reduce((a, s) => a + (s.seconds ?? 0), 0);
  if (!fitsLength(total, brief.length))
    f.push(
      `the scenes run ${total} s and the ${HOLD} s hold vs the brief's ${brief.length * 60} s ±10%`,
    );
  gates.budget = f;
}

// cites: every cite in the pack, each cited excerpt still word for word in its
// snapshot when the snapshots are there, and every number a scene shows on
// screen (`numbers` of its component) standing as written in an excerpt the
// scene cites: whole, so 200 is not found in 1,200 nor 5 in 0.5.
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
        if (seg.error) f.push(`${id}: ${ex.locator}: ${seg.error}`);
        else if (!seg.texts.some((t) => squash(t).includes(squash(ex.text))))
          f.push(`${id} is no longer word for word in ${ex.locator}`);
      }
    });
  for (const s of scenes) {
    const shown = VISUALS[s.visual.component].numbers?.(s.visual.props) ?? [];
    const ids = [...new Set(s.cites.flat())];
    const texts = ids.map((id) => byId.get(id)?.text ?? "");
    for (const n of shown) {
      if (texts.some((t) => numberIn(t, n))) continue;
      // The same number in another digit script is a near miss worth naming:
      // the video shows the excerpt's own digits.
      const hint = texts.some((t) => numberIn(plain(t), plain(n)))
        ? "; the excerpt writes it in another digit script, so write it as the excerpt does"
        : "";
      f.push(
        `${s.id}: on-screen number "${n}" is in none of ${ids.join(", ") || "its cites (it has none)"}${hint}`,
      );
    }
  }
  gates.cites = f;
}

// support: every sentence judged, on its present wording, as supported or
// connective. The checker judges afresh each time, so a sentence whose place,
// words, cites and cited excerpts' words are unchanged keeps the first verdict
// it got, and a different one is drift: a warn, never a new failure or fix
// attempt.
const record = fs.existsSync(file("check.json"))
  ? JSON.parse(fs.readFileSync(file("check.json"), "utf8"))
  : null;
let support = record?.support ?? { attempts: 0, judged: null };
let red = false;
const drift = [];
{
  const f = [];
  const excerpt = new Map(pack.excerpts.map((x) => [x.id, x.text]));
  const keyOf = (id, n, text, cites) =>
    crypto
      .createHash("sha256")
      .update(
        JSON.stringify([id, n, text, cites, cites.map((c) => excerpt.get(c))]),
      )
      .digest("hex");
  const kept = support.verdicts ?? {};
  const verdictsNow = {};
  const mtime = (f) => fs.statSync(file(f)).mtimeMs;
  if (!fs.existsSync(file("support.json")))
    f.push("no support.json: run the support check");
  // A new pack can put other words behind the same excerpt id.
  else if (mtime("excerpts.json") > mtime("support.json"))
    f.push("support.json predates excerpts.json: run the support check");
  else {
    const raw = fs.readFileSync(file("support.json"), "utf8");
    const verdicts = JSON.parse(raw).sentences ?? [];
    let judged = true;
    const failing = [];
    for (const s of scenes)
      s.narration.forEach((text, i) => {
        const now = verdicts.find(
          (x) =>
            x.scene === s.id &&
            x.n === i + 1 &&
            x.text === text &&
            JSON.stringify(x.cites) === JSON.stringify(s.cites[i]),
        );
        const key = keyOf(s.id, i + 1, text, s.cites[i]);
        const v = kept[key] ?? now;
        if (v) verdictsNow[key] = { verdict: v.verdict, why: v.why };
        if (!now) {
          judged = false;
          f.push(`${s.id} ${i + 1} not judged: run the support check`);
          return;
        }
        if (v.verdict !== now.verdict)
          drift.push(
            `${s.id} ${i + 1} drift: judged ${now.verdict} on unchanged words, kept ${v.verdict}`,
          );
        if (!["supported", "connective"].includes(v.verdict)) {
          f.push(`${s.id} ${i + 1} ${v.verdict}: ${v.why}`);
          failing.push([s.id, i + 1, text, s.cites[i], v.verdict]);
        }
      });
    const hash = crypto
      .createHash("sha256")
      .update(JSON.stringify(failing))
      .digest("hex");
    const prev = support;
    // A red set of failing sentences is one fix attempt, however often it is
    // judged; past the last fix attempt the stop holds until the gate passes.
    red = judged && f.length > 0;
    support = {
      ...(red
        ? {
            attempts: prev.attempts + (prev.judged === hash ? 0 : 1),
            judged: hash,
          }
        : judged
          ? { attempts: 0, judged: hash }
          : prev),
      verdicts: verdictsNow,
    };
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
      // a component may name the props a viewer reads, as custom does for its
      // source, whose style and script are not text on screen
      ...strings(
        VISUALS[s.visual.component]?.shown?.(s.visual.props) ?? s.visual.props,
      ),
    ]
      .join("\n")
      .toLowerCase();
  // A whole-word match, so `avoid=AI` is not hit by "explain".
  const has = (s, item) => {
    const quoted = item.toLowerCase().replace(/[.*+?^$|()[\]{}\\]/g, "\\$&");
    return new RegExp(
      `(?<![\\p{L}\\p{N}])${quoted}(?![\\p{L}\\p{N}])`,
      "u",
    ).test(text(s));
  };
  for (const m of brief.must)
    if (!scenes.some((s) => has(s, m)))
      f.push(`must "${m}" is not said or shown`);
  for (const a of brief.avoid) {
    const hit = scenes.filter((s) => has(s, a));
    if (hit.length)
      f.push(`avoid "${a}" is in ${hit.map((s) => s.id).join(", ")}`);
  }
  gates.coverage = f;
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

// A gate's warnings print after its failures, and warn it only when none fails.
gates.sentences = [];
const warned = { support: drift, sentences: warns };
const checks = {};
for (const [name, f] of Object.entries(gates)) {
  const findings = [...f, ...(warned[name] ?? [])];
  const status = f.length ? "fail" : findings.length ? "warn" : "pass";
  checks[name] = { status, findings };
  console.log(
    `script ${name}: ${status}${findings.length ? `: ${findings.join("; ")}` : ""}`,
  );
}
const count = (status) =>
  Object.values(checks).filter((c) => c.status === status).length;
const failed = count("fail");
fs.writeFileSync(
  file("check.json"),
  JSON.stringify({ checks, support }, null, 2) + "\n",
);
writeIgnore(run);
console.log(
  `script: ${count("pass")} pass, ${failed} fail, ${count("warn")} warn${
    !red
      ? ""
      : support.attempts > 2
        ? "; stop: unsupported claims after two fix attempts"
        : `; next: fix attempt ${support.attempts} of 2`
  }`,
);
process.exit(failed ? 1 : 0);
