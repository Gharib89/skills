// Voice QC (ADR 0016): the aligner's greedy transcript against the narration,
// so a garbled, cut or looped render blocks before anything is built on it.
// Floors from the spec: content-word recall 0.8 (cuts and mumbles), precision
// 0.85 (loops and invented speech), and 9 to 22 characters per second.
export const FLOORS = { recall: 0.8, precision: 0.85, rate: [9, 22] };

// English function words: a content word is any other word of two letters or more.
const STOP = new Set(
  `a an the and or but if of to in on at by for with from as is are was were be
  been being it its this that these those there here we you he she they i me my
  our your his her their them us do does did not no so than then too very can
  will would should could may might must has have had into out up down over
  about just what which who whom when where why how all any each some such only
  own same also both`.split(/\s+/),
);

const words = (text) =>
  text
    .toLowerCase()
    .replace(/[^a-z0-9' ]+/g, " ")
    .split(/\s+/)
    .filter(Boolean);
const content = (ws) =>
  ws.filter((w) => w.length > 1 && !STOP.has(w) && !/\d/.test(w));

function similar(a, b) {
  if (a === b) return true;
  const d = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let diag = d[0];
    d[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const up = d[j];
      d[j] = Math.min(
        d[j] + 1,
        d[j - 1] + 1,
        diag + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
      diag = up;
    }
  }
  // A model hearing a rare name spells it near enough: 60 percent of letters.
  return 1 - d[b.length] / Math.max(a.length, b.length) >= 0.6;
}

// One scene's verdict: each measured value, and a failure line per floor or band missed.
export function check(narration, transcript, seconds) {
  const ref = content(words(narration));
  const hyp = content(words(transcript));
  const hit = new Array(ref.length).fill(false);
  const used = new Array(hyp.length).fill(false);
  const free = (k) => k < hyp.length && !used[k];
  // The model splits or joins compounds ("work tree" for "worktree", "readyfull"
  // for "ready pull"), so a word also matches two adjacent words of the other side.
  ref.forEach((w, i) => {
    let k = hyp.findIndex((h, j) => free(j) && similar(w, h));
    if (k >= 0) return (hit[i] = used[k] = true);
    k = hyp.findIndex(
      (h, j) => free(j) && free(j + 1) && similar(w, h + hyp[j + 1]),
    );
    if (k >= 0) hit[i] = used[k] = used[k + 1] = true;
  });
  ref.forEach((w, i) => {
    if (hit[i] || i + 1 >= ref.length || hit[i + 1]) return;
    const k = hyp.findIndex((h, j) => free(j) && similar(w + ref[i + 1], h));
    if (k >= 0) hit[i] = hit[i + 1] = used[k] = true;
  });
  const count = (xs) => xs.filter(Boolean).length;
  const recall = ref.length ? count(hit) / ref.length : 1;
  const precision = hyp.length ? count(used) / hyp.length : 0;
  const rate = seconds > 0 ? narration.length / seconds : 0;
  const r2 = (n) => Math.round(n * 100) / 100;
  const out = {
    recall: r2(recall),
    precision: r2(precision),
    rate: r2(rate),
    failures: [],
  };
  if (recall < FLOORS.recall)
    out.failures.push(`recall ${out.recall} under ${FLOORS.recall}`);
  if (precision < FLOORS.precision)
    out.failures.push(`precision ${out.precision} under ${FLOORS.precision}`);
  if (rate < FLOORS.rate[0] || rate > FLOORS.rate[1])
    out.failures.push(
      `rate ${out.rate} chars/s outside ${FLOORS.rate[0]} to ${FLOORS.rate[1]}`,
    );
  return out;
}
