// Shared fixtures of the support tests: a run folder's source pack and the
// support checker's verdicts, written the way pack.mjs and
// agents/support-checker.md write them, and the runner of the script check.
import fs from "node:fs";
import path from "node:path";
import { here } from "./voice-lib.mjs";
import { exec } from "./timing-lib.mjs";

export const check = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
  "script",
  "check.mjs",
);

export const EXCERPTS = [
  {
    id: "ex-1",
    source: "s1",
    locator: "§ Run",
    text: "Ship drives one issue to a merged pull request.",
  },
  {
    id: "ex-2",
    source: "s1",
    locator: "§ Claim",
    text: "It claims the issue before any work so no other run takes it.",
  },
];

// `scenes` with every sentence given `cites`: `[]` (no claim) unless `cites`
// maps a scene id to its lists.
export const cited = (scenes, cites = {}) =>
  scenes.map((s) => ({
    ...s,
    cites: cites[s.id] ?? s.narration.map(() => []),
  }));

export function pack(fx, excerpts = EXCERPTS) {
  fs.writeFileSync(
    path.join(fx.dir, "excerpts.json"),
    JSON.stringify({ sources: [], excerpts }),
  );
}

// support.json judging every sentence of `scenes` (each with cites): `verdict`
// maps "<scene> <n>" to a verdict, the rest `supported` when cited, else
// `connective`.
export function judge(fx, scenes, verdict = {}) {
  const sentences = scenes.flatMap((s) =>
    s.narration.map((text, i) => ({
      scene: s.id,
      n: i + 1,
      text,
      cites: s.cites[i],
      verdict:
        verdict[`${s.id} ${i + 1}`] ??
        (s.cites[i].length ? "supported" : "connective"),
      why: "fixture",
    })),
  );
  fs.writeFileSync(
    path.join(fx.dir, "support.json"),
    JSON.stringify({ sentences }),
  );
}

export const runCheck = (fx) => exec(check, fx);
