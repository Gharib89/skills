// Node probe: Transformers.js Whisper word timestamps on CPU. Usage: node whisper.mjs <model> <dtype> <f32le-16k files...>
import { pipeline } from "@huggingface/transformers";
import { readFileSync } from "node:fs";

const [model, dtype, ...files] = process.argv.slice(2);
let t = performance.now();
const asr = await pipeline("automatic-speech-recognition", model, { dtype, device: "cpu" });
const load_s = (performance.now() - t) / 1000;
const out = { _meta: { model, dtype, load_s } };
let audio = 0, proc = 0;
for (const f of files) {
  const b = readFileSync(f);
  const x = new Float32Array(b.buffer, b.byteOffset, b.length / 4);
  t = performance.now();
  const r = await asr(x, { language: "arabic", task: "transcribe", return_timestamps: "word", chunk_length_s: 30 });
  const dt = (performance.now() - t) / 1000;
  audio += x.length / 16000; proc += dt;
  out[f.split("/").pop().replace(".f32", "")] = { text: r.text, sec: dt, words: r.chunks.map((c) => [c.text.trim(), c.timestamp[0], c.timestamp[1]]) };
  console.error(dt.toFixed(1), f, r.text.slice(0, 80));
}
Object.assign(out._meta, { audio_s: audio, proc_s: proc, rtf: proc / audio, rss_mb: process.memoryUsage().rss / 1e6 });
console.log(JSON.stringify(out));
