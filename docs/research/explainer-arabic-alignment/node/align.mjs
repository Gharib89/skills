// Node probe: CTC forced alignment with onnxruntime-node and a Viterbi pass in plain JS.
// Usage: node align.mjs <model.onnx> <tokens.json> <f32le-16k files...>
// tokens.json: { blank, sep, clips: { name: { words: [...], toks: [[id...]...] } } }
import * as ort from "onnxruntime-node";
import { readFileSync } from "node:fs";

const [modelPath, tokPath, ...files] = process.argv.slice(2);
const T = JSON.parse(readFileSync(tokPath, "utf8"));
let t0 = performance.now();
const sess = await ort.InferenceSession.create(modelPath, { intraOpNumThreads: 0 });
const out = { _meta: { model: modelPath, load_s: (performance.now() - t0) / 1000 } };

function viterbi(lp, nT, C, tgt, blank) {
  // lp: Float32Array nT*C log-probs. Returns per-frame index into the extended (blank-interleaved) target.
  const S = 2 * tgt.length + 1, ext = Array.from({ length: S }, (_, s) => (s % 2 ? tgt[(s - 1) >> 1] : blank));
  const NEG = -1e30, dp = new Float64Array(nT * S).fill(NEG), bp = new Int8Array(nT * S);
  dp[0] = lp[ext[0]]; dp[1] = lp[ext[1]];
  for (let t = 1; t < nT; t++) {
    for (let s = Math.max(0, S - 2 * (nT - t)); s < Math.min(S, 2 * t + 2); s++) {
      let best = dp[(t - 1) * S + s], k = 0;
      if (s > 0 && dp[(t - 1) * S + s - 1] > best) { best = dp[(t - 1) * S + s - 1]; k = 1; }
      if (s > 1 && ext[s] !== blank && ext[s] !== ext[s - 2] && dp[(t - 1) * S + s - 2] > best) { best = dp[(t - 1) * S + s - 2]; k = 2; }
      dp[t * S + s] = best + lp[t * C + ext[s]]; bp[t * S + s] = k;
    }
  }
  let s = dp[nT * S - 1] > dp[nT * S - 2] ? S - 1 : S - 2;
  const path = new Int32Array(nT);
  for (let t = nT - 1; t >= 0; t--) { path[t] = s; s -= bp[t * S + s]; }
  return path;
}

let audio = 0, proc = 0;
for (const f of files) {
  const name = f.split("/").pop().replace(".f32", "");
  const b = readFileSync(f);
  const raw = new Float32Array(b.buffer, b.byteOffset, b.length / 4);
  const t = performance.now();
  let mean = 0, sq = 0;
  for (const v of raw) mean += v;
  mean /= raw.length;
  for (const v of raw) sq += (v - mean) ** 2;
  const sd = Math.sqrt(sq / raw.length + 1e-7), x = raw.map((v) => (v - mean) / sd); // Wav2Vec2 feature-extractor normalisation
  const r = await sess.run({ audio: new ort.Tensor("float32", x, [1, x.length]) });
  const [, nT, C] = r.logits.dims, lg = r.logits.data, lp = new Float32Array(nT * C);
  for (let i = 0; i < nT; i++) { // log-softmax per frame
    let m = -Infinity, z = 0;
    for (let c = 0; c < C; c++) m = Math.max(m, lg[i * C + c]);
    for (let c = 0; c < C; c++) z += Math.exp(lg[i * C + c] - m);
    for (let c = 0; c < C; c++) lp[i * C + c] = lg[i * C + c] - m - Math.log(z);
  }
  const { words, toks } = T.clips[name];
  const tgt = [], owner = [];
  toks.forEach((tk, w) => { if (w) { tgt.push(T.sep); owner.push(-1); } tk.forEach((id) => { tgt.push(id); owner.push(w); }); });
  const path = viterbi(lp, nT, C, tgt, T.blank), sec = raw.length / 16000 / nT;
  const res = words.map((w) => [w, null, null]);
  for (let i = 0; i < nT; i++) {
    if (path[i] % 2 === 0) continue;
    const w = owner[(path[i] - 1) >> 1];
    if (w < 0) continue;
    if (res[w][1] === null) res[w][1] = +(i * sec).toFixed(3);
    res[w][2] = +((i + 1) * sec).toFixed(3);
  }
  const dt = (performance.now() - t) / 1000;
  audio += raw.length / 16000; proc += dt;
  out[name] = res;
}
Object.assign(out._meta, { audio_s: audio, proc_s: proc, rtf: proc / audio, rss_mb: process.memoryUsage().rss / 1e6 });
console.log(JSON.stringify(out));
