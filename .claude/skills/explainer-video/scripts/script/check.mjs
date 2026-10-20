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
//         (arc, budget, cites, support, coverage, reading, dashes,
//         sentences), then `script: <p> pass, <f> fail, <w> warn`, ending on
//         a red support verdict in `; next: fix attempt <a> of 2` or `; stop:
//         unsupported claims after two fix attempts`
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
import { blursDepth, findStyle, grammar } from "../lib/style.mjs";
import { VISUALS, findPhrase } from "../lib/visuals.mjs";
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
        if (seg.error) f.push(`${id}: ${ex.locator}: ${seg.error}`);
        else if (!seg.texts.some((t) => squash(t).includes(squash(ex.text))))
          f.push(`${id} is no longer word for word in ${ex.locator}`);
      }
    });
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
      ...strings(s.visual.props),
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

// reading: each visual item on screen long enough to read, from the sentence
// (or the `on` phrase) it rises at to the scene's end, timed by its share of
// the scene's words, or in a scene with an emphasis to the emphasis's cue for
// every item but the emphasised one, which the depth overlay blurs from then
// on (code takes none). A text of at most three words is a label, 0.8 s; a
// longer one 0.3 s a word and 1.2 s at least; an item's texts add up.
{
  const f = [];
  // The run's texture decides whether an emphasis blurs the other items; a
  // profile the render stage will refuse reads as the default one here.
  let texture = grammar({}).texture;
  try {
    texture = grammar(findStyle(run, script.style).profile).texture;
  } catch {}
  const floor = (t) => {
    const n = words(String(t ?? ""));
    return !n ? 0 : n <= 3 ? 0.8 : Math.max(1.2, 0.3 * n);
  };
  for (const s of scenes.filter((s) => s.seconds !== undefined)) {
    const items = VISUALS[s.visual.component].items(s.visual.props);
    const total = s.counts.reduce((a, b) => a + b, 0);
    const e = s.visual.props.emphasis;
    const depth = e && blursDepth(texture, s.visual.component);
    const upTo = (n) => s.counts.slice(0, n).reduce((a, b) => a + b, 0);
    for (const [name, at, texts, on] of items) {
      // An `on` phrase starts the item that many words into its sentence.
      const into = on === undefined ? 0 : findPhrase(s.narration[at - 1], on);
      const start = upTo(at - 1) + into;
      const blurred = depth && texts[0] !== e.target;
      const end = blurred
        ? upTo(e.at - 1) +
          (e.on === undefined ? 0 : findPhrase(s.narration[e.at - 1], e.on))
        : total;
      const shown = (s.seconds * (end - start)) / total;
      const read = texts.reduce((a, t) => a + floor(t), 0);
      if (shown < read)
        f.push(
          `${s.id} ${name}: ${shown.toFixed(1)} s on screen vs ${read.toFixed(1)} s to read`,
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
