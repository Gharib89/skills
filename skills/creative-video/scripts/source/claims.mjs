// The claims check: the narration checked against the source pack and the
// support checker's verdicts before anything is voiced, carried from
// explainer-video's script gates (cites and support only).
//
//   node claims.mjs <run-folder>
//
// Reads <run>/script.json (each scene's `cites`, one list of excerpt ids per
// narration sentence, [] for a sentence stating no fact), excerpts.json and
// support.json, which the support checker writes:
//   { "sentences": [{ "scene", "n", "text", "cites", "verdict", "why" }] }
// A verdict on another wording or other cites, or one older than
// excerpts.json, judges nothing; `verdict` is supported or connective (a
// pass), unsupported or unmarked (an uncited sentence that states a fact).
// stdout: `claims <check>: pass|fail: <findings>|warn: <findings>` for cites
//         and support, then `claims: <p> pass, <f> fail, <w> warn`, ending on
//         a red support verdict in `; next: fix attempt <a> of 2` or `; stop:
//         unsupported claims after two fix attempts`
// writes: <run>/claims.json: each check, the support attempts, each sentence's
//         kept verdict, and `passed`, the claims key (lib/claims.mjs) of a
//         script that passed, which the gates' support gate reads
// exit:   0 no check failed · 1 a check failed, or `claims: no <file>: <why>`
//         or `claims: <file>: <field> <problem>` on stderr · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { claimsKey } from "../lib/claims.mjs";
import { maybeJson, readJson } from "../lib/json.mjs";
import { stage } from "../lib/stage.mjs";

stage("claims");
const MAX_ATTEMPTS = 2;
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node claims.mjs <run-folder>");
  process.exit(2);
}
const file = (f) => path.join(run, f);
for (const [f, why] of [
  ["script.json", "write the script first"],
  ["excerpts.json", "run the source stage first"],
])
  if (!fs.existsSync(file(f))) {
    console.error(`claims: no ${f}: ${why}`);
    process.exit(1);
  }
const script = readJson(run, "script.json");
const pack = readJson(run, "excerpts.json");
const { scenes } = script;
const checks = {};

// cites: one list per sentence, every id an excerpt of the pack.
{
  const f = [];
  const ids = new Set(pack.excerpts.map((x) => x.id));
  for (const s of scenes) {
    if (!s.cites) {
      f.push(
        `${s.id}: no cites, one list of excerpt ids per sentence, [] for a sentence stating no fact`,
      );
      continue;
    }
    if (s.cites.length !== s.narration.length)
      f.push(
        `${s.id}: ${s.narration.length} sentence(s), ${s.cites.length} cites list(s)`,
      );
    s.cites.forEach((cites, i) => {
      for (const id of cites)
        if (!ids.has(id))
          f.push(`${s.id} ${i + 1}: ${id} is not in excerpts.json`);
    });
  }
  checks.cites = f;
}

// support: every sentence judged, on its present wording, as supported or
// connective. The checker judges afresh each time, so a sentence whose place,
// words, cites and cited excerpts' words are unchanged keeps the first verdict
// it got, and a different one is drift: a warn, never a new failure or fix
// attempt.
const record = maybeJson(run, "claims.json");
let support = record?.support ?? { attempts: 0, judged: null };
let red = false;
const drift = [];
{
  const f = [];
  const excerpt = new Map(pack.excerpts.map((x) => [x.id, x.text]));
  const keyOf = (...sentence) =>
    crypto
      .createHash("sha256")
      .update(
        JSON.stringify([
          ...sentence,
          sentence.at(-1).map((c) => excerpt.get(c)),
        ]),
      )
      .digest("hex");
  const kept = support.verdicts ?? {};
  const verdictsNow = {};
  const mtime = (f) => fs.statSync(file(f)).mtimeMs;
  if (checks.cites.length)
    f.push("the cites fail: fix them, then run the support check");
  else if (!fs.existsSync(file("support.json")))
    f.push("no support.json: run the support check");
  // A new pack can put other words behind the same excerpt id.
  else if (mtime("excerpts.json") > mtime("support.json"))
    f.push("support.json predates excerpts.json: run the support check");
  else {
    const verdicts = readJson(run, "support.json").sentences;
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
    // judged; past the last fix attempt the stop holds until the check passes.
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
  checks.support = f;
}

// A check's warnings print after its failures, and warn it only when none fails.
const warned = { support: drift };
const out = {};
for (const [name, f] of Object.entries(checks)) {
  const findings = [...f, ...(warned[name] ?? [])];
  const status = f.length ? "fail" : findings.length ? "warn" : "pass";
  out[name] = { status, findings };
  console.log(
    `claims ${name}: ${status}${findings.length ? `: ${findings.join("; ")}` : ""}`,
  );
}
const count = (status) =>
  Object.values(out).filter((c) => c.status === status).length;
const failed = count("fail");
fs.writeFileSync(
  file("claims.json"),
  JSON.stringify(
    {
      checks: out,
      support,
      ...(failed ? {} : { passed: claimsKey(script, pack) }),
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `claims: ${count("pass")} pass, ${failed} fail, ${count("warn")} warn${
    !red
      ? ""
      : support.attempts > MAX_ATTEMPTS
        ? "; stop: unsupported claims after two fix attempts"
        : `; next: fix attempt ${support.attempts} of ${MAX_ATTEMPTS}`
  }`,
);
process.exit(failed ? 1 : 0);
