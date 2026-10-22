// Shared fixtures of the parts tests: a run folder with a brief and a source
// pack, and the part plan the agent writes into it.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { node, temps } from "./check-lib.mjs";

export { node };

// A run folder `explainers/demo` whose brief asks for `length` minutes and
// whose pack holds `excerpts` excerpts, ex-1 on.
export function fixture({ length = 12, excerpts = 12, brief = [] } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-parts-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const fx = { tmp, dir };
  const b = node(fx, "brief/brief.mjs", [`length=${length}`, ...brief]);
  assert.equal(b.code, 0, b.err);
  fs.writeFileSync(
    path.join(dir, "excerpts.json"),
    JSON.stringify({
      minutes: length,
      budget: 96,
      sources: [{ id: "doc", kind: "md", source: "doc.md", title: "Ship" }],
      excerpts: Array.from({ length: excerpts }, (_, i) => ({
        id: `ex-${i + 1}`,
        source: "doc",
        locator: `line ${i + 1}`,
        text: `Fact number ${i + 1}.`,
        note: `note ${i + 1}`,
      })),
    }),
  );
  return fx;
}

export const parts = (fx, ...args) => node(fx, "parts/parts.mjs", args);

// A plan of parts of `minutes` each, `per` excerpts to a part in pack order.
export function plan(minutes, per = 4) {
  return {
    parts: minutes.map((m, i) => ({
      title:
        ["Claiming work", "Opening the PR", "Landing it"][i] ?? `Part ${i + 1}`,
      focus: `what happens in step ${i + 1}`,
      minutes: m,
      excerpts: Array.from({ length: per }, (_, k) => `ex-${i * per + k + 1}`),
    })),
  };
}

export const writePlan = (fx, p) =>
  fs.writeFileSync(path.join(fx.dir, "parts.json"), JSON.stringify(p));
export const readJson = (...p) =>
  JSON.parse(fs.readFileSync(path.join(...p), "utf8"));

// The pack's snapshot, one line a fact, so a cite still reads word for word
// where the run folder keeps it: with the run, not with a part.
export function snapshot(fx, excerpts = 12) {
  const snaps = path.join(fx.dir, "snapshots");
  fs.mkdirSync(snaps, { recursive: true });
  fs.writeFileSync(
    path.join(snaps, "doc.md"),
    Array.from({ length: excerpts }, (_, i) => `Fact number ${i + 1}.`).join(
      "\n",
    ),
  );
  fs.writeFileSync(
    path.join(snaps, "sources.json"),
    JSON.stringify({
      minutes: 6,
      budget: 48,
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
}

// Part `folder` rendered and delivered, as render leaves it.
export function deliver(fx, folder) {
  const out = path.join(fx.tmp, "videos");
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, `${folder}.mp4`), "mp4");
  fs.writeFileSync(
    path.join(fx.dir, "parts", folder, "manifest.json"),
    JSON.stringify({ delivered: out }),
  );
}
