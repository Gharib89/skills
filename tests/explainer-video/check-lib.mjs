// Shared fixtures of the script check tests: a scene file, a run folder and
// the stage and verdict runners.
import { after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { sentences } from "../../skills/explainer-video/scripts/lib/length.mjs";

export const here = path.dirname(fileURLToPath(import.meta.url));
export const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
);

export const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

export const VOCAB =
  "ship reads the issue then writes a failing test and the code that makes it pass before review".split(
    " ",
  );
export const spoken = (n) =>
  Array.from({ length: n }, (_, i) => VOCAB[i % VOCAB.length]).join(" ");
// A sentence of n spoken words ending in its cites.
export const say = (n, cites = "[ex-1]") => `${spoken(n)}. ${cites}`;

export const TITLE = { component: "title", props: { title: "The local gate" } };

// bf_emma speaks 16.55 characters a second and pauses 0.78 s a sentence, so a
// 12 s scene of three sentences budgets (12 - 2.34) x 16.55 = 160 characters,
// which three 12-word sentences of 49 characters meet, and a one-minute brief
// takes five such scenes and the 1 s hold.
export const SCENES = [
  { id: "hook", role: "hook" },
  { id: "why", role: "context" },
  { id: "steps", role: "point" },
  { id: "recap", role: "recap" },
  { id: "bye", role: "end" },
].map((s) => ({
  ...s,
  seconds: 12,
  sentences: [say(12), say(12, "[no-claim]"), say(12, "[ex-2, ex-3]")],
  visual: TITLE,
}));

export function sceneFile(scenes) {
  return [
    "# How Ship lands a pull request",
    "",
    ...scenes.flatMap((s) => [
      `## Scene ${s.id} · ${s.id}`,
      ...(s.role ? [`role: ${s.role} · ${s.seconds} s`] : []),
      "",
      "### Narration",
      ...s.sentences.map((x, i) => `${i + 1}. ${x}`),
      "",
      "### Visual",
      "```json",
      JSON.stringify(s.visual),
      "```",
      "",
    ]),
  ].join("\n");
}

export const DOC =
  "# Ship\n\nShip reads the issue.\n\n## Gate\n\nThe local gate runs every check.\n";

export function node(fx, stage, args = []) {
  const r = spawnSync(
    process.execPath,
    [path.join(scripts, stage), fx.dir, ...args],
    {
      env: {
        PATH: process.env.PATH,
        HOME: path.join(fx.tmp, "home"),
        XDG_CONFIG_HOME: path.join(fx.tmp, "config"),
      },
      encoding: "utf8",
    },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

// Every sentence of the compiled script judged as its mark says, unless
// `verdicts` overrides one by `<scene> <n>`.
export function judge(fx, verdicts = {}) {
  const s = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "script.json"), "utf8"),
  );
  const sentences = s.scenes.flatMap((sc) =>
    sc.narration.map((text, i) => ({
      scene: sc.id,
      n: i + 1,
      text,
      cites: sc.cites[i],
      verdict:
        verdicts[`${sc.id} ${i + 1}`] ??
        (sc.cites[i].length ? "supported" : "connective"),
      why: "fixture",
    })),
  );
  fs.writeFileSync(
    path.join(fx.dir, "support.json"),
    JSON.stringify({ sentences }),
  );
}

export function fixture({
  scenes = SCENES,
  brief = ["length=1", "must=local gate", "avoid=pricing"],
  md,
} = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-check-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(path.join(dir, "snapshots"), { recursive: true });
  const fx = { tmp, dir };
  assert.equal(node(fx, "brief/brief.mjs", brief).code, 0);
  fs.writeFileSync(path.join(dir, "snapshots", "doc.md"), DOC);
  fs.writeFileSync(
    path.join(dir, "snapshots", "sources.json"),
    JSON.stringify({
      minutes: 1,
      budget: 12,
      sources: [
        {
          id: "doc",
          kind: "md",
          source: "doc.md",
          title: "Ship",
          snapshot: "doc.md",
          share: 12,
        },
      ],
    }),
  );
  const ex = (id, locator, text) => ({
    id,
    source: "doc",
    locator,
    text,
    note: "n",
  });
  fs.writeFileSync(
    path.join(dir, "excerpts.json"),
    JSON.stringify({
      minutes: 1,
      budget: 12,
      sources: [],
      excerpts: [
        ex("ex-1", "§ Ship", "Ship reads the issue."),
        ex("ex-2", "§ Gate", "The local gate runs every check."),
        ex("ex-3", "line 3", "Ship reads the issue."),
      ],
    }),
  );
  fs.writeFileSync(path.join(dir, "script.md"), md ?? sceneFile(scenes));
  const c = node(fx, "script/compile.mjs");
  assert.equal(c.code, 0, c.err);
  judge(fx);
  return fx;
}

export const check = (fx) => node(fx, "script/check.mjs");
export const line = (r, name) =>
  r.out.split("\n").find((l) => l.startsWith(`script ${name}:`));
export const edit = (scenes, i, patch) =>
  scenes.map((s, k) => (k === i ? { ...s, ...patch } : s));

// A fix rewrites each `<scene> <n>` sentence in script.json, its first word
// swapped for a fresh one, so its count and cites stay.
export let rewrites = 0;
export function reword(fx, ...keys) {
  const file = path.join(fx.dir, "script.json");
  const s = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const k of keys) {
    const [id, n] = k.split(" ");
    const sc = s.scenes.find((x) => x.id === id);
    sc.narration[n - 1] = sc.narration[n - 1].replace(
      /^\S+/,
      `rewrite${++rewrites}`,
    );
  }
  fs.writeFileSync(file, JSON.stringify(s));
}
