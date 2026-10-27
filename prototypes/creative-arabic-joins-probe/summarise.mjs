// Scores results.json against truth.json: for each measure, how many broken
// words it caught and how many correct words or boxes it failed.
import fs from "node:fs";

const { cost, results } = JSON.parse(fs.readFileSync("results.json", "utf8"));
const truth = JSON.parse(fs.readFileSync("truth.json", "utf8"));
const WIDTH = Number(process.env.WIDTH ?? 0.5); // px of advance width
const PIXELS = Number(process.env.PIXELS ?? 0.3); // 1 - IoU of ink
const fails = {
  width: (r) => Math.abs(r.dw) > WIDTH,
  shaped: (r) => !r.same,
  pixels: (r) => r.pix > PIXELS,
};
const pct = (a, b) => (b ? `${a}/${b} (${((100 * a) / b).toFixed(1)}%)` : "-");
const out = {};
for (const [m, fail] of Object.entries(fails)) {
  const row = {
    caught: [0, 0],
    wordFP: [0, 0],
    boxFP: [0, 0],
    byFont: {},
    byStyle: {},
    missed: {},
  };
  const boxes = {};
  for (const r of results) {
    const tr = truth[`${r.font}/${r.box}`];
    const broken = tr.words[r.word];
    const f = fail(r);
    const k = `${r.font}/${r.box}@${r.t}`;
    boxes[k] ??= { ok: tr.words.every((w) => !w), failed: false };
    boxes[k].failed ||= f;
    if (broken) {
      row.caught[1]++;
      if (f) row.caught[0]++;
      else
        (row.missed[`${broken}`] ??= []).push(
          `${r.font} ${tr.style} ${r.text}`,
        );
    } else {
      row.wordFP[1]++;
      if (f) {
        row.wordFP[0]++;
        row.byFont[r.font] = (row.byFont[r.font] ?? 0) + 1;
        row.byStyle[tr.style] = (row.byStyle[tr.style] ?? 0) + 1;
      }
    }
  }
  for (const b of Object.values(boxes))
    if (b.ok) {
      row.boxFP[1]++;
      if (b.failed) row.boxFP[0]++;
    }
  out[m] = {
    caught: pct(...row.caught),
    wordFP: pct(...row.wordFP),
    boxFP: pct(...row.boxFP),
    fpByFont: row.byFont,
    fpByStyle: row.byStyle,
    missed: Object.fromEntries(
      Object.entries(row.missed).map(([k, v]) => [
        k,
        `${v.length}: ${[...new Set(v)].slice(0, 4).join("; ")}`,
      ]),
    ),
  };
}
// Spread on correct words, to see the margin under each threshold.
const ok = results.filter((r) => !truth[`${r.font}/${r.box}`].words[r.word]);
const bad = results.filter((r) => truth[`${r.font}/${r.box}`].words[r.word]);
const q = (a, p) =>
  a.sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(p * a.length))];
out.spread = {
  okAbsDw: {
    p50: q(
      ok.map((r) => Math.abs(r.dw)),
      0.5,
    ),
    p99: q(
      ok.map((r) => Math.abs(r.dw)),
      0.99,
    ),
    max: q(
      ok.map((r) => Math.abs(r.dw)),
      1,
    ),
  },
  badAbsDw: {
    min: q(
      bad.map((r) => Math.abs(r.dw)),
      0,
    ),
    p10: q(
      bad.map((r) => Math.abs(r.dw)),
      0.1,
    ),
  },
  okPix: {
    p50: q(
      ok.map((r) => r.pix),
      0.5,
    ),
    p99: q(
      ok.map((r) => r.pix),
      0.99,
    ),
    max: q(
      ok.map((r) => r.pix),
      1,
    ),
  },
  badPix: {
    min: q(
      bad.map((r) => r.pix),
      0,
    ),
    p10: q(
      bad.map((r) => r.pix),
      0.1,
    ),
  },
};
out.costMs = cost;
console.log(JSON.stringify(out, null, 1));
