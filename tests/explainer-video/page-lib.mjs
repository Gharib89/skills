// Shared by the storyboard page tests: the page's code run headless in a vm,
// the documented shape of board-data.md, and a session over sample boards whose
// reads are recorded through proxies.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const skill = path.join(here, "..", "..", "skills", "explainer-video");
export const read = (f) => fs.readFileSync(f, "utf8");
export const html = read(path.join(skill, "storyboard", "page.html"))
  // The page links its style and scripts as siblings; inline them to test the whole.
  .replace(
    /<link rel="stylesheet" href="([^":]+)">/g,
    (_, f) => `<style>\n${read(path.join(skill, "storyboard", f))}</style>`,
  )
  .replace(
    /(<script src="[^":]+"><\/script>\n?)+/,
    (m) =>
      `<script>\n${[...m.matchAll(/src="([^"]+)"/g)].map((x) => read(path.join(skill, "storyboard", x[1]))).join("")}</script>\n`,
  );
export const doc = read(path.join(skill, "storyboard", "board-data.md"));
export const sample = (n) =>
  JSON.parse(read(path.join(here, "board-fixtures", `${n}.json`)));
// The page runs in its own vm realm: plain copies compare equal to ours.
export const clone = (o) => JSON.parse(JSON.stringify(o));

// The documented shape: every table row whose first cell is a board. or answers. path.
export const shape = new Map();
for (const m of doc.matchAll(
  /^\| `((?:board|answers)\.[^`]+)` \| [^|]+ \| (\w+) \|/gm,
))
  shape.set(m[1], m[2]);

// Every object in a document with its path, `[]` standing for an array element.
export function objects(v, p, acc = []) {
  if (Array.isArray(v)) v.forEach((x) => objects(x, p + "[]", acc));
  else if (v && typeof v === "object") {
    acc.push([p, v]);
    for (const k of Object.keys(v)) objects(v[k], p + "." + k, acc);
  }
  return acc;
}
export function shapeProblems(d, root) {
  const out = [];
  const all = objects(d, root);
  for (const [p, o] of all)
    for (const k of Object.keys(o))
      if (!shape.has(p + "." + k)) out.push(`undocumented field ${p}.${k}`);
  for (const [f, req] of shape) {
    if (!f.startsWith(root + ".") || req === "no") continue;
    const parent = f.slice(0, f.lastIndexOf("."));
    const key = f.slice(f.lastIndexOf(".") + 1);
    for (const [p, o] of all)
      if (p === parent && !(key in o) && ["yes", d.kind].includes(req))
        out.push(`lacks required field ${f}`);
  }
  return out;
}

// The page's code, run with no document so it boots nothing and exposes its core.
export const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);
export const ctx = vm.createContext({ console });
vm.runInContext(
  scripts[0] +
    "\n;globalThis.__page = { newState, setBoards, setAnswers, view, ACT, canSubmit, answersDoc, answersText, mediaUrl, outcome, loopOf, sceneAt, buildOf };",
  ctx,
);
export const P = ctx.__page;
export const seen = new Set();
export function watch(v, p) {
  if (!v || typeof v !== "object") return v;
  return new Proxy(v, {
    get(t, k, r) {
      if (typeof k === "symbol") return Reflect.get(t, k, r);
      if (Array.isArray(t))
        return /^\d+$/.test(k) ? watch(t[k], p + "[]") : Reflect.get(t, k, r);
      seen.add(p + "." + k);
      return watch(t[k], p + "." + k);
    },
  });
}
export function session(docs, answered = []) {
  const S = P.newState("How Ship lands a pull request");
  P.setBoards(
    S,
    docs.map((d) => watch(clone(d), "board")),
  );
  P.setAnswers(
    S,
    answered.map((a) => watch(a, "answers")),
  );
  P.view(S);
  return S;
}
export const submitDisabled = (v) =>
  /<button[^>]*id="submit"[^>]*\sdisabled/.test(v) ||
  /<button[^>]*\sdisabled[^>]*id="submit"/.test(v);
